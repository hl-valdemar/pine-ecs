const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create the library module
    const lib_mod = b.addModule("pine-ecs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create static library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pine-ecs",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    // tests steps
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // doc steps
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    // create executable modules for each example in src/examples/
    const examples_path = "src/examples/";
    var dir = try std.fs.cwd().openDir(examples_path, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) continue;

        // create executable module
        const full_path = b.pathJoin(&.{ examples_path, file.name });
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(full_path),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("pine-ecs", lib_mod);

        // extract name
        var words = std.mem.splitAny(u8, file.name, ".");
        const example_name = words.next().?;

        // create executable
        const exe = b.addExecutable(.{
            .name = example_name,
            .root_module = exe_mod,
        });

        b.installArtifact(exe);

        // run step
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const allocator = std.heap.page_allocator;
        const run_step_desc = std.fmt.allocPrint(allocator, "Run {s} example", .{example_name}) catch "format failed";
        defer allocator.free(run_step_desc);

        const run_step = b.step(example_name, run_step_desc);
        run_step.dependOn(&run_cmd.step);

        // test steps
        const exe_unit_tests = b.addTest(.{
            .root_module = exe_mod,
        });

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
