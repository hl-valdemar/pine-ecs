const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Registry = @import("registry.zig").Registry;

/// Defines critical system functions.
fn SystemTrait(comptime System: type) type {
    return struct {
        pub const InitFn = fn (Allocator) anyerror!System;
        pub const DeinitFn = fn (*System) void;
        pub const ProcessFn = fn (*System, *Registry) anyerror!void;
    };
}

pub const TypeErasedSystem = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const SystemVTable,

    pub fn init(allocator: Allocator, comptime System: type) !TypeErasedSystem {
        const system_ptr = try allocator.create(System);

        // if system defines an init, use it
        system_ptr.* = if (@hasDecl(System, "init")) blk: {
            const system_init_type = @TypeOf(System.init);
            if (system_init_type != SystemTrait(System).InitFn) {
                @compileError(std.fmt.comptimePrint(
                    \\System type '{s}' has invalid init signature.
                    \\Expected: fn(Allocator) anyerror!{s}
                    \\Found:    {s}
                    \\Did you make the function public?
                , .{ @typeName(System), @typeName(System), @typeName(system_init_type) }));
            }
            break :blk try System.init(allocator);
        } else System{};

        return TypeErasedSystem{
            .allocator = allocator,
            .ptr = system_ptr,
            .vtable = &comptime makeSystemVTable(System),
        };
    }

    pub fn deinit(self: TypeErasedSystem) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn process(self: TypeErasedSystem, registry: *Registry) anyerror!void {
        try self.vtable.process(self.ptr, registry);
    }

    pub fn cast(type_erased_system_ptr: *anyopaque, comptime System: type) *System {
        return @alignCast(@ptrCast(type_erased_system_ptr));
    }
};

/// Virtual function table for type-erased systems.
pub const SystemVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    process: *const fn (*anyopaque, *Registry) anyerror!void,
};

pub fn makeSystemVTable(comptime System: type) SystemVTable {
    return SystemVTable{
        .deinit = (struct {
            fn func(allocator: Allocator, type_erased_system_ptr: *anyopaque) void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, System);

                // if system defines a deinit, use it
                if (@hasDecl(System, "deinit")) {
                    // assert that the deinit function follows convention
                    const system_deinit_type = @TypeOf(System.deinit);
                    if (system_deinit_type != SystemTrait(System).DeinitFn) {
                        @compileError(std.fmt.comptimePrint(
                            \\System type '{s}' has invalid deinit signature.
                            \\Expected: fn(*{s}) void
                            \\Found:    {s}
                        , .{ @typeName(System), @typeName(System), @typeName(system_deinit_type) }));
                    }

                    system.deinit();
                }

                allocator.destroy(system);
            }
        }).func,
        .process = (struct {
            fn func(type_erased_system_ptr: *anyopaque, registry: *Registry) anyerror!void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, System);

                // a system must define a process method, lest it be redundant
                if (@hasDecl(System, "process")) {
                    // assert that the process function follows convention
                    const system_process_type = @TypeOf(System.process);
                    if (system_process_type != SystemTrait(System).ProcessFn) {
                        @compileError(std.fmt.comptimePrint(
                            \\System type '{s}' has invalid process signature.
                            \\Expected: fn (*{s}, *Registry) anyerror!void
                            \\Found:    {s}
                            \\Did you make the function public?
                        , .{ @typeName(System), @typeName(System), @typeName(system_process_type) }));
                    }
                    try system.process(registry);
                } else @compileError(std.fmt.comptimePrint(
                    \\System type '{s}' has invalid process signature.
                    \\Expected: fn (*{s}, *Registry) anyerror!void
                    \\Found:    NONE
                    \\Did you make the function public?
                , .{ @typeName(System), @typeName(System) }));
            }
        }).func,
    };
}
