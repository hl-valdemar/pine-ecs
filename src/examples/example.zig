const std = @import("std");

const ecs = @import("pecs");
const Registry = ecs.Registry;
const TypeErasedComponentStorage = ecs.TypeErasedComponentStorage;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var registry = try Registry.init(allocator);
    defer registry.deinit();

    const player = try registry.createEntity();
    std.debug.print("created player!\n", .{});

    const Name = []const u8;
    try registry.addComponent(player, @as(Name, "Jane"));

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Name)).?;

        const name_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Name);
        const name = name_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player name: {s}\n", .{name});
    }

    const Health = u8;
    try registry.addComponent(player, @as(Health, 10));

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Health)).?;

        const health_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Health);
        const health = health_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player health: {}\n", .{health});
    }

    const Position = struct {
        x: u32,
        y: u32,
    };
    try registry.addComponent(player, Position{ .x = 2, .y = 5 });

    if (registry.archetypes.get(registry.entities.get(player).?.archetype_hash)) |archetype| {
        const type_erased_storage = archetype.components.get(@typeName(Position)).?;

        const position_storage = TypeErasedComponentStorage.cast(type_erased_storage.ptr, Position);
        const position = position_storage.get(registry.entities.get(player).?.entity_idx);

        std.debug.print("player position: {any}\n", .{position});
    }

    try registry.destroyEntity(player);
    std.debug.print("removed player!\n", .{});
}
