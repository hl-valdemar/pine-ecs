const std = @import("std");
const Allocator = std.mem.Allocator;

/// Iterator of mutable entries for a given resource.
///
/// Note: this iterator clones the resources under the assumption of
/// potential changes to the underlying data. This may be a good place to
/// optimize for memory consumption if this assumption proves naught.
pub fn ResourceQueryIterator(comptime R: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        resources: []R,
        index: usize = 0,

        pub fn init(allocator: Allocator, resources: []R) !Self {
            return Self{
                .allocator = allocator,
                .resources = try allocator.dupe(R, resources),
                .index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.resources);
        }

        pub fn next(self: *Self) ?R {
            defer self.index += 1; // increment when done

            if (self.index < self.resources.len)
                return self.resources[self.index];

            return null;
        }
    };
}
