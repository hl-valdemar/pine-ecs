const std = @import("std");

const ecs = @import("pine-ecs");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = ecs.log.logFn,
};

// declare a resource
const Potion = struct {
    kind: enum {
        health,
        stamina,
    },
    value: u8,
};

// you can also declare a resource requiring deinitialization via a .deinit() method
const Weapon = struct {
    kind: enum {
        sword,
        wand,
        bow,
    },
    damage: u8,

    fn init() Weapon {
        // probably some initialization requiring heap allocation...

        return .{
            .kind = .sword, // hardcoded for good luck
            .damage = 5, // -||-
        };
    }

    // note that the deinit function signature must follow this convention.
    // that is, `pub fn deinit(self: *R) void`.
    pub fn deinit(self: *Weapon) void {
        _ = self;
        std.debug.print("deinitializing the weapon resource...\n", .{});
        // deinitiazation here... (freeing allocated resources, etc.)
    }
};

pub fn main() !void {
    // choose an allocator
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // initialize the ecs registry
    var registry = try ecs.Registry.init(allocator, .{
        .destroy_empty_archetypes = true,
    });
    defer registry.deinit();

    // first register the resource type
    try registry.registerResource(Potion, .collection);

    // then push a resource of the registered type to the registry
    try registry.pushResource(Potion{
        .kind = .health,
        .value = 5,
    });
    try registry.pushResource(Potion{
        .kind = .stamina,
        .value = 2,
    });

    // you can now query for this resource
    var potions = switch (try registry.queryResource(Potion)) {
        .collection => |col| col,
        else => unreachable,
    };
    defer potions.deinit();

    while (potions.next()) |potion| {
        std.debug.print("{any}\n", .{potion});
    }

    // let's register the weapon resource
    try registry.registerResource(Weapon, .collection);

    // and push it to the registry
    try registry.pushResource(Weapon.init());

    // let's query to see if it's actually there
    var weapons = switch (try registry.queryResource(Weapon)) {
        .collection => |col| col,
        else => unreachable,
    };
    defer weapons.deinit();

    while (weapons.next()) |weapon| {
        std.debug.print("{any}\n", .{weapon});
    }
}
