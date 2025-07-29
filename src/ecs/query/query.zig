pub const ResourceQueryIterator = @import("resource.zig").ResourceQueryIterator;
pub const ComponentQueryIterator = @import("component.zig").ComponentQueryIterator;
pub const BufferedComponentQueryIterator = @import("component.zig").BufferedComponentQueryIterator;
pub const EntityView = @import("component.zig").EntityView;
pub const BufferedEntityView = @import("component.zig").BufferedEntityView;

pub const QueryError = error{
    InvalidQuery,
};
