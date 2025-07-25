const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("../log.zig");

pub const TypeErasedSingleton = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const SingletonVTable,

    pub fn init(allocator: Allocator, comptime R: type) !TypeErasedSingleton {
        const resource_ptr = try allocator.create(Singleton(R));
        resource_ptr.* = Singleton(R).init();

        return TypeErasedSingleton{
            .allocator = allocator,
            .ptr = resource_ptr,
            .vtable = &comptime makeSingletonVTable(R),
        };
    }

    pub fn deinit(self: *const TypeErasedSingleton) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn destroyResource(self: *const TypeErasedSingleton) void {
        self.vtable.destroyResource(self.ptr);
    }

    /// Cast a type erased singleton to a Resource(R) of type R.
    ///
    /// Note: casting to an inappropriate type *will* lead to undefined behavior.
    pub fn cast(type_erased_ptr: *anyopaque, comptime R: type) *Singleton(R) {
        return @alignCast(@ptrCast(type_erased_ptr));
    }
};

const SingletonVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    destroyResource: *const fn (*anyopaque) void,
};

pub fn Singleton(comptime R: type) type {
    return struct {
        const Self = @This();

        resource: ?R,

        pub fn init() Self {
            return Self{ .resource = null };
        }

        pub fn deinit(self: *Self) void {
            // deinit if appropriate
            if (self.resource) |*res| {
                if (resourceHasDeinit()) res.deinit();
            }
        }

        pub fn destroyResource(self: *Self) void {
            // deinit if appropriate
            if (self.resource) |*res| {
                if (resourceHasDeinit()) res.deinit();
                self.resource = null;
            }
        }

        // note: inline for comptime reasons
        inline fn resourceHasDeinit() bool {
            return @hasDecl(R, "deinit");
        }
    };
}

fn makeSingletonVTable(comptime R: type) SingletonVTable {
    return SingletonVTable{ .deinit = (struct {
        fn func(allocator: Allocator, type_erased_ptr: *anyopaque) void {
            const typed_ptr = TypeErasedSingleton.cast(type_erased_ptr, R);
            typed_ptr.deinit();
            allocator.destroy(typed_ptr);
        }
    }.func), .destroyResource = (struct {
        fn func(type_erased_ptr: *anyopaque) void {
            const typed_ptr = TypeErasedSingleton.cast(type_erased_ptr, R);
            typed_ptr.destroyResource();
        }
    }.func) };
}
