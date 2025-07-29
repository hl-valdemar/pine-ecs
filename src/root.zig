// global settings //

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("ecs/log.zig");

pub const Archetype = archetype.Archetype;
pub const ArchetypeHash = archetype.ArchetypeHash;

pub const ResourceKind = resource.ResourceKind;
pub const TypeErasedSingleton = resource.TypeErasedSingleton;
pub const TypeErasedCollection = resource.TypeErasedCollection;

pub const TypeErasedComponent = component.TypeErasedComponent;
pub const TypeErasedSystem = system.TypeErasedSystem;

pub const Registry = registry.Registry;
pub const Entity = registry.Entity;

pub const ComponentQueryIterator = query.ComponentQueryIterator;
pub const ResourceQueryIterator = query.ResourceQueryIterator;

pub const Plugin = plugin.Plugin;

pub const Pipeline = pipeline.Pipeline;
pub const StageConfig = pipeline.StageConfig;
pub const Stage = pipeline.Stage;

// private imports //

const std = @import("std");
const archetype = @import("ecs/archetype.zig");
const component = @import("ecs/component.zig");
const registry = @import("ecs/registry.zig");
const query = @import("ecs/query/query.zig");
const system = @import("ecs/system.zig");
const resource = @import("ecs/resource/resource.zig");
const plugin = @import("ecs/plugin.zig");
const pipeline = @import("ecs/pipeline.zig");
