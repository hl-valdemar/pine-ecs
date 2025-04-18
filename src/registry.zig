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

        errdefer {
            registry.entities.deinit();
            registry.archetypes.deinit();
        }

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

        // add new entity to archetype's list
        const entity_idx = empty_archetype.entities.items.len;
        try empty_archetype.entities.append(new_id);

        // remove the entity if entity pointer creation fails
        errdefer _ = empty_archetype.entities.pop();

        // add entity pointer to the registry
        try self.entities.put(new_id, EntityPointer{
            .archetype_hash = empty_archetype.hash,
            .entity_idx = entity_idx,
        });

        return new_id;
    }

    /// Returns true if the entity was succesfully removed, false otherwise.
    pub fn destroyEntity(self: *Registry, entity: EntityID) RegistryError!bool {
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
        return self.entities.remove(entity);
    }

    /// Create a new archetype with a new component type.
    fn createArchetypeWithComponent(
        allocator: Allocator,
        prev_archetype: *Archetype,
        component_type_name: []const u8,
        comptime ComponentType: type,
    ) !Archetype {
        const resulting_hash = prev_archetype.hash ^ std.hash_map.hashString(component_type_name);

        var new_archetype = Archetype.init(allocator);
        errdefer new_archetype.deinit();

        new_archetype.hash = resulting_hash;

        // copy component storage types from previous archetype
        var prev_arch_components_iter = prev_archetype.components.iterator();
        while (prev_arch_components_iter.next()) |entry| {
            const prev_component_storage = entry.value_ptr;

            const new_empty_storage = try prev_component_storage.cloneType(allocator);
            errdefer new_empty_storage.deinit();

            try new_archetype.components.put(entry.key_ptr.*, new_empty_storage);
        }

        // add storage for the new component type
        const new_erased_storage = try TypeErasedComponentStorage.init(allocator, ComponentType);
        errdefer new_erased_storage.deinit();

        try new_archetype.components.put(component_type_name, new_erased_storage);

        return new_archetype;
    }

    /// Migrate entity components between archetypes.
    fn migrateEntityComponents(
        prev_archetype: *Archetype,
        target_archetype: *Archetype,
        src_entity_idx: usize,
        dst_entity_idx: usize,
    ) !void {
        var prev_arch_components_iter = prev_archetype.components.iterator();
        while (prev_arch_components_iter.next()) |entry| {
            const component_type_name = entry.key_ptr.*;
            const prev_erased_storage = entry.value_ptr;
            const target_erased_storage = target_archetype.components.get(component_type_name).?;

            try prev_erased_storage.copy(
                src_entity_idx,
                target_erased_storage,
                dst_entity_idx,
            );
        }
    }

    /// Handle entity swapping after removal.
    fn handleSwappedEntity(
        self: *Registry,
        swapped_entity_id: ?EntityID,
        original_entity_idx: usize,
    ) !void {
        if (swapped_entity_id) |entity_id| {
            if (self.entities.getPtr(entity_id)) |swapped_entity_ptr_ptr| {
                swapped_entity_ptr_ptr.*.entity_idx = original_entity_idx;
            } else {
                std.debug.print("Error: Swapped entity ID {d} not found in registry!", .{entity_id});
                return error.InternalInconsistency;
            }
        }
    }

    pub fn addComponent(self: *Registry, entity: EntityID, component: anytype) !void {
        // get entity pointer or return error if entity doesn't exist
        const entity_ptr = self.entities.get(entity) orelse return error.NoSuchEntity;
        var prev_archetype = self.archetypes.getPtr(entity_ptr.archetype_hash) orelse return error.NoSuchArchetype;

        // calculate type name and resulting archetype hash
        const component_type_name = @typeName(@TypeOf(component));
        const resulting_hash = prev_archetype.hash ^ std.hash_map.hashString(component_type_name);

        // get or create the target archetype
        const resulting_archetype_entry = try self.archetypes.getOrPut(resulting_hash);
        const target_archetype = resulting_archetype_entry.value_ptr;

        const created_new_archetype = !resulting_archetype_entry.found_existing;
        errdefer if (created_new_archetype) {
            _ = self.archetypes.remove(resulting_hash);
            target_archetype.deinit();
        };

        // setup new archetype if it doesn't exist
        if (created_new_archetype) {
            target_archetype.* = try createArchetypeWithComponent(
                self.allocator,
                prev_archetype,
                component_type_name,
                @TypeOf(component),
            );
        } else {
            // archetype already exists, assert its hash is correct
            std.debug.assert(target_archetype.hash == resulting_hash);
        }

        // add the entity ID to the target archetype
        const target_entity_idx = target_archetype.entities.items.len;
        try target_archetype.entities.append(entity);
        errdefer _ = target_archetype.entities.pop();

        // migrate data for existing components
        try migrateEntityComponents(prev_archetype, target_archetype, entity_ptr.entity_idx, target_entity_idx);

        // add the new component
        const new_component_storage = target_archetype.components.getPtr(component_type_name).?;
        var specific_component_storage = TypeErasedComponentStorage.cast(new_component_storage.ptr, @TypeOf(component));
        try specific_component_storage.set(target_entity_idx, component);

        // update the entity pointer
        try self.entities.put(entity, EntityPointer{
            .entity_idx = target_entity_idx,
            .archetype_hash = target_archetype.hash,
        });

        // remove entity from previous archetype
        const remove_result = prev_archetype.remove(entity_ptr.entity_idx);
        std.debug.assert(remove_result.removed_id == entity);

        try handleSwappedEntity(self, remove_result.swapped_id, entity_ptr.entity_idx);
    }

    pub fn query(self: *Registry, comptime Component: type) !QueryIterator(Component) {
        // buffer for collecting values for the iterator
        var buffer = std.ArrayList(Component).init(self.allocator);
        defer buffer.deinit();

        // look for the given component type in all archetypes
        var archetype_iter = self.archetypes.valueIterator();
        while (archetype_iter.next()) |archetype| {

            // look for the component type among components of each archetype
            var component_iter = archetype.components.iterator();
            while (component_iter.next()) |entry| {

                // if component types match, add all components of the type to the buffer
                const component_name = entry.key_ptr.*;
                if (std.mem.eql(u8, component_name, @typeName(Component))) {
                    const type_erased_storage = entry.value_ptr.*;
                    const component_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Component);
                    for (component_storage.components.items) |component| {
                        try buffer.append(component);
                    }
                }
            }
        }

        // copy buffered values into iterator
        return QueryIterator(Component).init(buffer.items);
    }
};

pub fn QueryIterator(comptime Component: type) type {
    return struct {
        const Self = @This();

        values: []Component,
        value_ptr: usize = 0,

        pub fn init(data: []Component) Self {
            return Self{
                .values = data,
                .value_ptr = 0,
            };
        }

        pub fn next(self: *Self) ?Component {
            if (self.value_ptr < self.values.len) {
                const next_val = self.values[self.value_ptr];
                self.value_ptr += 1;
                return next_val;
            }
            return null;
        }
    };
}
