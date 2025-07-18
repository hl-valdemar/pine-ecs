const std = @import("std");

const ecs = @import("pine-ecs");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = ecs.log.logFn,
};

// declare some components
const Player = struct {}; // just a player tag
const Name = struct { value: []const u8 };
const Health = struct { value: u8 };
const Position = struct { x: i32, y: i32 };
const Velocity = struct { x: i32, y: i32 };

pub fn main() !void {
    // choose an allocator
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // initialize the ecs registry
    var registry = try ecs.Registry.init(allocator, .{
        .remove_empty_archetypes = true,
    });
    defer registry.deinit();

    // register systems
    // note: 1. it is also possible to register systems with a tag
    //       2. a request to update all systems registered with a certain tag can then be fired off
    try registry.registerSystem(GravitySystem);
    // try registry.registerSystem(GravitySystem, "update");

    // use the spawn command to easily create an entity and add components
    _ = try registry.spawn(.{
        Player{},
        Name{ .value = "Daxter" },
        Health{ .value = 3 },
        Position{ .x = 0, .y = 4 },
        Velocity{ .x = 0, .y = 0 },
    });

    try queryAndLog(&registry, "BEFORE systems processed");

    // process all systems
    registry.processSystems();
    // registry.processSystemsTagged("update");

    try queryAndLog(&registry, "AFTER systems processed");
}

/// Simple (and probably incorrectly calculated) gravity system.
const GravitySystem = struct {
    pub fn init(_: std.mem.Allocator) anyerror!GravitySystem {
        return GravitySystem{};
    }

    pub fn deinit(_: *GravitySystem) void {}

    pub fn process(_: *GravitySystem, registry: *ecs.Registry) anyerror!void {
        const gravity = 9;

        var entities = try registry.queryComponents(.{ Position, Velocity });
        while (entities.next()) |entity| {
            const position = entity.get(Position).?;
            const velocity = entity.get(Velocity).?;

            velocity.y += gravity;
            position.y += velocity.y;
        }
    }
};

// simple helper function
fn queryAndLog(registry: *ecs.Registry, moment: []const u8) !void {
    var entities = try registry.queryComponents(.{ Position, Velocity });

    std.debug.print(
        "\nEntities with position, velocity {s}: {}\n",
        .{ moment, entities.views.len },
    );

    while (entities.next()) |entity| {
        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {d}\n", .{entity.entity_id});
        std.debug.print("  ∟ Position component: {any}\n", .{entity.get(Position).?});
        std.debug.print("  ∟ Velocity component: {any}\n", .{entity.get(Velocity).?});
    }
}
