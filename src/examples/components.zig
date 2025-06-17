const std = @import("std");
const pecs = @import("pecs");

// use pecs' logging format
pub const std_options = std.Options{
    .logFn = pecs.log.logFn,
};

// declare some components
const Player = struct {}; // just a player tag
const Name = struct { value: []const u8 };
const Health = struct { value: u8 };

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
    try registry.addComponent(player, Player{});
    try registry.addComponent(player, Name{ .value = "Jane" });
    try registry.addComponent(player, Health{ .value = 10 });

    // 2. use the spawn command to easily create an entity and add components
    _ = try registry.spawn(.{
        Player{},
        Name{ .value = "Daxter" },
        Health{ .value = 3 },
    });

    try queryAndLog(&registry, "BEFORE manual destruction of entity");

    // you can manually destroy an entity
    // note: entities not destroyed on registry.deinit() will
    // be automatically cleaned up in the process
    registry.destroyEntity(player) catch std.log.err("failed to destroy entity!", .{});

    try queryAndLog(&registry, "AFTER manual destruction of entity");

    // components can be modified as follows
    // note: for batched updates, see `examples/buffered_updates.zig`
    var result = try registry.queryComponents(.{Health});
    while (result.next()) |entity| {
        const health = entity.get(Health).?;
        health.value -= 2;
    }

    try queryAndLog(&registry, "AFTER health modification");
}

// simple helper function
fn queryAndLog(registry: *pecs.Registry, moment: []const u8) !void {
    var result = try registry.queryComponents(.{ Player, Name, Health });

    std.debug.print(
        "\nEntities with player, name, and health {s}: {}\n",
        .{ moment, result.views.len },
    );

    while (result.next()) |entity| {
        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {d}\n", .{entity.entity_id});
        std.debug.print("  ∟ Player component: {any}\n", .{entity.get(Player).?});
        std.debug.print("  ∟ Name component: {any} ({s})\n", .{ entity.get(Name).?, entity.get(Name).?.value });
        std.debug.print("  ∟ Health component: {any}\n", .{entity.get(Health).?});
    }
}
