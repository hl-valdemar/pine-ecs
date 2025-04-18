const std = @import("std");

const pecs = @import("root.zig");
const Archetype = pecs.Archetype;
const ArchetypeHashType = pecs.ArchetypeHashType;
const TypeErasedComponentStorage = pecs.TypeErasedComponentStorage;

const Allocator = std.mem.Allocator;

pub const EntityID = u32;

pub const EntityPointer = struct {
    /// An ID for the archetype in which the entity data resides.
    archetype_hash: ArchetypeHashType,

    /// An index into the archetype table to the entity data.
    entity_idx: usize,
};

const RegistryError = error{
    NoSuchEntity,
    NoSuchArchetype,
    InternalInconsistency,
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

                // create an empty storage container of the correct type
                const new_empty_storage = try prev_component_storage.cloneType(self.allocator);
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
                entity_ptr.entity_idx,
                target_erased_storage,
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
