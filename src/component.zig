const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ComponentVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    swapRemove: *const fn (*anyopaque, usize) void,
    copy: *const fn (*anyopaque, *anyopaque, usize, usize) Allocator.Error!void,
    createEmpty: *const fn (Allocator) error{OutOfMemory}!TypeErasedComponentStorage,
};

pub fn makeVTable(comptime Component: type) ComponentVTable {
    return ComponentVTable{
        .deinit = (struct {
            fn func(alloc: Allocator, type_erased_ptr: *anyopaque) void {
                const storage = TypeErasedComponentStorage.cast(type_erased_ptr, Component);
                storage.deinit();
                alloc.destroy(storage);
            }
        }).func,
        .swapRemove = (struct {
            fn func(type_erased_ptr: *anyopaque, entity_idx: usize) void {
                var storage = TypeErasedComponentStorage.cast(type_erased_ptr, Component);
                storage.swapRemove(entity_idx);
            }
        }).func,
        .copy = (struct {
            fn func(
                src_erased_ptr: *anyopaque,
                dst_erased_ptr: *anyopaque,
                src_entity_idx: usize,
                dst_entity_idx: usize,
            ) Allocator.Error!void {
                var src_storage = TypeErasedComponentStorage.cast(src_erased_ptr, Component);
                const dst_storage = TypeErasedComponentStorage.cast(dst_erased_ptr, Component);
                try src_storage.copy(src_entity_idx, dst_storage, dst_entity_idx);
            }
        }).func,
        .createEmpty = (struct {
            fn func(allocator: Allocator) error{OutOfMemory}!TypeErasedComponentStorage {
                // Creates a new empty storage of Component type
                const component_ptr = try allocator.create(ComponentStorage(Component));
                component_ptr.* = ComponentStorage(Component).init(allocator);

                return TypeErasedComponentStorage{
                    .allocator = allocator,
                    .ptr = component_ptr,
                    .vtable = &comptime makeVTable(Component),
                };
            }
        }).func,
    };
}

pub const TypeErasedComponentStorage = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const ComponentVTable,

    pub fn init(allocator: Allocator, comptime Component: type) !TypeErasedComponentStorage {
        const component_ptr = try allocator.create(ComponentStorage(Component));
        component_ptr.* = ComponentStorage(Component).init(allocator);

        return TypeErasedComponentStorage{
            .allocator = allocator,
            .ptr = component_ptr,
            .vtable = &comptime makeVTable(Component),
        };
    }

    pub fn deinit(self: TypeErasedComponentStorage) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn swapRemove(self: TypeErasedComponentStorage, entity_idx: usize) void {
        self.vtable.swapRemove(self.ptr, entity_idx);
    }

    pub fn copy(self: TypeErasedComponentStorage, src_entity_idx: usize, dst: TypeErasedComponentStorage, dst_entity_idx: usize) !void {
        return self.vtable.copy(self.ptr, dst.ptr, src_entity_idx, dst_entity_idx);
    }

    pub fn cloneType(self: TypeErasedComponentStorage, allocator: Allocator) !TypeErasedComponentStorage {
        return self.vtable.createEmpty(allocator);
    }

    /// Cast a type erased component storage to a ComponentStorage(Component) of the given component type.
    ///
    /// NOTE: if cast to an inappropriate type, use may lead to corruption of memory.
    pub fn cast(erased_ptr: *anyopaque, comptime Component: type) *ComponentStorage(Component) {
        return @alignCast(@ptrCast(erased_ptr));
    }
};

pub fn ComponentStorage(comptime Component: type) type {
    return struct {
        const Self = @This();

        components: std.ArrayList(Component),

        pub fn init(allocator: Allocator) Self {
            return Self{
                .components = std.ArrayList(Component).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit();
        }

        /// Replace the component for the given entity index.
        pub fn set(self: *Self, entity_idx: usize, component: Component) !void {
            if (entity_idx >= self.components.items.len)
                try self.components.appendNTimes(undefined, entity_idx - self.components.items.len + 1);

            self.components.items[entity_idx] = component;
        }

        /// Get the component for the given entity index.
        pub fn get(self: *Self, entity_idx: usize) Component {
            std.debug.assert(entity_idx < self.components.items.len);
            return self.components.items[entity_idx];
        }

        /// Copy the component at the given source entity index to the destination.
        pub fn copy(src: *Self, src_entity_idx: usize, dst: *Self, dst_entity_idx: usize) !void {
            try dst.set(dst_entity_idx, src.get(src_entity_idx));
        }

        pub fn swapRemove(self: *Self, entity_idx: usize) void {
            _ = self.components.swapRemove(entity_idx);
        }
    };
}
