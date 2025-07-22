const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Registry = @import("registry.zig").Registry;

pub fn SystemTrait(comptime SystemType: type) type {
    const InitFunc = fn (Allocator) anyerror!SystemType;
    const DeinitFunc = fn (*SystemType) void;
    const ProcessFunc = fn (*SystemType, *Registry) anyerror!void;

    return struct {
        pub fn validate() void {
            // check if required functions exist with correct signatures
            if (!@hasDecl(SystemType, "init") or
                @TypeOf(SystemType.init) != InitFunc)
            {
                @compileLog("INVALID SYSTEM REGISTERED", SystemType);
                @compileError(
                    \\System type must have `pub fn init(Allocator) anyerror!Self`.
                    \\Did you make the function public?"
                );
            }

            if (!@hasDecl(SystemType, "deinit") or
                @TypeOf(SystemType.deinit) != DeinitFunc)
            {
                @compileLog("INVALID SYSTEM REGISTERED", SystemType);
                @compileError(
                    \\System type must have `pub fn deinit(*Self) void`.
                    \\Did you make the function public?
                );
            }

            if (!@hasDecl(SystemType, "process") or
                @TypeOf(SystemType.process) != ProcessFunc)
            {
                @compileLog("INVALID SYSTEM REGISTERED", SystemType);
                @compileError(
                    \\System type must have `pub fn process(*Self, *Registry) anyerror!void`.
                    \\Did you make the function public?
                );
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
