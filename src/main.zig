const std = @import("std");

const Allocator = std.mem.Allocator;

const RegistryError = error{
    NoSuchEntity,
    NoSuchArchetype,
    InternalInconsistency,
};

const EntityID = u32;

const EntityPointer = struct {
    /// An ID for the archetype in which the entity data resides.
    archetype_hash: ArchetypeHashType,

    /// An index into the archetype table to the entity data.
    entity_idx: usize,
};

pub const Registry = struct {
    allocator: Allocator,

    /// Maps an entity ID to a pointer to its archetype.
    entities: std.AutoHashMap(EntityID, EntityPointer),

    /// Maps an archetype hash to its corresponding archetype.
    archetypes: std.AutoHashMap(ArchetypeHashType, Archetype),

    pub fn init(allocator: Allocator) !Registry {
        var registry = Registry{
            .allocator = allocator,
            .entities = std.AutoHashMap(EntityID, EntityPointer).init(allocator),
            .archetypes = std.AutoHashMap(ArchetypeHashType, Archetype).init(allocator),
        };

        // the empty archetype should always be present
        const empty_archetype = Archetype.init(allocator);
        try registry.archetypes.put(empty_archetype.hash, empty_archetype);

        return registry;
    }

    pub fn deinit(self: *Registry) void {
        self.entities.deinit();

        var arch_iter = self.archetypes.valueIterator();
        while (arch_iter.next()) |archetype| {
            archetype.deinit();
        }
        self.archetypes.deinit();
    }

    pub fn createEntity(self: *Registry) !EntityID {
        const new_id = self.entities.count();
        const empty_archetype = self.archetypes.getPtr(Archetype.EMPTY_ARCHETYPE_HASH).?;

        // 1) add new entity to archetype's list
        const entity_idx = empty_archetype.entities.items.len;
        try empty_archetype.entities.append(new_id);

        // 2) add entity pointer to the registry
        try self.entities.put(new_id, EntityPointer{
            .archetype_hash = empty_archetype.hash,
            .entity_idx = entity_idx,
        });

        return new_id;
    }

    /// Returns true if the entity was succesfully removed, false otherwise.
    pub fn destroyEntity(self: *Registry, entity: EntityID) RegistryError!void {
        const entity_ptr = self.entities.get(entity) orelse return error.NoSuchEntity;
        var archetype = self.archetypes.getPtr(entity_ptr.archetype_hash) orelse return error.NoSuchArchetype;

        const original_entity_idx = entity_ptr.entity_idx; // store old index before remove invalidates entity_ptr

        // remove entity data from archetype
        const removed_result = archetype.remove(original_entity_idx);
        std.debug.assert(removed_result.removed_id == entity);

        // handle the swapped entity
        if (removed_result.swapped_id) |swapped_entity_id| {
            if (self.entities.getPtr(swapped_entity_id)) |swapped_entity_ptr_ptr| {
                // update the index for the swapped entity
                swapped_entity_ptr_ptr.*.entity_idx = original_entity_idx;
            } else {
                // should not happen in consistent state
                std.debug.print("Error: Swapped entity ID {d} not found in registry during destroyEntity!", .{swapped_entity_id});
                return error.InternalInconsistency;
            }
        }

        // remove entity id from registry's entities list
        _ = self.entities.remove(entity);
    }

    pub fn addComponent(self: *Registry, entity: EntityID, component: anytype) !void {
        const entity_ptr = self.entities.get(entity).?;
        var prev_archetype = self.archetypes.getPtr(entity_ptr.archetype_hash).?;

        const resulting_hash = prev_archetype.hash ^ std.hash_map.hashString(@typeName(@TypeOf(component)));

        const resulting_archetype_entry = try self.archetypes.getOrPut(resulting_hash);
        const target_archetype = resulting_archetype_entry.value_ptr;

        // setup *new* archetype if it doesn't exist
        if (!resulting_archetype_entry.found_existing) {
            // initialize the archetype itself
            target_archetype.* = Archetype.init(self.allocator);

            // setup *empty* storage for all components from the previous archetype
            var prev_arch_components_iter = prev_archetype.components.iterator();
            while (prev_arch_components_iter.next()) |entry| {
                const prev_component_storage = entry.value_ptr; // type erased from old archetype
                var new_empty_storage: TypeErasedComponentStorage = undefined;

                // create an empty storage container of the correct type
                try prev_component_storage.cloneType.?(self.allocator, &new_empty_storage);
                new_empty_storage.cloneType = prev_component_storage.cloneType;

                try target_archetype.components.put(entry.key_ptr.*, new_empty_storage);
            }

            // setup *empty* storage for the new component type
            const new_erased_storage = try TypeErasedComponentStorage.init(self.allocator, @TypeOf(component));
            try target_archetype.components.put(@typeName(@TypeOf(component)), new_erased_storage);

            // crucially, set the hash for the new archetype
            target_archetype.hash = resulting_hash;
        } else {
            // archetype already exists, assert its hash is correct
            std.debug.assert(target_archetype.hash == resulting_hash);
        }

        // add the entity ID to the target entity->index map
        const target_entity_idx = target_archetype.entities.items.len;
        try target_archetype.entities.append(entity);

        // migrate data for existing components
        var prev_arch_components_iter = prev_archetype.components.iterator();
        while (prev_arch_components_iter.next()) |entry| {
            const component_type_name = entry.key_ptr.*;
            const prev_erased_storage = entry.value_ptr; // type erased from old archetype

            // get the corresponding storage from the target archetype
            const target_erased_storage = target_archetype.components.get(component_type_name).?;

            // copy data for entity from prev_erased_storage.ptr to entity in target_erased_storage.ptr
            try prev_erased_storage.copy(
                prev_erased_storage.ptr,
                target_erased_storage.ptr,
                entity_ptr.entity_idx,
                target_entity_idx,
            );
        }

        // add the new component too
        const new_component_storage = target_archetype.components.getPtr(@typeName(@TypeOf(component))).?;
        var specific_component_storage = TypeErasedComponentStorage.cast(new_component_storage.ptr, @TypeOf(component));
        try specific_component_storage.set(target_entity_idx, component);

        // update the entity pointer
        try self.entities.put(entity, EntityPointer{
            .entity_idx = target_entity_idx,
            .archetype_hash = target_archetype.hash,
        });

        // remove entity from previous archetype (needs attention to swapped entity)
        const remove_result = prev_archetype.remove(entity_ptr.entity_idx);

        // make sure we removed the right entity
        std.debug.assert(remove_result.removed_id == entity);

        // handle the swapped entity
        if (remove_result.swapped_id) |swapped_entity_id| {
            // an entity was swapped into the removed entity's old slot, so update its pointer
            if (self.entities.getPtr(swapped_entity_id)) |swapped_entity_ptr_ptr| {
                // update the index for the swapped entity - it's now at the index that the entity we just moved used to be
                swapped_entity_ptr_ptr.*.entity_idx = entity_ptr.entity_idx;
            } else {
                // this case should ideally not happen if the ECS state is consistent
                std.debug.print("Error: Swapped entity ID {d} not found in registry during remove!", .{swapped_entity_id});
                return error.InternalInconsistency;
            }
        }
    }
};

const ArchetypeHashType = u64;

const Archetype = struct {
    const EMPTY_ARCHETYPE_HASH: ArchetypeHashType = 0;

    const RemoveResult = struct {
        removed_id: EntityID,
        swapped_id: ?EntityID,
    };

    allocator: Allocator,

    hash: u64,

    /// Maps entity row index -> EntityID.
    entities: std.ArrayList(EntityID),

    /// Maps @typeName(Component) -> ErasedComponentStorage.
    ///
    /// Each index of the hashmap contains a list components, each list containing a different component type.
    components: std.StringArrayHashMap(TypeErasedComponentStorage),

    pub fn init(allocator: Allocator) Archetype {
        var archetype = Archetype{
            .allocator = allocator,
            .entities = std.ArrayList(EntityID).init(allocator),
            .components = std.StringArrayHashMap(TypeErasedComponentStorage).init(allocator),
            .hash = EMPTY_ARCHETYPE_HASH,
        };

        archetype.hash = EMPTY_ARCHETYPE_HASH;

        return archetype;
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();

        for (self.components.values()) |erased| {
            erased.deinit(self.allocator, erased.ptr);
        }
        self.components.deinit();
    }

    /// Replace the component at the given entity index.
    fn set(self: *Archetype, name: []const u8, entity_idx: usize, component: anytype) void {
        const type_erased_components = self.components.get(name).?;
        const components = TypeErasedComponentStorage.cast(type_erased_components.ptr, @TypeOf(component));
        try components.set(entity_idx, component);
    }

    fn remove(self: *Archetype, entity_idx: usize) RemoveResult {
        const last_idx = self.entities.items.len - 1;
        const removed_entity_id = self.entities.swapRemove(entity_idx); // This is the ID being removed

        var swapped_entity_id: ?EntityID = null;
        if (entity_idx != last_idx) {
            // if we didn't remove the last element, something was swapped into entity_idx
            // the ID now at entity_idx is the one that was at last_idx
            swapped_entity_id = self.entities.items[entity_idx];
        } // otherwise, we removed the last element and nothing was swapped into entity_idx

        // perform swapRemove on all component storages
        for (self.components.values()) |*type_erased| {
            // pass the pointer to the TypeErasedComponentStorage struct itself
            type_erased.swapRemove(type_erased.ptr, entity_idx);
        }

        return RemoveResult{
            .removed_id = removed_entity_id,
            .swapped_id = swapped_entity_id,
        };
    }
};

fn ComponentStorage(comptime Component: type) type {
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

const TypeErasedComponentStorage = struct {
    allocator: Allocator,

    /// Type erased pointer to the inherent ComponentStorage(Component).
    ptr: *anyopaque,

    deinit: *const fn (Allocator, type_erased_ptr: *anyopaque) void,

    /// Function to specifically swap-remove a component for the given entity index.
    swapRemove: *const fn (type_erased_ptr: *anyopaque, entity_idx: usize) void,

    /// Copy from a source component of a certain entity to a given destination.
    copy: *const fn (
        src_erased_ptr: *anyopaque,
        dst_erased_ptr: *anyopaque,
        src_entity_idx: usize,
        dst_entity_idx: usize,
    ) Allocator.Error!void,

    cloneType: ?*const fn (Allocator, dst_type_erased: *TypeErasedComponentStorage) error{OutOfMemory}!void,

    pub fn init(allocator: Allocator, comptime Component: type) !TypeErasedComponentStorage {
        const component_ptr = try allocator.create(ComponentStorage(Component));
        component_ptr.* = ComponentStorage(Component).init(allocator);

        return TypeErasedComponentStorage{
            .allocator = allocator,
            .ptr = component_ptr,
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
            .cloneType = (struct {
                fn func(alloc: Allocator, dst_erased: *TypeErasedComponentStorage) error{OutOfMemory}!void {
                    // Create the new storage as before
                    const new_storage = try alloc.create(ComponentStorage(Component));
                    new_storage.* = ComponentStorage(Component).init(alloc);

                    // important: initialize all fields of the destination struct
                    dst_erased.* = TypeErasedComponentStorage{
                        .allocator = alloc,
                        .ptr = new_storage,
                        .deinit = (struct {
                            fn inner(inner_alloc: Allocator, type_erased_ptr: *anyopaque) void {
                                const storage = TypeErasedComponentStorage.cast(type_erased_ptr, Component);
                                storage.deinit();
                                inner_alloc.destroy(storage);
                            }
                        }).inner,
                        .swapRemove = (struct {
                            fn inner(type_erased_ptr: *anyopaque, entity_idx: usize) void {
                                var storage = TypeErasedComponentStorage.cast(type_erased_ptr, Component);
                                storage.swapRemove(entity_idx);
                            }
                        }).inner,
                        .copy = (struct {
                            fn inner(
                                src_erased_ptr: *anyopaque,
                                dst_erased_ptr: *anyopaque,
                                src_entity_idx: usize,
                                dst_entity_idx: usize,
                            ) Allocator.Error!void {
                                var src_storage = TypeErasedComponentStorage.cast(src_erased_ptr, Component);
                                const dst_storage = TypeErasedComponentStorage.cast(dst_erased_ptr, Component);
                                try src_storage.copy(src_entity_idx, dst_storage, dst_entity_idx);
                            }
                        }).inner,
                        .cloneType = null, // to avoid recursion, the caller must manually copy over this function
                    };
                }
            }).func,
        };
    }

    /// Cast a type erased component storage to a ComponentStorage(Component) of the given component type.
    pub fn cast(erased_ptr: *anyopaque, comptime Component: type) *ComponentStorage(Component) {
        return @alignCast(@ptrCast(erased_ptr));
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var registry = try Registry.init(allocator);
    defer registry.deinit();

    const player = try registry.createEntity();
    std.debug.print("created player!\n", .{});

    const Name = []const u8;
    try registry.addComponent(player, @as(Name, "Jane"));

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Name)).?;

        const name_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Name);
        const name = name_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player name: {s}\n", .{name});
    }

    const Health = u8;
    try registry.addComponent(player, @as(Health, 10));

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Health)).?;

        const health_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Health);
        const health = health_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player health: {}\n", .{health});
    }

    const Position = struct {
        x: u32,
        y: u32,
    };
    try registry.addComponent(player, Position{ .x = 2, .y = 5 });

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Position)).?;

        const position_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Position);
        const position = position_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player position: {any}\n", .{position});
    }

    try registry.destroyEntity(player);
    std.debug.print("removed player!\n", .{});
}
