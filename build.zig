const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {

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

    // Build all files names in the src/examples folder
    const examples_path = "src/examples/";
    var dir = try std.fs.cwd().openDir(examples_path, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) {
            continue;
        }

        std.debug.print("[building...] {s}{s}\n", .{ examples_path, file.name });

        const allocator = std.heap.page_allocator;
        const full_path = std.fmt.allocPrint(allocator, "{s}{s}", .{ examples_path, file.name }) catch "format failed";
        defer allocator.free(full_path);

        const exe_mod = b.createModule(.{
            .root_source_file = b.path(full_path),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("pecs", lib_mod);

        var words = std.mem.splitAny(u8, file.name, ".");
        const example_name = words.next().?;

        // This creates another `std.Build.Step.Compile`, but this one builds an executable
        // rather than a static library.
        const exe = b.addExecutable(.{
            .name = example_name,
            .root_module = exe_mod,
        });

        // Add src/lib for libraries.
        // exe.addIncludePath(.{
        //     .src_path = .{ 
        //         .owner = b,
        //         .sub_path = "src/lib",
        //     },
        // });

        b.installArtifact(exe);

        // This *creates* a Run step in the build graph, to be executed when another
        // step is evaluated that depends on it. The next line below will establish
        // such a dependency.
        const run_cmd = b.addRunArtifact(exe);

        // By making the run step depend on the install step, it will be run from the
        // installation directory rather than directly from within the cache directory.
        // This is not necessary, however, if the application depends on other installed
        // files, this ensures they will be present and in the expected location.
        run_cmd.step.dependOn(b.getInstallStep());

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step_desc = std.fmt.allocPrint(allocator, "Run {s} example", .{ example_name }) catch "format failed";
        defer allocator.free(run_step_desc);

        // This creates a build step. It will be visible in the `zig build --help` menu,
        // and can be selected like this: `zig build run`
        // This will evaluate the `run` step rather than the default, which is "install".
        const run_step = b.step(example_name, run_step_desc);
        run_step.dependOn(&run_cmd.step);

        // const exe_unit_tests = b.addTest(.{
        //     .root_module = exe_mod,
        // });
        //
        // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        //
        // // Similar to creating the run step earlier, this exposes a `test` step to
        // // the `zig build --help` menu, providing a way for the user to request
        // // running the unit tests.
        // test_step.dependOn(&run_exe_unit_tests.step);
    }
}
