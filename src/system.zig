const std = @import("std");
const Allocator = std.mem.Allocator;

const pecs = @import("root.zig");
const Registry = pecs.Registry;

pub fn SystemTrait(comptime SystemType: type) type {
    return struct {
        pub fn validate() void {
            // Check if required functions exist with correct signatures
            if (!@hasDecl(SystemType, "init") or
                @TypeOf(SystemType.init) != fn (Allocator) anyerror!SystemType)
            {
                @compileError("System type must have init(Allocator) anyerror!SystemType");
            }

            if (!@hasDecl(SystemType, "deinit") or
                @TypeOf(SystemType.deinit) != fn (*SystemType) void)
            {
                @compileError("System type must have deinit(*Self) void");
            }

            if (!@hasDecl(SystemType, "update") or
                @TypeOf(SystemType.update) != fn (*SystemType, *Registry) anyerror!void)
            {
                @compileError("System type must have update(*Self, *Registry) anyerror!void");
            }
        }
    };
}

pub const TypeErasedSystem = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const SystemVTable,

    pub fn init(allocator: Allocator, comptime SystemType: type) !TypeErasedSystem {
        comptime SystemTrait(SystemType).validate();

        const system_ptr = try allocator.create(SystemType);
        system_ptr.* = try SystemType.init(allocator);

        return TypeErasedSystem{
            .allocator = allocator,
            .ptr = system_ptr,
            .vtable = &comptime makeSystemVTable(SystemType),
        };
    }

    pub fn deinit(self: TypeErasedSystem) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn update(self: TypeErasedSystem, registry: *Registry) anyerror!void {
        try self.vtable.update(self.ptr, registry);
    }

    pub fn cast(type_erased_system_ptr: *anyopaque, comptime SystemType: type) *SystemType {
        return @alignCast(@ptrCast(type_erased_system_ptr));
    }
};

/// Virtual function table for type-erased systems.
pub const SystemVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    update: *const fn (*anyopaque, *Registry) anyerror!void,
};

pub fn makeSystemVTable(comptime SystemType: type) SystemVTable {
    return SystemVTable{
        .deinit = (struct {
            fn func(allocator: Allocator, type_erased_system_ptr: *anyopaque) void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, SystemType);
                system.deinit();
                allocator.destroy(system);
            }
        }).func,
        .update = (struct {
            fn func(type_erased_system_ptr: *anyopaque, registry: *Registry) anyerror!void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, SystemType);
                try system.update(registry);
            }
        }).func,
    };
}

pub const SystemManager = struct {
    allocator: Allocator,
    tagged_systems: std.StringArrayHashMap(TypeErasedSystem),
    untagged_systems: std.ArrayList(TypeErasedSystem),

    pub fn init(allocator: Allocator) SystemManager {
        return SystemManager{
            .allocator = allocator,
            .tagged_systems = std.StringArrayHashMap(TypeErasedSystem).init(allocator),
            .untagged_systems = std.ArrayList(TypeErasedSystem).init(allocator),
        };
    }

    pub fn deinit(self: *SystemManager) void {
        // clean up all untagged systems
        for (self.untagged_systems.items) |system| {
            system.deinit();
        }
        self.untagged_systems.deinit();

        // clean up all tagged systems
        for (self.tagged_systems.values()) |system| {
            system.deinit();
        }
        self.tagged_systems.deinit();
    }

    /// Register a system with the manager.
    pub fn registerSystem(self: *SystemManager, comptime SystemType: type) !void {
        const erased_system = try TypeErasedSystem.init(self.allocator, SystemType);
        errdefer erased_system.deinit();
        try self.untagged_systems.append(erased_system);
    }

    pub fn registerTaggedSystem(self: *SystemManager, comptime SystemType: type, tag: []const u8) !void {
        const type_erased_system = try TypeErasedSystem.init(self.allocator, SystemType);
        errdefer type_erased_system.deinit();
        try self.tagged_systems.put(tag, type_erased_system);
    }

    /// Update all systems with the given tag.
    pub fn updateUntagged(self: *SystemManager, registry: *Registry) void {
        // update all untagged systems
        for (self.untagged_systems.items) |system| {
            system.update(registry) catch |err| {
                std.debug.print("Failed to update {s}: {}\n", .{ @typeName(@TypeOf(system)), err });
            };
        }
    }

    /// Update all systems with the given tag.
    pub fn updateTagged(self: *SystemManager, registry: *Registry, target_tag: []const u8) void {
        // update all tagged systems
        var tagged_systems_iter = self.tagged_systems.iterator();
        blk: while (tagged_systems_iter.next()) |entry| {
            const this_tag = entry.key_ptr.*;
            if (!std.mem.eql(u8, target_tag, this_tag)) continue :blk;

            const system = entry.value_ptr;
            system.update(registry) catch |err| {
                std.debug.print(
                    "Failed to update {s}, tag '{s}': {}\n",
                    .{ @typeName(@TypeOf(system)), target_tag, err },
                );
            };
        }
    }

    /// Update all systems.
    pub fn updateAll(self: *SystemManager, registry: *Registry) void {
        // update all untagged systems
        for (self.untagged_systems.items) |system| {
            system.update(registry) catch |err| {
                std.debug.print("Failed to update {s}: {}\n", .{ @typeName(@TypeOf(system)), err });
            };
        }

        // update all tagged systems
        var tagged_systems_iter = self.tagged_systems.iterator();
        while (tagged_systems_iter.next()) |entry| {
            const tag = entry.key_ptr;
            const system = entry.value_ptr;
            system.update(registry) catch |err| {
                std.debug.print(
                    "Failed to update {s}, tag '{s}': {}\n",
                    .{ @typeName(@TypeOf(system)), tag, err },
                );
            };
        }
    }

    pub fn tags(self: *SystemManager) [][]const u8 {
        return self.tagged_systems.keys();
    }
};
