const std = @import("std");
const Allocator = std.mem.Allocator;

const EntityID = @import("registry.zig").EntityID;

pub const ComponentVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    swapRemove: *const fn (*anyopaque, usize) void,
    copy: *const fn (*anyopaque, *anyopaque, usize, usize) Allocator.Error!void,
    createEmpty: *const fn (Allocator) Allocator.Error!TypeErasedComponentStorage,
    getComponentPtr: *const fn (*anyopaque, usize) *anyopaque,
};

pub fn makeComponentVTable(comptime Component: type) ComponentVTable {
    return ComponentVTable{
        .deinit = (struct {
            fn func(alloc: Allocator, type_erased_components_ptr: *anyopaque) void {
                const storage = TypeErasedComponentStorage.cast(type_erased_components_ptr, Component);
                storage.deinit();
                alloc.destroy(storage);
            }
        }).func,
        .swapRemove = (struct {
            fn func(type_erased_components_ptr: *anyopaque, entity_idx: usize) void {
                var storage = TypeErasedComponentStorage.cast(type_erased_components_ptr, Component);
                storage.swapRemove(entity_idx);
            }
        }).func,
        .copy = (struct {
            fn func(
                src_type_erased_components_ptr: *anyopaque,
                dst_type_erased_components_ptr: *anyopaque,
                src_entity_idx: usize,
                dst_entity_idx: usize,
            ) Allocator.Error!void {
                var src_storage = TypeErasedComponentStorage.cast(src_type_erased_components_ptr, Component);
                const dst_storage = TypeErasedComponentStorage.cast(dst_type_erased_components_ptr, Component);
                try src_storage.copy(src_entity_idx, dst_storage, dst_entity_idx);
            }
        }).func,
        .createEmpty = (struct {
            fn func(allocator: Allocator) Allocator.Error!TypeErasedComponentStorage {
                // create a new empty storage of component type
                const components_ptr = try allocator.create(ComponentStorage(Component));
                components_ptr.* = ComponentStorage(Component).init(allocator);

                return TypeErasedComponentStorage{
                    .allocator = allocator,
                    .ptr = components_ptr,
                    .vtable = &comptime makeComponentVTable(Component),
                };
            }
        }).func,
        .getComponentPtr = (struct {
            fn func(type_erased_components_ptr: *anyopaque, idx: usize) *anyopaque {
                const components_ptr = TypeErasedComponentStorage.cast(type_erased_components_ptr, Component);
                return &components_ptr.components.items[idx];
            }
        }).func,
    };
}

pub const TypeErasedComponentStorage = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const ComponentVTable,

    pub fn init(allocator: Allocator, comptime Component: type) !TypeErasedComponentStorage {
        const components_ptr = try allocator.create(ComponentStorage(Component));
        components_ptr.* = ComponentStorage(Component).init(allocator);

        return TypeErasedComponentStorage{
            .allocator = allocator,
            .ptr = components_ptr,
            .vtable = &comptime makeComponentVTable(Component),
        };
    }

    pub fn deinit(self: *const TypeErasedComponentStorage) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn swapRemove(self: *const TypeErasedComponentStorage, entity_idx: usize) void {
        self.vtable.swapRemove(self.ptr, entity_idx);
    }

    pub fn copy(
        self: *const TypeErasedComponentStorage,
        src_entity_idx: usize,
        dst: TypeErasedComponentStorage,
        dst_entity_idx: usize,
    ) !void {
        return self.vtable.copy(self.ptr, dst.ptr, src_entity_idx, dst_entity_idx);
    }

    pub fn cloneType(self: *const TypeErasedComponentStorage, allocator: Allocator) !TypeErasedComponentStorage {
        return self.vtable.createEmpty(allocator);
    }

    pub fn getComponentPtr(self: *const TypeErasedComponentStorage, idx: usize) *anyopaque {
        return self.vtable.getComponentPtr(self.ptr, idx);
    }

    /// Cast a type erased component storage to a ComponentStorage(Component) of the given component type.
    ///
    /// NOTE: if cast to an inappropriate type, use may lead to corruption of memory.
    pub fn cast(type_erased_components_ptr: *anyopaque, comptime Component: type) *ComponentStorage(Component) {
        return @alignCast(@ptrCast(type_erased_components_ptr));
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
            // deinit all remaining components if they have a deinit method
            if (@hasDecl(Component, "deinit")) {
                for (self.components.items) |*component| {
                    component.deinit();
                }
            }
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
            // call deinit on the component being removed if it has one
            if (@hasDecl(Component, "deinit")) {
                self.components.items[entity_idx].deinit();
            }
            _ = self.components.swapRemove(entity_idx);
        }
    };
}

pub const ComponentUpdate = struct {
    entity_id: EntityID,
    component_type_name: []const u8,
    component_ptr: *anyopaque,
    new_value_bytes: []u8, // store the new value as bytes
    copy_fn: *const fn (*anyopaque, []const u8) void,
};

pub const UpdateBuffer = struct {
    allocator: Allocator,
    updates: std.ArrayList(ComponentUpdate),

    pub fn init(allocator: Allocator) UpdateBuffer {
        return .{
            .allocator = allocator,
            .updates = std.ArrayList(ComponentUpdate).init(allocator),
        };
    }

    pub fn deinit(self: *UpdateBuffer) void {
        // free all stored update data
        for (self.updates.items) |update| {
            self.allocator.free(update.new_value_bytes);
        }
        self.updates.deinit();
    }

    pub fn clear(self: *UpdateBuffer) void {
        for (self.updates.items) |update| {
            self.allocator.free(update.new_value_bytes);
        }
        self.updates.clearRetainingCapacity();
    }
};
