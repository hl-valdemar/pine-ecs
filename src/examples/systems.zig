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
const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

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

    // register systems
    // try registry.registerSystem(GravitySystem);

    // use the spawn command to easily create an entity and add components
    _ = try registry.spawn(.{
        Player{},
        Name{ .value = "Daxter" },
        Health{ .value = 3 },
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 0, .y = 0 },
    });

    try queryAndLog(&registry, "BEFORE systems processed");

    // process all systems
    registry.processSystems();

    try queryAndLog(&registry, "AFTER systems processed");
}

const GravitySystem = struct {
    fn init(_: std.mem.Allocator) anyerror!GravitySystem {
        return GravitySystem{};
    }

    fn deinit(_: *GravitySystem) void {}

    fn process(_: *GravitySystem, registry: *pecs.Registry) anyerror!void {
        const gravity = 9.82;
        var entities = try registry.queryComponents(.{ Position, Velocity });
        for (entities.next()) |entity| {
            const position = entity.get(Position).?;
            const velocity = entity.get(Velocity).?;

            velocity.y += gravity;
            position.y += velocity.y;
        }
    }
};

// simple helper function
fn queryAndLog(registry: *pecs.Registry, moment: []const u8) !void {
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
