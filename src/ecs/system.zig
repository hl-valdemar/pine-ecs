const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Registry = @import("registry.zig").Registry;

/// Metadata about a system's capabilities
const SystemMetadata = struct {
    has_init: bool,
    has_deinit: bool,
    has_process: bool,
    name: []const u8,
};

fn SystemTrait(comptime System: type) type {
    return struct {
        // define expected signatures
        const InitFn = fn (Allocator) anyerror!System;
        const DeinitFn = fn (*System) void;
        const ProcessFn = fn (*System, *Registry) anyerror!void;

        const metadata = SystemMetadata{
            .has_init = @hasDecl(System, "init"),
            .has_deinit = @hasDecl(System, "deinit"),
            .has_process = @hasDecl(System, "process"),
            .name = @typeName(System),
        };

        // NOTE: inline to satisfy comptime execution requirements
        pub inline fn validate() SystemMetadata {
            // validate signatures
            if (metadata.has_init and @TypeOf(System.init) != InitFn) {
                @compileError(std.fmt.comptimePrint(
                    \\System '{s}' has invalid init signature.
                    \\Expected: {s}
                    \\Found:    {s}
                    \\
                    \\Make sure the function is public and matches the expected signature.
                , .{ metadata.name, @typeName(InitFn), @typeName(@TypeOf(System.init)) }));
            }

            if (metadata.has_deinit and @TypeOf(System.deinit) != DeinitFn) {
                @compileError(std.fmt.comptimePrint(
                    \\System '{s}' has invalid deinit signature.
                    \\Expected: {s}
                    \\Found:    {s}
                    \\
                    \\Make sure the function is public and matches the expected signature.
                , .{ metadata.name, @typeName(DeinitFn), @typeName(@TypeOf(System.deinit)) }));
            }

            if (metadata.has_process) {
                const process_type = @TypeOf(System.process);
                if (process_type != ProcessFn) {
                    @compileError(std.fmt.comptimePrint(
                        \\System '{s}' has invalid process signature.
                        \\Expected: {s}
                        \\Found:    {s}
                        \\
                        \\Make sure the function is public and matches the expected signature.
                    , .{ metadata.name, @typeName(ProcessFn), @typeName(process_type) }));
                }
            } else @compileError(std.fmt.comptimePrint(
                \\System '{s}' is missing the required process function.
                \\
                \\Every system must define:
                \\  pub fn process(self: *{s}, registry: *Registry) anyerror!void
            , .{ metadata.name, metadata.name }));

            return metadata;
        }
    };
}

pub const TypeErasedSystem = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const SystemVTable,
    metadata: SystemMetadata,

    pub fn init(allocator: Allocator, comptime System: type) !TypeErasedSystem {
        const metadata = SystemTrait(System).validate();

        const system_ptr = try allocator.create(System);
        errdefer allocator.destroy(system_ptr);

        system_ptr.* = if (metadata.has_init)
            try System.init(allocator)
        else
            System{};

        return TypeErasedSystem{
            .allocator = allocator,
            .ptr = system_ptr,
            .vtable = &comptime makeSystemVTable(System, metadata),
            .metadata = metadata,
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

pub fn makeSystemVTable(comptime System: type, metadata: SystemMetadata) SystemVTable {
    return SystemVTable{
        .deinit = (struct {
            fn func(allocator: Allocator, type_erased_system_ptr: *anyopaque) void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, System);

                if (metadata.has_deinit)
                    system.deinit();

                allocator.destroy(system);
            }
        }).func,
        .process = (struct {
            fn func(type_erased_system_ptr: *anyopaque, registry: *Registry) anyerror!void {
                const system = TypeErasedSystem.cast(type_erased_system_ptr, System);
                if (metadata.has_process) {
                    try system.process(registry);
                } else unreachable;
            }
        }).func,
    };
}
