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

    // create executable modules for all examples
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try addExamples(
        allocator,
        b,
        EXAMPLES_DIR,
        &.{
            .{
                .name = "pine-ecs",
                .module = lib_mod,
            },
        },
        .{
            .target = target,
            .optimize = optimize,
        },
    );
}

const EXAMPLES_DIR = "examples/";

/// Create executable modules for each example in `EXAMPLES_DIR`.
///
/// Note: assumes path with trailing '/' (slash).
fn addExamples(
    allocator: std.mem.Allocator,
    b: *std.Build,
    path: []const u8,
    imports: []const struct {
        name: []const u8,
        module: *std.Build.Module,
    },
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    },
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    var it = dir.iterate();
    while (try it.next()) |file| {
        switch (file.kind) {
            .file => {
                if (std.mem.eql(u8, file.name, "main.zig")) {
                    // create executable module
                    const full_path = b.pathJoin(&.{ path, file.name });
                    const exe_mod = b.createModule(.{
                        .root_source_file = b.path(full_path),
                        .target = options.target,
                        .optimize = options.optimize,
                    });

                    for (imports) |import| {
                        exe_mod.addImport(import.name, import.module);
                    }

                    // extract name
                    var dir_names = std.mem.splitScalar(u8, path, '/');
                    var example_name: []const u8 = undefined;
                    while (dir_names.next()) |name| {
                        example_name = name;
                    } // get the last name in the path (parent of `main.zig`)

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

                    const run_desc = try std.fmt.allocPrint(allocator, "Run {s} example", .{example_name});
                    defer allocator.free(run_desc);

                    const run_step = b.step(example_name, run_desc);
                    run_step.dependOn(&run_cmd.step);
                }
            },
            .directory => {
                try addExamples(allocator, b, b.pathJoin(&.{ path, file.name }), imports, options);
            },
            else => {},
        }
    }
}
