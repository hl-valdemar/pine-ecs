const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.addModule("pecs", .{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_examples_mod = b.createModule(.{
        .root_source_file = b.path("src/examples/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_examples_mod.addImport("pecs", lib_mod);

    const exe_examples = b.addExecutable(.{
        .name = "example",
        .root_module = exe_examples_mod,
    });

    b.installArtifact(exe_examples);

    const run_cmd_examples = b.addRunArtifact(exe_examples);
    run_cmd_examples.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd_examples.addArgs(args);
    }

    const run_step_examples = b.step("example", "Run the given example");
    run_step_examples.dependOn(&run_cmd_examples.step);
}
