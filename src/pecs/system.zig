const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");

const Registry = @import("registry.zig").Registry;

/// Trait defining system behavior.
///
/// NB: all systems must implement this.
pub fn SystemTrait(comptime SystemType: type) type {
    return struct {
        pub fn validate() void {
            // check if required functions exist with correct signatures
            if (!@hasDecl(SystemType, "init") or
                @TypeOf(SystemType.init) == fn (Allocator) anyerror!SystemType)
            {
                @compileError("System type must have function `init(Allocator) anyerror!SystemType`");
            }

            if (!@hasDecl(SystemType, "deinit") or
                @TypeOf(SystemType.deinit) != fn (*SystemType) void)
            {
                @compileError("System type must have function `deinit(*Self) void`");
            }

            if (!@hasDecl(SystemType, "process") or
                @TypeOf(SystemType.process) != fn (*SystemType, *Registry) anyerror!void)
            {
                @compileError("System type must have function `process(*Self, *Registry) anyerror!void`");
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

    pub fn process(self: TypeErasedSystem, registry: *Registry) anyerror!void {
        try self.vtable.process(self.ptr, registry);
    }

    pub fn cast(type_erased_system_ptr: *anyopaque, comptime SystemType: type) *SystemType {
        return @alignCast(@ptrCast(type_erased_system_ptr));
    }
};

/// Virtual function table for type-erased systems.
pub const SystemVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    process: *const fn (*anyopaque, *Registry) anyerror!void,
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
        .process = (struct {
            fn func(type_erased_system_ptr: *anyopaque, registry: *Registry) anyerror!void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, SystemType);
                try system.process(registry);
            }
        }).func,
    };
}

pub const SystemManager = struct {
    allocator: Allocator,
    tagged_systems: std.StringArrayHashMap(std.ArrayList(TypeErasedSystem)),
    untagged_systems: std.ArrayList(TypeErasedSystem),

    pub fn init(allocator: Allocator) SystemManager {
        return SystemManager{
            .allocator = allocator,
            .tagged_systems = std.StringArrayHashMap(std.ArrayList(TypeErasedSystem)).init(allocator),
            .untagged_systems = std.ArrayList(TypeErasedSystem).init(allocator),
        };
    }

    pub fn deinit(self: *SystemManager) void {
        // clean up all untagged systems
        for (self.untagged_systems.items) |system| system.deinit();
        self.untagged_systems.deinit();

        // clean up all tagged systems
        for (self.tagged_systems.values()) |systems| {
            for (systems.items) |system| system.deinit();
            systems.deinit();
        }
        self.tagged_systems.deinit();
    }

    /// Register a system with the manager.
    pub fn registerSystem(self: *SystemManager, comptime SystemType: type) !void {
        const erased_system = try TypeErasedSystem.init(self.allocator, SystemType);
        errdefer erased_system.deinit();
        try self.untagged_systems.append(erased_system);
    }

    /// Register a system with the manager with the given tag.
    ///
    /// Useful for differentiating systems that should run under certain circumstances.
    pub fn registerTaggedSystem(self: *SystemManager, comptime SystemType: type, tag: []const u8) !void {
        const type_erased_system = try TypeErasedSystem.init(self.allocator, SystemType);
        errdefer type_erased_system.deinit();

        const entry = try self.tagged_systems.getOrPut(tag);
        if (!entry.found_existing) {
            // new tag => new array list
            entry.value_ptr.* = std.ArrayList(TypeErasedSystem).init(self.allocator);
        }

        const systems = entry.value_ptr;
        try systems.append(type_erased_system);
    }

    /// Process all systems with the given tag.
    pub fn processUntagged(self: *SystemManager, registry: *Registry) void {
        // process all untagged systems
        for (self.untagged_systems.items) |system| {
            system.process(registry) catch |err| {
                log.warn("failed to process system: {}\n", .{err});
            };
        }
    }

    /// Process all systems with the given tag.
    pub fn processTagged(self: *SystemManager, registry: *Registry, tag: []const u8) !void {
        const systems = self.tagged_systems.get(tag);

        if (systems == null)
            return error.NoSuchTag;

        // process all systems with the given tag
        for (systems.?.items) |system| {
            system.process(registry) catch |err| {
                log.warn("failed to process system tagged '{s}': {}\n", .{ tag, err });
            };
        }
    }

    /// Process all systems.
    pub fn processAll(self: *SystemManager, registry: *Registry) void {
        // process all untagged systems
        self.processUntagged(registry);

        // process all tagged systems
        const system_tags = self.tagged_systems.keys();
        for (system_tags) |tag| self.processTagged(registry, tag);
    }

    /// Return a list of registered tags.
    pub fn tags(self: *SystemManager) [][]const u8 {
        return self.tagged_systems.keys();
    }
};
