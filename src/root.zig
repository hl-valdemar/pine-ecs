// global settings //

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("ecs/log.zig");

pub const Archetype = archetype.Archetype;
pub const ArchetypeHashType = archetype.ArchetypeHashType;

pub const TypeErasedComponentStorage = component.TypeErasedComponentStorage;
pub const TypeErasedResourceStorage = resource.TypeErasedResourceStorage;
pub const TypeErasedSystem = system.TypeErasedSystem;

pub const Registry = registry.Registry;
pub const EntityID = registry.EntityID;

pub const EntityView = query.EntityView;
pub const ComponentQueryIterator = query.ComponentQueryIterator;
pub const ResourceQueryIterator = query.ResourceQueryIterator;

pub const Plugin = plugin.Plugin;

pub const Pipeline = pipeline.Pipeline;
pub const PipelineBuilder = pipeline.PipelineBuilder;
pub const StageConfig = pipeline.StageConfig;
pub const Stage = pipeline.Stage;

// private imports //

const std = @import("std");
const archetype = @import("ecs/archetype.zig");
const component = @import("ecs/component.zig");
const registry = @import("ecs/registry.zig");
const query = @import("ecs/query.zig");
const system = @import("ecs/system.zig");
const resource = @import("ecs/resource/resource.zig");
const plugin = @import("ecs/plugin.zig");
const pipeline = @import("ecs/pipeline.zig");
