const std = @import("std");
const pecs = @import("pecs");

// use pecs' logging format
pub const std_options = std.Options{
    .logFn = pecs.log.logFn,
};

// declare some components
const Position = struct { x: i32, y: i32 };
const Velocity = struct { x: i32, y: i32 };

pub fn main() !void {
    // choose an allocator
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // initialize the ecs registry
    var registry = try pecs.Registry.init(allocator, .{
        .remove_empty_archetypes = true,
    });
    defer registry.deinit();

    // you can either:
    // 1. manually spawn entity and add components
    const player = try registry.createEntity();
    try registry.addComponent(player, Position{ .x = 5, .y = 10 });
    try registry.addComponent(player, Velocity{ .x = 2, .y = 5 });

    // 2. use the spawn command to easily create an entity and add components
    _ = try registry.spawn(.{
        Position{ .x = 1, .y = 3 },
        Velocity{ .x = 3, .y = 1 },
    });

    // it's possible to query for components with the intention of batching updates
    // note: this currently requires that an update buffer be passed
    var update_buffer = pecs.UpdateBuffer.init(allocator);
    defer update_buffer.deinit();

    // now query and register updates
    var query = try registry.queryComponentsBuffered(.{ Position, Velocity }, &update_buffer);
    while (query.next()) |entity| {
        const velocity = entity.get(Velocity).?;

        if (entity.getMut(Position)) |pos| {
            const current = pos.get();
            try pos.set(.{
                .x = current.x + velocity.x,
                .y = current.y + velocity.y,
            });
        }
    }

    try queryAndLog(&registry, "BEFORE");

    // finally, apply all updates at once
    registry.applyBufferedUpdates(&update_buffer);

    try queryAndLog(&registry, "AFTER");
}

// simple helper function
fn queryAndLog(registry: *pecs.Registry, moment: []const u8) !void {
    var result = try registry.queryComponents(.{ Position, Velocity });

    std.debug.print(
        "\nEntities with position and velocity {s} buffered update: {}\n",
        .{ moment, result.views.len },
    );

    while (result.next()) |entity| {
        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {d}\n", .{entity.entity_id});
        std.debug.print("  ∟ Position component: {any}\n", .{entity.get(Position).?});
        std.debug.print("  ∟ Velocity component: {any}\n", .{entity.get(Velocity).?});
    }
}
