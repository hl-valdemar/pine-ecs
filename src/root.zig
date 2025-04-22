//-- public --//
pub const Archetype = archetype.Archetype;
pub const ArchetypeHashType = archetype.ArchetypeHashType;

pub const TypeErasedComponentStorage = component.TypeErasedComponentStorage;
pub const TypeErasedResourceStorage = resource.TypeErasedResourceStorage;

pub const Registry = registry.Registry;
pub const EntityID = registry.EntityID;

pub const EntityView = query.EntityView;
pub const ComponentQueryIterator = query.ComponentQueryIterator;
pub const ResourceQueryIterator = query.ResourceQueryIterator;

pub const SystemManager = system.SystemManager;

//-- private --//
const archetype = @import("archetype.zig");
const component = @import("component.zig");
const registry = @import("registry.zig");
const query = @import("query.zig");
const system = @import("system.zig");
const resource = @import("resource.zig");
