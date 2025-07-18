const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ResourceVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    clear: *const fn (*anyopaque) void,
    remove: *const fn (*anyopaque, usize) void,
    createEmpty: *const fn (Allocator) Allocator.Error!TypeErasedResourceStorage,
};

pub fn makeResourceVTable(comptime Resource: type) ResourceVTable {
    return ResourceVTable{
        .deinit = (struct {
            fn func(allocator: Allocator, type_erased_resource_ptr: *anyopaque) void {
                const storage = TypeErasedResourceStorage.cast(type_erased_resource_ptr, Resource);
                storage.deinit();
                allocator.destroy(storage);
            }
        }).func,
        .clear = (struct {
            fn func(type_erased_resource_ptr: *anyopaque) void {
                const storage = TypeErasedResourceStorage.cast(type_erased_resource_ptr, Resource);
                storage.clear();
            }
        }).func,
        .remove = (struct {
            fn func(type_erased_resource_ptr: *anyopaque, idx: usize) void {
                const storage = TypeErasedResourceStorage.cast(type_erased_resource_ptr, Resource);
                _ = storage.remove(idx);
            }
        }).func,
        .createEmpty = (struct {
            fn func(allocator: Allocator) Allocator.Error!TypeErasedResourceStorage {
                // create a new empty storage of component type
                const resource_ptr = try allocator.create(ResourceStorage(Resource));
                resource_ptr.* = ResourceStorage(Resource).init(allocator);

                return TypeErasedResourceStorage{
                    .allocator = allocator,
                    .ptr = resource_ptr,
                    .vtable = &comptime makeResourceVTable(Resource),
                };
            }
        }).func,
    };
}

pub const TypeErasedResourceStorage = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const ResourceVTable,

    pub fn init(allocator: Allocator, comptime Resource: type) !TypeErasedResourceStorage {
        const resource_ptr = try allocator.create(ResourceStorage(Resource));
        resource_ptr.* = ResourceStorage(Resource).init(allocator);

        return TypeErasedResourceStorage{
            .allocator = allocator,
            .ptr = resource_ptr,
            .vtable = &comptime makeResourceVTable(Resource),
        };
    }

    pub fn deinit(self: *const TypeErasedResourceStorage) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn clear(self: *const TypeErasedResourceStorage) void {
        self.vtable.clear(self.ptr);
    }

    pub fn remove(self: *const TypeErasedResourceStorage, idx: usize) void {
        self.vtable.remove(self.ptr, idx);
    }

    /// Cast a type erased component storage to a ResourceStorage(Component) of the given component type.
    ///
    /// NOTE: if cast to an inappropriate type, use may lead to corruption of memory.
    pub fn cast(type_erased_resource_ptr: *anyopaque, comptime Resource: type) *ResourceStorage(Resource) {
        return @alignCast(@ptrCast(type_erased_resource_ptr));
    }
};

pub fn ResourceStorage(comptime Resource: type) type {
    return struct {
        const Self = @This();

        resources: std.ArrayList(Resource),

        pub fn init(allocator: Allocator) Self {
            return Self{
                .resources = std.ArrayList(Resource).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // first deinit resources if necessary
            if (@hasDecl(Resource, "deinit") and
                @typeInfo(@TypeOf(@field(Resource, "deinit"))) == .@"fn")
            {
                for (self.resources.items) |*resource| {
                    resource.deinit();
                }
            }
            // then deinit list
            self.resources.deinit();
        }

        pub fn clear(self: *Self) void {
            self.resources.clearRetainingCapacity();
        }

        pub fn remove(self: *Self, idx: usize) Resource {
            return self.resources.orderedRemove(idx);
        }

        pub fn swapRemove(self: *Self, idx: usize) Resource {
            return self.resources.swapRemove(idx);
        }
    };
}
