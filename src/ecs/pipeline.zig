// src/ecs/pipeline.zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Registry = @import("registry.zig").Registry;
const TypeErasedSystem = @import("system.zig").TypeErasedSystem;

pub const PipelineError = error{
    StageNotFound,
    SystemAlreadyRegistered,
    CircularDependency, // TODO: implement circular dependency checks...
    DuplicateStage,
    NoSubstagePipeline,
};

/// A pipeline manages the execution order of systems through named stages.
pub const Pipeline = struct {
    allocator: Allocator,
    stages: std.ArrayList(Stage),
    stage_map: std.StringHashMap(usize), // name -> index for O(1) lookup

    pub fn init(allocator: Allocator) Pipeline {
        return .{
            .allocator = allocator,
            .stages = std.ArrayList(Stage).init(allocator),
            .stage_map = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Pipeline) void {
        for (self.stages.items) |*stage| {
            stage.deinit();
        }
        self.stages.deinit();
        self.stage_map.deinit();
    }

    /// Add a new stage to the pipeline.
    pub fn addStage(self: *Pipeline, name: []const u8, config: StageConfig) !void {
        if (self.stage_map.contains(name)) {
            return PipelineError.DuplicateStage;
        }

        const stage_index = self.stages.items.len;

        var stage = Stage.init(self.allocator, name, config);
        errdefer stage.deinit();

        try self.stages.append(stage);
        errdefer _ = self.stages.pop();

        try self.stage_map.put(name, stage_index);
    }

    /// Add a stage that runs after another stage.
    pub fn addStageAfter(self: *Pipeline, name: []const u8, after: []const u8, config: StageConfig) !void {
        const after_index = self.stage_map.get(after) orelse return PipelineError.StageNotFound;

        if (self.stage_map.contains(name)) {
            return PipelineError.DuplicateStage;
        }

        // insert new stage after the specified one
        var stage = Stage.init(self.allocator, name, config);
        errdefer stage.deinit();

        try self.stages.insert(after_index + 1, stage);

        // update indices in stage_map
        try self.rebuildStageMap();
    }

    /// Add a stage that runs before another stage.
    pub fn addStageBefore(self: *Pipeline, name: []const u8, before: []const u8, config: StageConfig) !void {
        const before_index = self.stage_map.get(before) orelse return PipelineError.StageNotFound;

        if (self.stage_map.contains(name)) {
            return PipelineError.DuplicateStage;
        }

        var stage = Stage.init(self.allocator, name, config);
        errdefer stage.deinit();

        try self.stages.insert(before_index, stage);

        // update indices in stage_map
        try self.rebuildStageMap();
    }

    /// Remove a stage from the pipeline.
    pub fn removeStage(self: *Pipeline, name: []const u8) !void {
        const index = self.stage_map.get(name) orelse return PipelineError.StageNotFound;

        var stage = self.stages.orderedRemove(index);
        stage.deinit();

        try self.rebuildStageMap();
    }

    /// Add a system to a specific stage.
    pub fn addSystem(self: *Pipeline, stage_name: []const u8, comptime System: type) !void {
        const stage_index = self.stage_map.get(stage_name) orelse return PipelineError.StageNotFound;
        var stage = &self.stages.items[stage_index];

        try stage.addSystem(System);
    }

    /// Add multiple systems to a stage at once.
    pub fn addSystems(self: *Pipeline, stage_name: []const u8, comptime systems: anytype) !void {
        const stage_index = self.stage_map.get(stage_name) orelse return PipelineError.StageNotFound;
        var stage = &self.stages.items[stage_index];

        inline for (systems) |System| {
            try stage.addSystem(System);
        }
    }

    /// Execute the entire pipeline.
    pub fn execute(self: *Pipeline, registry: *Registry) void {
        for (self.stages.items) |*stage| {
            stage.execute(registry);
        }
    }

    /// Execute only specific stages.
    pub fn executeStages(self: *Pipeline, registry: *Registry, stage_names: []const []const u8) !void {
        var stage_indexes = std.ArrayList(usize).init(self.allocator);
        defer stage_indexes.deinit();

        // collect stage indexes
        for (stage_names) |stage_name| {
            const stage_index = self.stage_map.get(stage_name) orelse {
                log.warn("trying to execute non-registered stage '{s}': {}", .{ stage_name, PipelineError.StageNotFound });
                continue;
            };

            try stage_indexes.append(stage_index);
        }

        // sort stages so that execution order is preserved
        std.sort.heap(usize, stage_indexes.items, {}, std.sort.asc(usize));

        // execute in order
        for (stage_indexes.items) |idx| {
            self.stages.items[idx].execute(registry);
        }
    }

    /// Execute stages matching a predicate.
    pub fn executeStagesIf(self: *Pipeline, registry: *Registry, predicate: *const fn (stage_name: []const u8) bool) void {
        for (self.stages.items) |*stage| {
            if (predicate(stage.name)) {
                stage.execute(registry);
            }
        }
    }

    /// Get a stage by name for direct manipulation.
    pub fn getStage(self: *Pipeline, name: []const u8) ?*Stage {
        const index = self.stage_map.get(name) orelse return null;
        return &self.stages.items[index];
    }

    /// Check if a stage exists.
    pub fn hasStage(self: *Pipeline, name: []const u8) bool {
        return self.stage_map.contains(name);
    }

    pub const BooleanOperation = enum {
        @"and",
        @"or",
    };

    /// Check if a bunch of stages exists.
    pub fn hasStages(self: *Pipeline, stage_names: []const []const u8, operation: BooleanOperation) bool {
        switch (operation) {
            .@"and" => {
                var result = true;
                for (stage_names) |name| {
                    result = result and self.hasStage(name);
                }
                return result;
            },
            .@"or" => {
                var result = false;
                for (stage_names) |name| {
                    result = result or self.hasStage(name);
                }
                return result;
            },
        }
    }

    /// Get all stage names in execution order.
    ///
    /// Note: caller owns returned object.
    pub fn getStageNames(self: *Pipeline, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.stages.items.len);
        errdefer allocator.free(names);

        for (self.stages.items, 0..) |stage, i| {
            names[i] = stage.name;
        }

        return names;
    }

    pub fn getSystemNames(self: *Pipeline, allocator: Allocator, stage_name: []const u8) ![][]const u8 {
        if (self.getStage(stage_name)) |stage| {
            return try stage.getSystemNames(allocator);
        } else return PipelineError.StageNotFound;
    }

    /// Check whether a stage is void of systems.
    ///
    /// Note: returns `true` also in the case that an unregistered stage is checked.
    pub fn stageEmpty(self: *Pipeline, stage_name: []const u8) bool {
        if (self.getStage(stage_name)) |stage| {
            return stage.systems.items.len == 0;
        } else return true;
    }

    pub fn stagesEmpty(self: *Pipeline, stage_names: []const []const u8, operation: BooleanOperation) bool {
        switch (operation) {
            .@"and" => {
                var result = true;
                for (stage_names) |name| {
                    result = result and self.stageEmpty(name);
                }
                return result;
            },
            .@"or" => {
                var result = false;
                for (stage_names) |name| {
                    result = result or self.stageEmpty(name);
                }
                return result;
            },
        }
    }

    /// Print pipeline structure for debugging.
    pub fn debugPrint(self: *Pipeline) void {
        log.debug("pipeline structure:", .{});
        for (self.stages.items, 0..) |stage, i| {
            log.debug("  stage {d}: {s} ({s}, {} systems)", .{
                i,
                stage.name,
                if (stage.config.parallel) "parallel" else "sequential",
                stage.systems.items.len,
            });
            for (stage.systems.items, 0..) |_, j| {
                log.debug("    system {d}", .{j});
            }
        }
    }

    /// Must be called whenever `stages` is modified.
    /// Otherwise, stage map has invalid state.
    fn rebuildStageMap(self: *Pipeline) !void {
        self.stage_map.clearRetainingCapacity();
        for (self.stages.items, 0..) |stage, index| {
            try self.stage_map.put(stage.name, index);
        }
    }
};

pub const StageConfig = struct {
    /// TODO: If true, systems in this stage can run in parallel (future feature).
    parallel: bool = false,

    /// If true, continue executing even if a system fails.
    continue_on_error: bool = false,

    /// Optional condition to check before running this stage.
    run_condition: ?*const fn (*Registry) bool = null,

    /// If true, stage is enabled by default.
    enabled: bool = true,
};

pub const Stage = struct {
    allocator: Allocator,
    name: []const u8,
    config: StageConfig,
    systems: std.ArrayList(TypeErasedSystem),
    substages: ?Pipeline,

    pub fn init(allocator: Allocator, name: []const u8, config: StageConfig) Stage {
        return Stage{
            .allocator = allocator,
            .name = name,
            .config = config,
            .systems = std.ArrayList(TypeErasedSystem).init(allocator),
            .substages = null,
        };
    }

    pub fn deinit(self: *Stage) void {
        // deinit systems
        for (self.systems.items) |system| {
            system.deinit();
        }
        self.systems.deinit();

        // deinit substages
        if (self.substages) |*pipeline| {
            pipeline.deinit();
        }
    }

    pub fn addSystem(self: *Stage, comptime System: type) !void {
        const erased_system = try TypeErasedSystem.init(self.allocator, System);
        errdefer erased_system.deinit();

        try self.systems.append(erased_system);
    }

    pub fn removeSystem(self: *Stage, index: usize) void {
        if (index >= self.systems.items.len) return;

        var system = self.systems.orderedRemove(index);
        system.deinit();
    }

    pub fn getSystemNames(self: *Stage, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.systems.items.len);
        errdefer allocator.free(names);

        for (self.systems.items, 0..) |system, i| {
            names[i] = system.metadata.name;
        }

        return names;
    }

    pub fn clearSystems(self: *Stage) void {
        for (self.systems.items) |system| {
            system.deinit();
        }
        self.systems.clearRetainingCapacity();
    }

    pub fn addSubstage(self: *Stage, name: []const u8, config: StageConfig) !void {
        if (self.substages) |*pipeline| {
            try pipeline.addStage(name, config);
        } else {
            self.substages = Pipeline.init(self.allocator);
            try self.substages.?.addStage(name, config);
        }
    }

    pub fn addSubstageAfter(self: *Stage, name: []const u8, after: []const u8, config: StageConfig) !void {
        if (self.substages) |*pipeline| {
            try pipeline.addStageAfter(name, after, config);
        } else {
            self.substages = Pipeline.init(self.allocator);
            try self.substages.?.addStageAfter(name, after, config);
        }
    }

    pub fn addSubstageBefore(self: *Stage, name: []const u8, before: []const u8, config: StageConfig) !void {
        if (self.substages) |*pipeline| {
            try pipeline.addStageBefore(name, before, config);
        } else {
            self.substages = Pipeline.init(self.allocator);
            try self.substages.?.addStageBefore(name, before, config);
        }
    }

    pub fn removeSubstage(self: *Stage, name: []const u8) !void {
        if (self.substages) |pipeline| {
            try pipeline.removeStage(name);
        } else {
            return PipelineError.NoSubstagePipeline;
        }
    }

    pub fn setEnabled(self: *Stage, enabled: bool) void {
        self.config.enabled = enabled;
    }

    pub fn execute(self: *Stage, registry: *Registry) void {
        // check if stage is enabled
        if (!self.config.enabled) {
            log.debug("skipping disabled stage '{s}'", .{self.name});
            return;
        }

        // check run condition if present
        if (self.config.run_condition) |condition| {
            if (!condition(registry)) {
                log.debug("skipping stage '{s}' due to run condition", .{self.name});
                return;
            }
        }

        // log.debug("executing stage: {s}", .{self.name});

        // first execute the substages
        if (self.substages) |*pipeline| {
            pipeline.execute(registry);
        }

        // then execute the immediate systems
        if (self.config.parallel) {
            // TODO: implement parallel execution when needed.
            // for now, fall back to sequential.
            self.executeSequential(registry);
        } else {
            self.executeSequential(registry);
        }
    }

    fn executeSequential(self: *Stage, registry: *Registry) void {
        for (self.systems.items) |system| {
            system.process(registry) catch |err| {
                log.err("system failed in stage '{s}': {}", .{ self.name, err });
                if (!self.config.continue_on_error) {
                    return;
                }
            };
        }
    }
};
