const std = @import("std");

const ecs = @import("pecs");
const Registry = ecs.Registry;
const TypeErasedComponentStorage = ecs.TypeErasedComponentStorage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const Position = struct { x: u32, y: u32 };
    const Health = u8;
    const Name = []const u8;

    var registry = try Registry.init(allocator);
    defer registry.deinit();

    const player = try registry.createEntity();
    defer _ = registry.destroyEntity(player) catch |err| std.debug.print("Failed to remove player entity: {}", .{err});
    try registry.addComponent(player, @as(Name, "Jane"));
    try registry.addComponent(player, @as(Health, 10));
    try registry.addComponent(player, Position{ .x = 2, .y = 5 });

    const enemy = try registry.createEntity();
    defer _ = registry.destroyEntity(enemy) catch |err| std.debug.print("Failed to remove enemy entity: {}", .{err});
    try registry.addComponent(enemy, @as(Name, "John"));
    try registry.addComponent(enemy, @as(Health, 3));
    try registry.addComponent(enemy, Position{ .x = 7, .y = 9 });

    // QUERY EXPERIMENTS //

    std.debug.print("All position components before modification:\n", .{});
    var positions = try registry.query(Position);
    while (positions.next()) |position| {
        std.debug.print("  {any}\n", .{position});
        position.x += 10;
        position.y += 10;
    }

    std.debug.print("All position components after modification:\n", .{});
    positions = try registry.query(Position);
    while (positions.next()) |position| {
        std.debug.print("  {any}\n", .{position});
    }

    ///////////////////////
}
