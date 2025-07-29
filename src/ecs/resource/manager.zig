const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("../log.zig");
const ResourceQueryIterator = @import("../query/query.zig").ResourceQueryIterator;
const Singleton = @import("singleton.zig").Singleton;
const TypeErasedCollection = @import("collection.zig").TypeErasedCollection;
const TypeErasedSingleton = @import("singleton.zig").TypeErasedSingleton;

pub const ResourceError = error{
    ResourceNotRegistered,
    ResourceAlreadyRegistered,
};

pub const ResourceKind = enum {
    single,
    collection,
};

pub fn ResourceQuery(comptime R: type) type {
    return union(ResourceKind) {
        single: *Singleton(R),
        collection: ResourceQueryIterator(R),
    };
}

pub const ResourceManager = struct {
    allocator: Allocator,
    singletons: std.StringHashMap(TypeErasedSingleton),
    collections: std.StringHashMap(TypeErasedCollection),
    kind_map: std.StringHashMap(ResourceKind),

    pub fn init(allocator: Allocator) !ResourceManager {
        return ResourceManager{
            .allocator = allocator,
            .singletons = std.StringHashMap(TypeErasedSingleton).init(allocator),
            .collections = std.StringHashMap(TypeErasedCollection).init(allocator),
            .kind_map = std.StringHashMap(ResourceKind).init(allocator),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        // deinit singletons
        var singletons = self.singletons.valueIterator();
        while (singletons.next()) |resource| {
            resource.deinit();
        }
        self.singletons.deinit();

        // deinit collections
        var collections = self.collections.valueIterator();
        while (collections.next()) |collection| {
            collection.deinit();
        }
        self.collections.deinit();

        // deinit resource kind map
        self.kind_map.deinit();
    }

    /// Check whether a resource has been registered.
    pub fn isRegistered(self: *const ResourceManager, comptime R: type) bool {
        const name = @typeName(R);
        return self.kind_map.contains(name);
    }

    /// Register a resource.
    pub fn register(self: *ResourceManager, comptime R: type, kind: ResourceKind) !void {
        const name = @typeName(R);

        // make sure the resource follows conventions
        const DeinitFn = fn (*R) void;
        if (@hasDecl(R, "deinit") and @TypeOf(R.deinit) != DeinitFn) {
            @compileError(std.fmt.comptimePrint(
                \\Resource '{s}' has invalid deinit signature.
                \\Expected: {s}
                \\Found: {s}
                \\
                \\Make sure the function is public and matches the expected signature.
            , .{ name, @typeName(DeinitFn), @typeName(@TypeOf(R.deinit)) }));
        }

        // store the kind
        const kind_entry = try self.kind_map.getOrPut(name);
        if (!kind_entry.found_existing) {
            kind_entry.value_ptr.* = kind;
        } else return ResourceError.ResourceAlreadyRegistered;

        // instantiate the storage
        switch (kind) {
            .single => {
                const resource_entry = try self.singletons.getOrPut(name);
                if (!resource_entry.found_existing) {
                    resource_entry.value_ptr.* = try TypeErasedSingleton.init(self.allocator, R);
                } else return ResourceError.ResourceAlreadyRegistered;
                log.info("registered resource [{s}] as a singleton", .{name});
            },
            .collection => {
                const resource_entry = try self.collections.getOrPut(name);
                if (!resource_entry.found_existing) {
                    resource_entry.value_ptr.* = try TypeErasedCollection.init(self.allocator, R);
                } else return ResourceError.ResourceAlreadyRegistered;
                log.info("registered resource [{s}] as a collection", .{name});
            },
        }
    }

    /// Query for a resource.
    pub fn query(self: *const ResourceManager, comptime R: type) !ResourceQuery(R) {
        const name = @typeName(R);
        const kind = self.kind_map.get(name) orelse {
            return ResourceError.ResourceNotRegistered;
        };

        // construct the appropriate resource query object
        switch (kind) {
            .single => {
                if (self.singletons.get(name)) |type_erased| {
                    const storage = TypeErasedSingleton.cast(type_erased.ptr, R);
                    return ResourceQuery(R){ .single = storage };
                } else return ResourceError.ResourceNotRegistered;
            },
            .collection => {
                if (self.collections.get(name)) |type_erased| {
                    const storage = TypeErasedCollection.cast(type_erased.ptr, R);
                    const iter = try ResourceQueryIterator(R).init(self.allocator, storage.collection.items);
                    return ResourceQuery(R){ .collection = iter };
                } else return ResourceError.ResourceNotRegistered;
            },
        }
    }

    /// Push a *registered* resource to storage.
    pub fn push(self: *ResourceManager, resource: anytype) !void {
        const R = @TypeOf(resource);
        const name = @typeName(R);

        const kind = self.kind_map.get(name) orelse {
            return ResourceError.ResourceNotRegistered;
        };

        switch (kind) {
            .single => {
                if (self.singletons.getPtr(name)) |type_erased| {
                    const storage = TypeErasedSingleton.cast(type_erased.ptr, R);
                    storage.resource = resource;
                } else return ResourceError.ResourceNotRegistered;
            },
            .collection => {
                if (self.collections.getPtr(name)) |type_erased| {
                    const storage = TypeErasedCollection.cast(type_erased.ptr, R);
                    try storage.collection.append(resource);
                } else return ResourceError.ResourceNotRegistered;
            },
        }
    }

    pub fn RemoveInfo(comptime R: type) type {
        return union(ResourceKind) {
            single: R,
            collection: struct {
                R: R,
                index: usize,
            },
        };
    }

    pub fn remove(self: *ResourceManager, details: RemoveInfo) !void {
        switch (details) {
            .single => |R| {
                const name = @typeName(R);
                if (self.singletons.getPtr(name)) |type_erased| {
                    type_erased.destroyResource();
                } else return ResourceError.ResourceNotRegistered;
            },
            .collection => |col| {
                const name = @typeName(col.R);
                if (self.collections.getPtr(name)) |type_erased| {
                    type_erased.remove(col.index);
                } else return ResourceError.ResourceNotRegistered;
            },
        }
    }

    pub fn clear(self: *ResourceManager, comptime R: type) !void {
        const name = @typeName(R);
        const kind = self.kind_map.get(name) orelse {
            return ResourceError.ResourceNotRegistered;
        };

        switch (kind) {
            .single => {
                if (self.singletons.getPtr(name)) |type_erased| {
                    type_erased.destroyResource();
                } else return ResourceError.ResourceNotRegistered;
            },
            .collection => {
                if (self.collections.getPtr(name)) |type_erased| {
                    type_erased.clear();
                } else return ResourceError.ResourceNotRegistered;
            },
        }
    }
};
