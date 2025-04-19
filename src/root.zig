//-- public --//
pub const Archetype = archetype.Archetype;
pub const ArchetypeHashType = archetype.ArchetypeHashType;

pub const TypeErasedComponentStorage = component.TypeErasedComponentStorage;

pub const Registry = registry.Registry;
pub const EntityID = registry.EntityID;

pub const QueryIterator = query.QueryIterator;
pub const EntityView = query.EntityView;

//-- private --//
const archetype = @import("archetype.zig");
const component = @import("component.zig");
const registry = @import("registry.zig");
const query = @import("query.zig");
