// global settings //
const std = @import("std");

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("pecs/log.zig");

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

/////////////////////

pub const UpdateBuffer = component.UpdateBuffer;

// private imports //

const archetype = @import("pecs/archetype.zig");
const component = @import("pecs/component.zig");
const registry = @import("pecs/registry.zig");
const query = @import("pecs/query.zig");
const system = @import("pecs/system.zig");
const resource = @import("pecs/resource.zig");
const plugin = @import("pecs/plugin.zig");
