const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // expose the module to the world
    _ = b.addModule("pecs", .{
        .root_source_file = b.path("src/root.zig"),
    });
}
