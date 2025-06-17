const std = @import("std");
const Allocator = std.mem.Allocator;

const reg = @import("registry.zig");
const EntityID = reg.EntityID;
const Registry = reg.Registry;

pub const QueryError = error{
    InvalidQuery,
};

/// A view into an entity with its components for queries.
pub fn EntityView(comptime component_types: anytype) type {
    const ComponentTuple = @TypeOf(component_types);
    const component_info = @typeInfo(ComponentTuple);

    if (component_info != .@"struct" or !component_info.@"struct".is_tuple) {
        @compileError("Query components must be a tuple of types");
    }

    const component_count = component_info.@"struct".fields.len;

    return struct {
        const Self = @This();

        registry: *Registry,
        entity_id: EntityID,
        component_ptrs: [component_count]*anyopaque,

        /// Get a specific component by type.
        pub fn get(self: *const Self, comptime ComponentType: type) ?*ComponentType {
            comptime var i = 0;
            inline while (i < component_count) : (i += 1) {
                // extract the actual type directly from the tuple value
                const FieldType = @field(component_types, std.fmt.comptimePrint("{d}", .{i}));

                if (FieldType == ComponentType)
                    return @ptrCast(@alignCast(self.component_ptrs[i]));
            }
            return null;
        }

        /// Get the entity ID.
        pub fn id(self: *const Self) EntityID {
            return self.entity_id;
        }
    };
}

/// Iterator for component queries.
///
/// Note: this iterator clones the entity views under the assumption of
/// potential changes to the underlying data. This may be a good place to
/// optimize for memory consumption if this assumption proves naught.
pub fn ComponentQueryIterator(comptime component_types: anytype) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        registry: *Registry,
        views: []EntityView(component_types),
        index: usize = 0,
        freed: bool = false,

        pub fn init(
            allocator: Allocator,
            registry: *Registry,
            entity_views: []EntityView(component_types),
        ) !Self {
            return Self{
                .allocator = allocator,
                .registry = registry,
                .views = try allocator.dupe(EntityView(component_types), entity_views),
                .index = 0,
                .freed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.views);
            self.freed = true;
        }

        pub fn next(self: *Self) ?EntityView(component_types) {
            defer self.index += 1; // increment when done

            if (self.index < self.views.len) {
                return self.views[self.index];
            }

            // free the views array when iteration is complete
            if (self.index == self.views.len and !self.freed)
                self.deinit();

            return null;
        }
    };
}

/// Iterator of mutable entries for a given resource.
///
/// Note: this iterator clones the resources under the assumption of
/// potential changes to the underlying data. This may be a good place to
/// optimize for memory consumption if this assumption proves naught.
pub fn ResourceQueryIterator(comptime Resource: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        resources: []Resource,
        index: usize = 0,
        freed: bool = false,

        pub fn init(allocator: Allocator, resources: []Resource) !Self {
            return Self{
                .allocator = allocator,
                .resources = try allocator.dupe(Resource, resources),
                .index = 0,
                .freed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.resources);
            self.freed = true;
        }

        pub fn next(self: *Self) ?Resource {
            defer self.index += 1; // increment when done

            if (self.index < self.resources.len) {
                return self.resources[self.index];
            }

            // free the resources array when iteration is complete
            if (self.index == self.resources.len and !self.freed)
                self.deinit();

            return null;
        }
    };
}
