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
    systems: std.ArrayList(TypeErasedSystem),

    pub fn init(allocator: Allocator) SystemManager {
        return SystemManager{
            .allocator = allocator,
            .systems = std.ArrayList(TypeErasedSystem).init(allocator),
        };
    }

    pub fn deinit(self: *const SystemManager) void {
        for (self.systems.items) |system| {
            system.deinit();
        }
        self.systems.deinit();
    }

    /// Register a system with the manager.
    pub fn registerSystem(self: *SystemManager, comptime SystemType: type) !void {
        const erased_system = try TypeErasedSystem.init(self.allocator, SystemType);
        errdefer erased_system.deinit();
        try self.systems.append(erased_system);
    }

    /// Update all systems.
    pub fn updateAll(self: *SystemManager, registry: *Registry) void {
        for (self.systems.items) |system| {
            system.update(registry) catch |err| {
                std.debug.print("Failed to update {s}: {}\n", .{ @typeName(@TypeOf(system)), err });
            };
        }
    }
};
