// global settings //
const std = @import("std");

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("ecs/log.zig");

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

pub const Plugin = plugin.Plugin;

// private imports //

const archetype = @import("ecs/archetype.zig");
const component = @import("ecs/component.zig");
const registry = @import("ecs/registry.zig");
const query = @import("ecs/query.zig");
const system = @import("ecs/system.zig");
const resource = @import("ecs/resource.zig");
const plugin = @import("ecs/plugin.zig");
