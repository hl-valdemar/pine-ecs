const manager = @import("manager.zig");
const singleton = @import("singleton.zig");
const collection = @import("collection.zig");

pub const ResourceKind = manager.ResourceKind;
pub const ResourceQuery = manager.ResourceQuery;
pub const TypeErasedSingleton = singleton.TypeErasedSingleton;
pub const TypeErasedCollection = collection.TypeErasedCollection;
