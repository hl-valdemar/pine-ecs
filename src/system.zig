const std = @import("std");

const Allocator = std.mem.Allocator;

const pecs = @import("root.zig");
const Registry = pecs.Registry;

// /// System interface that defines the core functionality all systems must implement.
// pub fn SystemInterface(comptime Self: type) type {
//     return struct {
//         pub const init = Self.init;
//         pub const deinit = Self.deinit;
//         pub const update = Self.update;
//     };
// }

pub const TypeErasedSystem = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const SystemVTable,

    pub fn init(allocator: Allocator, comptime SystemType: type) !TypeErasedSystem {
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

    pub fn update(self: TypeErasedSystem, registry: *Registry) void {
        self.vtable.update(self.ptr, registry);
    }
};

/// Virtual function table for type-erased systems.
pub const SystemVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    update: *const fn (*anyopaque, *Registry) void,
};

pub fn makeSystemVTable(comptime SystemType: type) SystemVTable {
    return SystemVTable{ .deinit = (struct {
        fn func(allocator: Allocator, type_erased_system_ptr: *anyopaque) void {
            const system: *SystemType = @alignCast(@ptrCast(type_erased_system_ptr));
            system.deinit();
            allocator.destroy(system);
        }
    }).func, .update = (struct {
        fn func(type_erased_system_ptr: *anyopaque, registry: *Registry) void {
            const system: *SystemType = @alignCast(@ptrCast(type_erased_system_ptr));
            system.update(registry);
        }
    }).func };
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
            system.update(registry);
        }
    }
};
