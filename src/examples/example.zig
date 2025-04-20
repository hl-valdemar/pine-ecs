const std = @import("std");

const Allocator = std.mem.Allocator;

const pecs = @import("pecs");

// example components
const Position = struct { x: u32, y: u32 };
const Health = struct { value: u8 };
const Name = struct { value: []const u8 };

// example movement system
const MovementSystem = struct {
    allocator: Allocator,

    pub fn init(alloc: Allocator) !MovementSystem {
        return MovementSystem{
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *MovementSystem) void {
        _ = self;
    }

    pub fn update(self: *MovementSystem, registry: *pecs.Registry) void {
        _ = self;

        var query_result = registry.query(.{ Position, Name }) catch |err| {
            std.debug.print("Failed to query entities: {}\n", .{err});
            return;
        };

        while (query_result.next()) |entity| {
            const position = entity.get(Position);
            const name = entity.get(Name);

            if (position) |p| {
                p.x += 2;
                p.y += 5;
            }

            if (name) |n| {
                std.debug.print("\nSystem log: {s} moved!\n", .{n.value});
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // SETUP //

    var registry = try pecs.Registry.init(allocator, .{ .remove_empty_archetypes = true });
    defer registry.deinit();

    const player = try registry.createEntity();
    defer _ = registry.destroyEntity(player) catch |err| std.debug.print("Failed to remove player entity: {}", .{err});
    try registry.addComponent(player, Name{ .value = "Jane" });
    try registry.addComponent(player, Health{ .value = 10 });
    try registry.addComponent(player, Position{ .x = 2, .y = 5 });

    const enemy = try registry.createEntity();
    defer _ = registry.destroyEntity(enemy) catch |err| std.debug.print("Failed to remove enemy entity: {}", .{err});
    try registry.addComponent(enemy, Health{ .value = 3 });
    try registry.addComponent(enemy, Position{ .x = 7, .y = 9 });

    var archetypes_iter = registry.archetypes.iterator();
    var archetypes_count: usize = 0;
    while (archetypes_iter.next()) |_| archetypes_count += 1;
    std.debug.print("\n", .{});
    std.debug.print("Archetypes: {}\n", .{archetypes_count});

    archetypes_iter = registry.archetypes.iterator();
    while (archetypes_iter.next()) |entry| {
        std.debug.print("\n", .{});
        std.debug.print("  Archetype hash: {}\n", .{entry.key_ptr.*});
        std.debug.print("  Archetype entity count: {}\n", .{entry.value_ptr.entities.items.len});

        const component_keys = entry.value_ptr.components.keys();
        std.debug.print("  Archetype component count: {}\n", .{component_keys.len});
        for (component_keys) |key| {
            std.debug.print("  ∟ {s}\n", .{key});
        }
    }

    // QUERIES //

    std.debug.print("\n", .{});
    std.debug.print("NOTE: Before System Updates\n", .{});

    var query_result_0 = try registry.query(.{Name});

    std.debug.print("\n", .{});
    std.debug.print("Query .{{ Name }}, results: {}\n", .{query_result_0.views.len});

    while (query_result_0.next()) |entity| {
        const name = entity.get(Name);

        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {}\n", .{entity.id()});
        std.debug.print("  ∟ Health: {any}\n", .{name});
    }

    var query_result_1 = try registry.query(.{ Position, Health });

    std.debug.print("\n", .{});
    std.debug.print("Query .{{ Position, Health }}, results: {}\n", .{query_result_1.views.len});

    while (query_result_1.next()) |entity| {
        const position = entity.get(Position);
        const health = entity.get(Health);

        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {}\n", .{entity.id()});
        std.debug.print("  ∟ Position: {any}\n", .{position});
        std.debug.print("  ∟ Health: {any}\n", .{health});
    }

    var query_result_2 = try registry.query(.{ Name, Position, Health });

    std.debug.print("\n", .{});
    std.debug.print("Query .{{ Name, Position, Health }}, results: {}\n", .{query_result_2.views.len});

    while (query_result_2.next()) |entity| {
        const name = entity.get(Name);
        const position = entity.get(Position);
        const health = entity.get(Health);

        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {}\n", .{entity.id()});
        std.debug.print("  ∟ Health: {any}\n", .{name});
        std.debug.print("  ∟ Position: {any}\n", .{position});
        std.debug.print("  ∟ Health: {any}\n", .{health});
    }

    // SYSTEMS //

    registry.registerSystem(MovementSystem) catch |err| {
        std.debug.print("Failed to register system: {}\n", .{err});
    };

    registry.updateSystems();

    std.debug.print("\n", .{});
    std.debug.print("NOTE: After System Updates\n", .{});

    var query_result_3 = try registry.query(.{Position});

    std.debug.print("\n", .{});
    std.debug.print("Query .{{ Position }}, results: {}\n", .{query_result_3.views.len});

    while (query_result_3.next()) |entity| {
        const position = entity.get(Position);

        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {}\n", .{entity.id()});
        std.debug.print("  ∟ Position: {any}\n", .{position});
    }
}
