const std = @import("std");

const ecs = @import("pine-ecs");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = ecs.log.logFn,
};

// declare some components
const Player = struct {}; // just a player tag
const Enemy = struct {}; // just an enemy tag
const Name = struct { value: []const u8 };
const Health = struct { value: u8 };

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
    const player1 = try registry.createEntity();
    try registry.addComponent(player1, Player{});
    try registry.addComponent(player1, Name{ .value = "Jane" });
    try registry.addComponent(player1, Health{ .value = 10 });

    // 2. use the spawn command to easily create an entity and add components
    _ = try registry.spawn(.{
        Player{},
        Name{ .value = "Daxter" },
        Health{ .value = 3 },
    });

    // why not spawn a little enemy
    const enemy = try registry.spawn(.{
        Enemy{},
        Health{ .value = 1 },
    });

    // check if the player has the player component
    std.debug.print("\nPlayer entity has player component: {}\n", .{registry.hasComponent(player1, Player)});

    // now check if the enemy has the player component
    std.debug.print("Enemy entity has player component: {}\n", .{registry.hasComponent(enemy, Player)});

    try queryAndLog(&registry, "BEFORE manual destruction of entity");

    // you can manually destroy an entity
    // note: entities not destroyed on registry.deinit() will
    // be automatically cleaned up in the process
    registry.destroyEntity(player1) catch std.log.err("failed to destroy entity!", .{});

    try queryAndLog(&registry, "AFTER manual destruction of entity");

    // components can be modified as follows
    // note: for batched updates, see `examples/buffered_updates.zig`
    var result = try registry.queryComponents(.{Health});
    defer result.deinit();

    const damage = 2;
    while (result.next()) |entity| {
        const health = entity.get(Health).?;
        if (health.value < damage) {
            health.value = 0;
        } else health.value -= damage;
    }

    try queryAndLog(&registry, "AFTER health modification");
}

// simple helper function
fn queryAndLog(registry: *ecs.Registry, moment: []const u8) !void {
    var entities = try registry.queryComponents(.{ Player, Name, Health });
    defer entities.deinit();

    std.debug.print(
        "\nEntities with player, name, and health {s}: {}\n",
        .{ moment, entities.views.len },
    );

    while (entities.next()) |entity| {
        std.debug.print("\n", .{});
        std.debug.print("  Entity id: {d}\n", .{entity.entity_id});
        std.debug.print("  ∟ Player component: {any}\n", .{entity.get(Player).?});
        std.debug.print("  ∟ Name component: {any} ({s})\n", .{ entity.get(Name).?, entity.get(Name).?.value });
        std.debug.print("  ∟ Health component: {any}\n", .{entity.get(Health).?});
    }
}
