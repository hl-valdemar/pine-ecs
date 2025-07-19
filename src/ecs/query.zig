const std = @import("std");
const Allocator = std.mem.Allocator;

const reg = @import("registry.zig");
const EntityID = reg.EntityID;
const Registry = reg.Registry;
const UpdateBuffer = @import("component.zig").UpdateBuffer;

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

        entity_id: EntityID,
        component_ptrs: [component_count]*anyopaque,

        pub fn init(
            entity_id: EntityID,
            component_ptrs: [component_count]*anyopaque,
        ) Self {
            return Self{
                .entity_id = entity_id,
                .component_ptrs = component_ptrs,
            };
        }

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
        views: []EntityView(component_types),
        index: usize = 0,
        freed: bool = false,

        pub fn init(
            allocator: Allocator,
            entity_views: []EntityView(component_types),
        ) !Self {
            return Self{
                .allocator = allocator,
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

pub fn BufferedEntityView(comptime component_types: anytype) type {
    const BaseView = EntityView(component_types);

    return struct {
        const Self = @This();

        base_view: BaseView,
        update_buffer: *UpdateBuffer,

        /// Get a component for reading (same as regular EntityView).
        pub fn get(self: *const Self, comptime ComponentType: type) ?*const ComponentType {
            return self.base_view.get(ComponentType);
        }

        /// Get a mutable component that queues updates.
        pub fn getMut(self: *Self, comptime ComponentType: type) ?BufferedComponent(ComponentType) {
            if (self.base_view.get(ComponentType)) |component_ptr| {
                return BufferedComponent(ComponentType){
                    .ptr = component_ptr,
                    .entity_id = self.base_view.entity_id,
                    .update_buffer = self.update_buffer,
                };
            }
            return null;
        }

        pub fn id(self: *const Self) EntityID {
            return self.base_view.entity_id;
        }
    };
}

pub fn BufferedComponent(comptime ComponentType: type) type {
    return struct {
        const Self = @This();

        ptr: *ComponentType,
        entity_id: EntityID,
        update_buffer: *UpdateBuffer,

        /// Queue a new value for this component.
        pub fn set(self: Self, new_value: ComponentType) !void {
            const bytes = try self.update_buffer.allocator.alloc(u8, @sizeOf(ComponentType));
            @memcpy(bytes, std.mem.asBytes(&new_value));

            const copy_fn = struct {
                fn copy(dst_ptr: *anyopaque, src_bytes: []const u8) void {
                    const typed_dst: *ComponentType = @ptrCast(@alignCast(dst_ptr));
                    typed_dst.* = std.mem.bytesToValue(ComponentType, src_bytes[0..@sizeOf(ComponentType)]);
                }
            }.copy;

            try self.update_buffer.updates.append(.{
                .entity_id = self.entity_id,
                .component_type_name = @typeName(ComponentType),
                .component_ptr = self.ptr,
                .new_value_bytes = bytes,
                .copy_fn = copy_fn,
            });
        }

        /// Get read-only access to current value.
        pub fn get(self: Self) *const ComponentType {
            return self.ptr;
        }
    };
}

/// Iterator for buffered component queries.
///
/// Note: this iterator clones the entity views under the assumption of
/// potential changes to the underlying data. This may be a good place to
/// optimize for memory consumption if this assumption proves naught.
pub fn BufferedComponentQueryIterator(comptime component_types: anytype) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        views: []BufferedEntityView(component_types),
        index: usize = 0,
        freed: bool = false,

        pub fn init(
            allocator: Allocator,
            entity_views: []BufferedEntityView(component_types),
        ) !Self {
            return Self{
                .allocator = allocator,
                .views = try allocator.dupe(BufferedEntityView(component_types), entity_views),
                .index = 0,
                .freed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.views);
            self.freed = true;
        }

        pub fn next(self: *Self) ?*BufferedEntityView(component_types) {
            defer self.index += 1; // increment when done

            if (self.index < self.views.len) {
                return &self.views[self.index];
            }

            // free the views array when iteration is complete
            if (self.index == self.views.len and !self.freed)
                self.deinit();

            return null;
        }
    };
}
