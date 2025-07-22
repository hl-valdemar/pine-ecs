const std = @import("std");
const Allocator = std.mem.Allocator;

const EntityID = @import("registry.zig").EntityID;
const TypeErasedComponentStorage = @import("component.zig").TypeErasedComponentStorage;

pub const ArchetypeHash = u64;

pub const Archetype = struct {
    pub const VOID_HASH: ArchetypeHash = 0;

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
            .hash = VOID_HASH,
        };

        archetype.hash = VOID_HASH;

        return archetype;
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();

        for (self.components.values()) |erased| {
            erased.deinit();
        }
        self.components.deinit();
    }

    /// Replace the component at the given entity index.
    pub fn set(self: *Archetype, name: []const u8, entity_idx: usize, component: anytype) !void {
        const type_erased_components = self.components.get(name).?;
        const components = TypeErasedComponentStorage.cast(type_erased_components.ptr, @TypeOf(component));
        try components.set(entity_idx, component);
    }

    pub fn remove(self: *Archetype, entity_idx: usize) RemoveResult {
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
            type_erased.swapRemove(entity_idx);
        }

        return RemoveResult{
            .removed_id = removed_entity_id,
            .swapped_id = swapped_entity_id,
        };
    }
};
