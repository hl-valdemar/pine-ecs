const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Pipeline = @import("pipeline.zig").Pipeline;
const Plugin = @import("plugin.zig").Plugin;
const query = @import("query.zig");
const EntityView = query.EntityView;
const ComponentQueryIterator = query.ComponentQueryIterator;
const ResourceQueryIterator = query.ResourceQueryIterator;
const QueryError = query.QueryError;
const BufferedEntityView = query.BufferedEntityView;
const BufferedComponentQueryIterator = query.BufferedComponentQueryIterator;
const res = @import("archetype.zig");
const Archetype = res.Archetype;
const ArchetypeHash = res.ArchetypeHash;
const Stage = @import("pipeline.zig").Stage;
const StageConfig = @import("pipeline.zig").StageConfig;
const TypeErasedComponentStorage = @import("component.zig").TypeErasedComponent;
const TypeErasedResourceStorage = @import("resource/singleton.zig").TypeErasedResourceStorage;
const UpdateBuffer = @import("component.zig").UpdateBuffer;
const ResourceManager = @import("resource/manager.zig").ResourceManager;
const ResourceKind = @import("resource/manager.zig").ResourceKind;
const ResourceQuery = @import("resource/manager.zig").ResourceQuery;
const RemoveInfo = @import("resource/manager.zig").RemoveInfo;

pub const EntityID = u32;

pub const EntityPointer = struct {
    /// An ID for the archetype in which the entity data resides.
    archetype_hash: ArchetypeHash,

    /// An index into the archetype table to the entity data.
    entity_idx: usize,
};

pub const RegistryConfig = struct {
    /// If true, remove archetypes when they have no entities.
    destroy_empty_archetypes: bool = true,
};

const RegistryError = error{
    NoSuchEntity,
    NoSuchArchetype,
    InternalInconsistency,
    UnregisteredResource,
};

pub const Registry = struct {
    allocator: Allocator,

    /// Maps an entity ID to a pointer to its archetype.
    entities: std.AutoHashMap(EntityID, EntityPointer),

    /// Maps an archetype hash to its corresponding archetype.
    archetypes: std.AutoHashMap(ArchetypeHash, Archetype),

    /// Data not related to any particular entities.
    // resources: std.StringHashMap(TypeErasedResourceStorage),
    resources: ResourceManager,

    /// Plugins bundle behavior.
    plugins: std.ArrayList(Plugin),

    pipeline: Pipeline,

    update_buffer: UpdateBuffer,
    config: RegistryConfig,

    pub fn init(allocator: Allocator, config: RegistryConfig) !Registry {
        var registry = Registry{
            .allocator = allocator,
            .entities = std.AutoHashMap(EntityID, EntityPointer).init(allocator),
            .archetypes = std.AutoHashMap(ArchetypeHash, Archetype).init(allocator),
            // .resources = std.StringHashMap(TypeErasedResourceStorage).init(allocator),
            .resources = try ResourceManager.init(allocator),
            .plugins = std.ArrayList(Plugin).init(allocator),
            .pipeline = Pipeline.init(allocator),
            .update_buffer = UpdateBuffer.init(allocator),
            .config = config,
        };

        errdefer {
            registry.entities.deinit();
            registry.archetypes.deinit();
            registry.resources.deinit();
            registry.plugins.deinit();
            registry.pipeline.deinit();
            registry.update_buffer.deinit();
        }

        // the empty archetype should always be present
        const void_archetype = Archetype.init(allocator);
        try registry.archetypes.put(void_archetype.hash, void_archetype);

        return registry;
    }

    pub fn deinit(self: *Registry) void {
        self.entities.deinit();

        var arch_iter = self.archetypes.valueIterator();
        while (arch_iter.next()) |archetype| {
            archetype.deinit();
        }
        self.archetypes.deinit();

        // var resource_iter = self.resources.valueIterator();
        // while (resource_iter.next()) |resource| {
        //     resource.deinit();
        // }
        self.resources.deinit();

        for (self.plugins.items) |plugin| {
            if (plugin.deinit_fn) |deinit_fn| deinit_fn(self);
        }
        self.plugins.deinit();

        self.pipeline.deinit();
        self.update_buffer.deinit();
    }

    /// Spawn an entity with initial components.
    ///
    /// An example might look as follows:
    /// ```zig
    /// const entity = try registry.spawn(.{
    ///     Player{},
    ///     Health{ .current = 3, .max = 5 },
    /// });
    /// ```
    pub fn spawn(self: *Registry, components: anytype) !EntityID {
        const entity = try self.createEntity();
        errdefer _ = self.destroyEntity(entity) catch unreachable; // here, the entity must have been created!

        // add components with reflection
        inline for (std.meta.fields(@TypeOf(components))) |field| {
            try self.addComponent(entity, @field(components, field.name));
        }

        return entity;
    }

    pub fn createEntity(self: *Registry) !EntityID {
        const new_id = self.entities.count();
        const empty_archetype = self.archetypes.getPtr(Archetype.VOID_HASH).?;

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
    pub fn destroyEntity(self: *Registry, entity: EntityID) RegistryError!void {
        const entity_ptr = self.entities.get(entity) orelse return RegistryError.NoSuchEntity;
        var archetype = self.archetypes.getPtr(entity_ptr.archetype_hash) orelse
            return RegistryError.NoSuchArchetype;

        // store old index before remove invalidates entity_ptr
        const original_entity_idx = entity_ptr.entity_idx;

        // remove entity data from archetype
        const removed_result = archetype.remove(original_entity_idx);

        // assert correctness
        if (removed_result.removed_id != entity) {
            log.err(
                "removed entity ID {d} does not correspond with requested entity ID {d}",
                .{ removed_result.removed_id, entity },
            );
            return RegistryError.InternalInconsistency;
        }

        // handle the swapped entity
        if (removed_result.swapped_id) |swapped_entity_id| {
            if (self.entities.getPtr(swapped_entity_id)) |swapped_entity_ptr_ptr| {
                // update the index for the swapped entity
                swapped_entity_ptr_ptr.*.entity_idx = original_entity_idx;
            } else {
                // should not happen in consistent state
                log.err(
                    "swapped entity ID {d} not found in registry during destroyEntity!",
                    .{swapped_entity_id},
                );
                return RegistryError.InternalInconsistency;
            }
        }

        // remove entity id from registry's entities list
        _ = self.entities.remove(entity); // at this point always true
    }

    /// Create a new archetype by extending an existing archetype.
    fn createExtendedArchetype(
        allocator: Allocator,
        prev_archetype: *Archetype,
        component_type_name: []const u8,
        comptime C: type,
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
        const new_type_erased_storage = try TypeErasedComponentStorage.init(allocator, C);
        errdefer new_type_erased_storage.deinit();

        try new_archetype.components.put(component_type_name, new_type_erased_storage);

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
            const prev_type_erased_storage = entry.value_ptr;
            const target_type_erased_storage = target_archetype.components.get(component_type_name).?;

            try prev_type_erased_storage.copy(
                src_entity_idx,
                target_type_erased_storage,
                dst_entity_idx,
            );
        }
    }

    /// Handle entity swapping after removal.
    fn handleSwappedEntity(
        self: *Registry,
        swapped_entity_id: ?EntityID,
        original_entity_idx: usize,
    ) RegistryError!void {
        if (swapped_entity_id) |entity_id| {
            if (self.entities.getPtr(entity_id)) |swapped_entity_ptr_ptr| {
                swapped_entity_ptr_ptr.*.entity_idx = original_entity_idx;
            } else {
                log.err("swapped entity ID {d} not found in registry!", .{entity_id});
                return RegistryError.InternalInconsistency;
            }
        }
    }

    pub fn addComponent(self: *Registry, entity: EntityID, component: anytype) !void {
        // get entity pointer or return error if entity doesn't exist
        const entity_ptr = self.entities.get(entity) orelse return RegistryError.NoSuchEntity;

        // store the hash before any HashMap operations that might invalidate pointers
        const prev_archetype_hash = entity_ptr.archetype_hash;

        // get the previous archetype and verify it exists
        const prev_archetype_check = self.archetypes.getPtr(prev_archetype_hash) orelse
            return RegistryError.NoSuchArchetype;

        // calculate type name and resulting archetype hash
        const component_type_name = @typeName(@TypeOf(component));
        const resulting_hash = prev_archetype_check.hash ^ std.hash_map.hashString(component_type_name);

        // get or create the target archetype
        const resulting_archetype_entry = try self.archetypes.getOrPut(resulting_hash);
        const target_archetype = resulting_archetype_entry.value_ptr;

        const created_new_archetype = !resulting_archetype_entry.found_existing;
        errdefer if (created_new_archetype) {
            _ = self.archetypes.remove(resulting_hash);
            target_archetype.deinit();
        };

        // IMPORTANT: Re-fetch prev_archetype after getOrPut, as the HashMap might have resized
        const prev_archetype = self.archetypes.getPtr(prev_archetype_hash) orelse
            return RegistryError.NoSuchArchetype;

        // setup new archetype if it doesn't exist
        if (created_new_archetype) {
            target_archetype.* = try createExtendedArchetype(
                self.allocator,
                prev_archetype,
                component_type_name,
                @TypeOf(component),
            );
        } else {
            // archetype already exists, assert its hash is correct
            std.debug.assert(target_archetype.hash == resulting_hash);
        }

        // add the entity id to the target archetype
        const target_entity_idx = target_archetype.entities.items.len;
        try target_archetype.entities.append(entity);
        errdefer _ = target_archetype.entities.pop();

        // migrate data for existing components
        try migrateEntityComponents(
            prev_archetype,
            target_archetype,
            entity_ptr.entity_idx,
            target_entity_idx,
        );

        // add the new component
        const new_component_storage = target_archetype.components.getPtr(component_type_name).?;
        var specific_component_storage = TypeErasedComponentStorage.cast(
            new_component_storage.ptr,
            @TypeOf(component),
        );
        try specific_component_storage.set(target_entity_idx, component);

        // update the entity pointer
        try self.entities.put(entity, EntityPointer{
            .entity_idx = target_entity_idx,
            .archetype_hash = target_archetype.hash,
        });

        // remove entity from previous archetype
        const remove_result = prev_archetype.remove(entity_ptr.entity_idx);
        std.debug.assert(remove_result.removed_id == entity);

        // destroy the archetype if no entities are left in it
        if (self.config.destroy_empty_archetypes and
            prev_archetype.entities.items.len == 0 and
            prev_archetype_hash != Archetype.VOID_HASH)
        {
            if (self.archetypes.fetchRemove(prev_archetype_hash)) |entry| {
                var archetype = entry.value;
                archetype.deinit();
            } else @panic("failed to remove empty archetype!\n"); // this shouldn't happen...
        }

        try handleSwappedEntity(self, remove_result.swapped_id, entity_ptr.entity_idx);
    }

    /// Check if an entity has a certain component.
    pub fn hasComponent(self: *Registry, entity: EntityID, comptime C: type) bool {
        // get component names from archetype
        const entity_ptr = self.entities.get(entity) orelse return false;
        const archetype = self.archetypes.get(entity_ptr.archetype_hash) orelse return false;
        const component_names = archetype.components.keys();

        // check for a match
        for (component_names) |name| {
            if (std.mem.eql(u8, name, @typeName(C)))
                return true;
        }

        return false;
    }

    /// Query for entities that have all specified component types.
    ///
    /// A query might look as follows:
    /// ```zig
    /// var result = try register.queryComponents(.{ Position, Velocity });
    /// defer result.deinit();
    ///
    /// while (result.next()) |entity| {
    ///     const position = entity.get(Position).?; // pointer to the position component
    ///     const velocity = entity.get(Velocity).?; // pointer to the velocity component
    ///
    ///     position.x += velocity.x;
    ///     position.y += velocity.y;
    /// }
    /// ```
    ///
    /// NB: caller owns the returned object and should `.deinit()` the allocator when after use.
    pub fn queryComponents(
        self: *Registry,
        component_types: anytype,
    ) !ComponentQueryIterator(component_types) {
        const ComponentTuple = @TypeOf(component_types);
        const component_info = @typeInfo(ComponentTuple);

        if (component_info != .@"struct" or !component_info.@"struct".is_tuple) {
            return QueryError.InvalidQuery;
        }

        // verify each element in the tuple is a type
        inline for (0..component_info.@"struct".fields.len) |i| {
            const field_name = component_info.@"struct".fields[i].name;
            if (@TypeOf(@field(component_types, field_name)) != type) {
                return QueryError.InvalidQuery;
            }
        }

        const component_count = component_info.@"struct".fields.len;

        // buffer to collect entity views
        var buffer = std.ArrayList(EntityView(component_types)).init(self.allocator);
        defer buffer.deinit();

        // store component type names for matching
        var component_names: [component_count][]const u8 = undefined;
        inline for (0..component_count) |i| {
            const field_name = component_info.@"struct".fields[i].name;
            const ComponentType = @field(component_types, field_name);
            component_names[i] = @typeName(ComponentType);
        }

        // find archetypes that contain all required components
        var archetype_iter = self.archetypes.valueIterator();
        next_archetype: while (archetype_iter.next()) |archetype| {
            // skip archetypes that don't have all required components
            for (component_names) |component_name| {
                if (!archetype.components.contains(component_name)) {
                    continue :next_archetype;
                }
            }

            // archetype has all components, process its entities
            for (archetype.entities.items, 0..) |entity_id, entity_idx| {
                var component_ptrs: [component_count]*anyopaque = undefined;

                // fill component pointers array
                inline for (0..component_count) |i| {
                    const component_name = component_names[i];

                    // get component storage for this type
                    const storage_ptr = archetype.components.get(component_name).?;

                    // get a raw pointer to the component
                    component_ptrs[i] = storage_ptr.getComponentPtr(entity_idx);
                }

                // create entity view with the component pointers
                try buffer.append(EntityView(component_types).init(entity_id, component_ptrs));
            }
        }

        return try ComponentQueryIterator(component_types).init(self.allocator, buffer.items);
    }

    /// Register a resource with the registry.
    pub fn registerResource(self: *Registry, comptime R: type, kind: ResourceKind) !void {
        try self.resources.register(R, kind);
    }

    /// Check whether a resource has been registered.
    pub fn resourceRegistered(self: *Registry, comptime R: type) bool {
        return self.resources.isRegistered(R);
    }

    /// Query for a *registered* resource.
    pub fn queryResource(self: *Registry, comptime R: type) !ResourceQuery(R) {
        return try self.resources.query(R);
    }

    /// Returns the first resource of the sort.
    ///
    /// NB: caller owns the returned copy - must be destroyed with given allocators' `.destroy(-)` method.
    // pub fn querySingleResource(self: *Registry, allocator: Allocator, comptime Resource: type) !*?Resource {
    //     var result = try self.queryResource(Resource);
    //     defer result.deinit();

    //     const resource_ptr = try allocator.create(?Resource);
    //     resource_ptr.* = result.next();

    //     return resource_ptr;
    // }

    /// Push a *registered* resource to the registry.
    pub fn pushResource(self: *Registry, resource: anytype) !void {
        try self.resources.push(resource);
    }

    pub fn clearResource(self: *Registry, comptime R: type) !void {
        try self.resources.clear(R);
    }

    pub fn removeResource(self: *Registry, comptime R: type, index: usize) !void {
        try self.resources.remove(RemoveInfo(R){
            .collection = .{
                .R = R,
                .index = index,
            },
        });
    }

    pub fn addPlugin(self: *Registry, plugin: Plugin) !void {
        try self.plugins.append(plugin);
        try plugin.init_fn(self);
    }

    /// Set a custom pipeline.
    pub fn setPipeline(self: *Registry, pipeline: Pipeline) void {
        self.pipeline.deinit(); // deinit old pipeline
        self.pipeline = pipeline;
    }

    pub fn queryComponentsBuffered(
        self: *Registry,
        component_types: anytype,
    ) !BufferedComponentQueryIterator(component_types) {
        const ComponentTuple = @TypeOf(component_types);
        const component_info = @typeInfo(ComponentTuple);

        if (component_info != .@"struct" or !component_info.@"struct".is_tuple) {
            return QueryError.InvalidQuery;
        }

        // verify each element in the tuple is a type
        inline for (0..component_info.@"struct".fields.len) |i| {
            const field_name = component_info.@"struct".fields[i].name;
            if (@TypeOf(@field(component_types, field_name)) != type) {
                return QueryError.InvalidQuery;
            }
        }

        const component_count = component_info.@"struct".fields.len;

        // buffer to collect entity views
        var buffer = std.ArrayList(BufferedEntityView(component_types)).init(self.allocator);
        defer buffer.deinit();

        // store component type names for matching
        var component_names: [component_count][]const u8 = undefined;
        inline for (0..component_count) |i| {
            const field_name = component_info.@"struct".fields[i].name;
            const ComponentType = @field(component_types, field_name);
            component_names[i] = @typeName(ComponentType);
        }

        // find archetypes that contain all required components
        var archetype_iter = self.archetypes.valueIterator();
        next_archetype: while (archetype_iter.next()) |archetype| {
            // skip archetypes that don't have all required components
            for (component_names) |component_name| {
                if (!archetype.components.contains(component_name)) {
                    continue :next_archetype;
                }
            }

            // archetype has all components, process its entities
            for (archetype.entities.items, 0..) |entity_id, entity_idx| {
                var component_ptrs: [component_count]*anyopaque = undefined;

                // fill component pointers array
                inline for (0..component_count) |i| {
                    const component_name = component_names[i];

                    // get component storage for this type
                    const storage_ptr = archetype.components.get(component_name).?;

                    // get a raw pointer to the component
                    component_ptrs[i] = storage_ptr.getComponentPtr(entity_idx);
                }

                // create entity view with the component pointers
                try buffer.append(BufferedEntityView(component_types){
                    .base_view = EntityView(component_types).init(entity_id, component_ptrs),
                    .update_buffer = &self.update_buffer,
                });
            }
        }

        return try BufferedComponentQueryIterator(component_types).init(self.allocator, buffer.items);
    }

    /// Apply all buffered updates.
    ///
    /// NB: if a component has been updated twice or more in one pass, the last update will take
    /// precedence over the others.
    pub fn applyBufferedUpdates(self: *Registry) void {
        for (self.update_buffer.updates.items) |update| {
            update.copy_fn(update.component_ptr, update.new_value_bytes);
        }
        self.update_buffer.clear();
    }

    /// Clear buffered updates without applying them.
    pub fn discardBufferedUpdates(self: *Registry) void {
        self.update_buffer.clear();
    }

    /// Check if there are pending updates.
    pub fn hasPendingUpdates(self: *Registry) bool {
        return self.update_buffer.updates.items.len > 0;
    }

    /// Add a new stage to the pipeline.
    pub fn addStage(
        self: *Registry,
        name: []const u8,
        config: StageConfig,
    ) !void {
        try self.pipeline.addStage(name, config);
    }

    /// Add a stage that runs after another stage.
    pub fn addStageAfter(
        self: *Registry,
        name: []const u8,
        after: []const u8,
        config: StageConfig,
    ) !void {
        try self.pipeline.addStageAfter(name, after, config);
    }

    /// Add a stage that runs before another stage.
    pub fn addStageBefore(
        self: *Registry,
        name: []const u8,
        before: []const u8,
        config: StageConfig,
    ) !void {
        try self.pipeline.addStageBefore(name, before, config);
    }

    /// Remove a stage from the pipeline.
    pub fn removeStage(self: *Registry, name: []const u8) !void {
        try self.pipeline.removeStage(name);
    }

    /// Add a system to a specific stage.
    pub fn addSystem(
        self: *Registry,
        stage_path: []const u8,
        comptime S: type,
    ) !void {
        try self.pipeline.addSystem(stage_path, S);
    }

    /// Add multiple systems to a stage at once.
    pub fn addSystems(
        self: *Registry,
        stage_path: []const u8,
        comptime systems: anytype,
    ) !void {
        try self.pipeline.addSystems(stage_path, systems);
    }

    /// Execute the entire pipeline.
    pub fn executePipeline(self: *Registry) void {
        self.pipeline.execute(self);
    }

    /// Execute only specific stages.
    pub fn executeStages(self: *Registry, stage_names: []const []const u8) !void {
        try self.pipeline.executeStages(self, stage_names);
    }

    /// Execute stages matching a predicate.
    pub fn executeStagesIf(
        self: *Registry,
        predicate: *const fn (stage_name: []const u8) bool,
    ) void {
        self.pipeline.executeStagesIf(self, predicate);
    }

    /// Get a stage by name for direct manipulation.
    pub fn getStage(self: *Registry, name: []const u8) ?*Stage {
        return self.pipeline.getStage(name);
    }

    /// Check if a stage exists.
    pub fn hasStage(self: *Registry, name: []const u8) bool {
        return self.pipeline.hasStage(name);
    }

    /// Check if multiple stages exist.
    pub fn hasStages(
        self: *Registry,
        stage_names: []const []const u8,
        operation: Pipeline.BooleanOperation,
    ) bool {
        return self.pipeline.hasStages(stage_names, operation);
    }

    /// Get all stage names in execution order.
    pub fn getStageNames(self: *Registry, allocator: Allocator) ![][]const u8 {
        return try self.pipeline.getStageNames(allocator);
    }

    pub fn getSystemNames(
        self: *Registry,
        allocator: Allocator,
        stage_name: []const u8,
    ) ![][]const u8 {
        return try self.pipeline.getSystemNames(allocator, stage_name);
    }

    pub fn stageEmpty(self: *Registry, stage_name: []const u8) bool {
        return self.pipeline.stageEmpty(stage_name);
    }

    pub fn stagesEmpty(
        self: *Registry,
        stage_names: []const []const u8,
        operation: Pipeline.BooleanOperation,
    ) bool {
        return self.pipeline.stagesEmpty(stage_names, operation);
    }
};
