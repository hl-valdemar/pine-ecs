const std = @import("std");

const pecs = @import("pecs");
const Registry = pecs.Registry;
const TypeErasedComponentStorage = pecs.TypeErasedComponentStorage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const Position = struct { x: u32, y: u32 };
    const Health = struct { value: u8 };
    const Name = struct { value: []const u8 };

    var registry = try Registry.init(allocator, .{ .remove_empty_archetypes = true });
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

    var query_result_0 = try registry.query(.{Name});

    std.debug.print("\n", .{});
    std.debug.print("Query result: {}\n", .{query_result_0.views.len});

    while (query_result_0.next()) |entity| {
        const name = entity.get(Name);

        std.debug.print("\n", .{});
        std.debug.print("  Entity ID: {}\n", .{entity.id()});
        std.debug.print("  ∟ Health: {any}\n", .{name});
    }

    var query_result_1 = try registry.query(.{ Position, Health });

    std.debug.print("\n", .{});
    std.debug.print("Query result: {}\n", .{query_result_1.views.len});

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
    std.debug.print("Query result: {}\n", .{query_result_2.views.len});

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
}
