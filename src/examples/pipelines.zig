const std = @import("std");
const ecs = @import("pine-ecs");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = ecs.log.logFn,
};

// components
const Position = struct { x: i32, y: i32 };
const Velocity = struct { x: i32, y: i32 };
const Health = struct { current: u32, max: u32 };
const Player = struct {};
const Enemy = struct { ai_type: enum { aggressive, defensive } };

// resources
const GameState = struct {
    paused: bool = false,
    frame_count: u64 = 0,
};

const InputState = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    std.log.info("=== Pine ECS Pipeline Example ===", .{});

    // example 1: basic pipeline usage
    try basicPipelineExample(allocator);

    // example 2: advanced pipeline with conditions
    try advancedPipelineExample(allocator);

    // example 3: dynamic pipeline modification
    try dynamicPipelineExample(allocator);
}

fn basicPipelineExample(allocator: std.mem.Allocator) !void {
    std.log.info("\n--- Basic Pipeline Example ---", .{});

    // create registry with default pipeline
    var registry = try ecs.Registry.init(allocator, .{
        .destroy_empty_archetypes = true,
    });
    defer registry.deinit();

    // add stages to the pipeline
    try registry.pipeline.addStage("startup", .{});
    try registry.pipeline.addStage("pre_update", .{});
    try registry.pipeline.addStage("update", .{});
    try registry.pipeline.addStage("post_update", .{});
    try registry.pipeline.addStage("render", .{});

    // add systems to the stages
    try registry.pipeline.addSystem("startup", InitSystem);
    try registry.pipeline.addSystem("pre_update", InputSystem);
    try registry.pipeline.addSystem("update", MovementSystem);
    try registry.pipeline.addSystem("update", CollisionSystem);
    try registry.pipeline.addSystem("render", RenderSystem);

    // create some entities
    _ = try registry.spawn(.{
        Player{},
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 0 },
        Health{ .current = 100, .max = 100 },
    });

    _ = try registry.spawn(.{
        Enemy{ .ai_type = .aggressive },
        Position{ .x = 10, .y = 10 },
        Velocity{ .x = -1, .y = 0 },
        Health{ .current = 50, .max = 50 },
    });

    // register resources
    try registry.registerResource(InputState);
    try registry.pushResource(InputState{});

    // process all systems in pipeline order
    std.log.info("processing full pipeline...", .{});
    registry.pipeline.execute(&registry);

    // process only specific stages
    std.log.info("processing only update and render stages...", .{});
    try registry.pipeline.executeStages(&registry, &.{ "update", "render" });
}

fn advancedPipelineExample(allocator: std.mem.Allocator) !void {
    std.log.info("\n--- Advanced Pipeline Example ---", .{});

    // create registry without default pipeline
    var registry = try ecs.Registry.init(allocator, .{
        .destroy_empty_archetypes = true,
    });
    defer registry.deinit();

    // build a custom pipeline directly
    try registry.pipeline.addStage("init", .{});
    try registry.pipeline.addStage("input", .{});
    try registry.pipeline.addStage("ai", .{
        // only run ai when game is not paused
        .run_condition = struct {
            fn condition(reg: *ecs.Registry) bool {
                const state = reg.querySingleResource(std.heap.page_allocator, GameState) catch return true;
                defer std.heap.page_allocator.destroy(state);
                return !(state.* orelse GameState{}).paused;
            }
        }.condition,
    });
    try registry.pipeline.addStageAfter("physics", "ai", .{
        .continue_on_error = true, // don't stop if physics fails
    });
    try registry.pipeline.addStage("render", .{});
    try registry.pipeline.addStage("debug", .{
        .enabled = false, // disabled by default
    });

    // add systems to stages
    try registry.pipeline.addSystem("init", InitSystem);
    try registry.pipeline.addSystem("input", InputSystem);
    try registry.pipeline.addSystems("ai", .{ AIDecisionSystem, AIMovementSystem });
    try registry.pipeline.addSystem("physics", PhysicsSystem);
    try registry.pipeline.addSystem("render", RenderSystem);
    try registry.pipeline.addSystem("debug", DebugSystem);

    // set up game state
    try registry.registerResource(GameState);
    try registry.pushResource(GameState{ .paused = false });

    // process normally
    std.log.info("processing with game running...", .{});
    registry.pipeline.execute(&registry);

    // pause the game and process again
    try registry.clearResource(GameState);
    try registry.pushResource(GameState{ .paused = true });

    std.log.info("processing with game paused (ai should skip)...", .{});
    registry.pipeline.execute(&registry);

    // enable debug stage
    if (registry.pipeline.getStage("debug")) |debug_stage| {
        debug_stage.setEnabled(true);
    }

    std.log.info("processing with debug enabled...", .{});
    registry.pipeline.execute(&registry);
}

fn dynamicPipelineExample(allocator: std.mem.Allocator) !void {
    std.log.info("\n--- Dynamic Pipeline Example ---", .{});

    var registry = try ecs.Registry.init(allocator, .{
        .destroy_empty_archetypes = true,
    });
    defer registry.deinit();

    // start with a simple pipeline
    try registry.pipeline.addStage("update", .{});
    try registry.pipeline.addSystem("update", BasicUpdateSystem);

    registry.pipeline.debugPrint();

    // dynamically add stages based on game state.
    // add combat system when enemies are present.
    _ = try registry.spawn(.{Enemy{ .ai_type = .defensive }});

    var enemies = try registry.queryComponents(.{Enemy});
    defer enemies.deinit();

    if (enemies.views.len > 0) {
        std.log.info("enemies detected, adding combat stage...", .{});
        try registry.pipeline.addStageAfter("combat", "update", .{});
        try registry.pipeline.addSystem("combat", CombatSystem);
    }

    // add a stage before update
    try registry.pipeline.addStageBefore("pre-update", "update", .{});
    try registry.pipeline.addSystem("pre-update", PreUpdateSystem);

    // add a conditional stage
    try registry.pipeline.addStage("expensive_calculations", .{
        .run_condition = struct {
            var frame_counter: u32 = 0;
            fn condition(_: *ecs.Registry) bool {
                frame_counter += 1;
                return frame_counter % 10 == 0; // run every 10 frames
            }
        }.condition,
    });
    try registry.pipeline.addSystem("expensive_calculations", ExpensiveSystem);

    // remove a stage
    try registry.pipeline.removeStage("update");

    std.log.info("\npipeline after modifications:", .{});
    registry.pipeline.debugPrint();

    // process the modified pipeline multiple times to see conditional execution
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        std.log.info("\n--- Frame {} ---", .{i});
        registry.pipeline.execute(&registry);
    }
}

// Example Systems

const InitSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!InitSystem {
        _ = allocator;
        return InitSystem{};
    }
    pub fn deinit(_: *InitSystem) void {}
    pub fn process(_: *InitSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  InitSystem: initializing game", .{});
    }
};

const InputSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!InputSystem {
        _ = allocator;
        return InputSystem{};
    }
    pub fn deinit(_: *InputSystem) void {}
    pub fn process(_: *InputSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  InputSystem: processing input", .{});
    }
};

const MovementSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!MovementSystem {
        _ = allocator;
        return MovementSystem{};
    }
    pub fn deinit(_: *MovementSystem) void {}
    pub fn process(_: *MovementSystem, registry: *ecs.Registry) anyerror!void {
        std.log.info("  MovementSystem: updating positions", .{});

        var entities = try registry.queryComponents(.{ Position, Velocity });
        while (entities.next()) |entity| {
            const pos = entity.get(Position).?;
            const vel = entity.get(Velocity).?;
            pos.x += vel.x;
            pos.y += vel.y;
        }
    }
};

const CollisionSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!CollisionSystem {
        _ = allocator;
        return CollisionSystem{};
    }
    pub fn deinit(_: *CollisionSystem) void {}
    pub fn process(_: *CollisionSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  CollisionSystem: checking collisions", .{});
    }
};

const PhysicsSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!PhysicsSystem {
        _ = allocator;
        return PhysicsSystem{};
    }
    pub fn deinit(_: *PhysicsSystem) void {}
    pub fn process(_: *PhysicsSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  PhysicsSystem: simulating physics", .{});
        // Simulate a random failure
        const random = std.crypto.random.int(u8);
        if (random < 50) {
            return error.PhysicsSimulationFailed;
        }
    }
};

const RenderSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!RenderSystem {
        _ = allocator;
        return RenderSystem{};
    }
    pub fn deinit(_: *RenderSystem) void {}
    pub fn process(_: *RenderSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  RenderSystem: rendering frame", .{});
    }
};

const AIDecisionSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!AIDecisionSystem {
        _ = allocator;
        return AIDecisionSystem{};
    }
    pub fn deinit(_: *AIDecisionSystem) void {}
    pub fn process(_: *AIDecisionSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  AIDecisionSystem: making ai decisions", .{});
    }
};

const AIMovementSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!AIMovementSystem {
        _ = allocator;
        return AIMovementSystem{};
    }
    pub fn deinit(_: *AIMovementSystem) void {}
    pub fn process(_: *AIMovementSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  AIMovementSystem: moving ai entities", .{});
    }
};

const DebugSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!DebugSystem {
        _ = allocator;
        return DebugSystem{};
    }
    pub fn deinit(_: *DebugSystem) void {}
    pub fn process(_: *DebugSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  DebugSystem: drawing debug overlays", .{});
    }
};

const CombatSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!CombatSystem {
        _ = allocator;
        return CombatSystem{};
    }
    pub fn deinit(_: *CombatSystem) void {}
    pub fn process(_: *CombatSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  CombatSystem: resolving combat", .{});
    }
};

const BasicUpdateSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!BasicUpdateSystem {
        _ = allocator;
        return BasicUpdateSystem{};
    }
    pub fn deinit(_: *BasicUpdateSystem) void {}
    pub fn process(_: *BasicUpdateSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  BasicUpdateSystem: basic update", .{});
    }
};

const PreUpdateSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!PreUpdateSystem {
        _ = allocator;
        return PreUpdateSystem{};
    }
    pub fn deinit(_: *PreUpdateSystem) void {}
    pub fn process(_: *PreUpdateSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  PreUpdateSystem: pre-update checks", .{});
    }
};

const ExpensiveSystem = struct {
    pub fn init(allocator: std.mem.Allocator) anyerror!ExpensiveSystem {
        _ = allocator;
        return ExpensiveSystem{};
    }
    pub fn deinit(_: *ExpensiveSystem) void {}
    pub fn process(_: *ExpensiveSystem, _: *ecs.Registry) anyerror!void {
        std.log.info("  ExpensiveSystem: running expensive calculations", .{});
    }
};
