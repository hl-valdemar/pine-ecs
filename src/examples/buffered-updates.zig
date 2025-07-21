const std = @import("std");

const ecs = @import("pine-ecs");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = ecs.log.logFn,
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
    var registry = try ecs.Registry.init(allocator, .{
        .destroy_empty_archetypes = false,
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

    // now query and register updates
    var query = try registry.queryComponentsBuffered(.{ Position, Velocity });
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
    registry.applyBufferedUpdates();

    try queryAndLog(&registry, "AFTER");
}

// simple helper function
fn queryAndLog(registry: *ecs.Registry, moment: []const u8) !void {
    var entities = try registry.queryComponents(.{ Position, Velocity });

    std.debug.print(
        "\nEntities with position and velocity {s} buffered update: {}\n",
        .{ moment, entities.views.len },
    );

    while (entities.next()) |entity| {
        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {d}\n", .{entity.entity_id});
        std.debug.print("  ∟ Position component: {any}\n", .{entity.get(Position).?});
        std.debug.print("  ∟ Velocity component: {any}\n", .{entity.get(Velocity).?});
    }
}
