const std = @import("std");

const Step = std.Build.Step;
const Import = std.Build.Module.Import;

// meta options
const zon = @import("build.zig.zon");
const Constraints = struct {
    max_value_len: usize = 256,
    max_file_open: usize = 4096,
};

// entry point
pub fn build(b: *std.Build) void {
    // build config
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // define sub-modules
    const internal = b.addModule("interal", .{
        .root_source_file = b.path("src/lib/internal.zig"),
        .target = target,
    });

    const aws = b.addModule("aws", .{
        .root_source_file = b.path("src/lib/aws.zig"),
        .target = target,
    });

    const io = b.addModule("io", .{
        .root_source_file = b.path("src/lib/io.zig"),
        .target = target,
    });

    // collect imports
    const imports = [_]Import{
        .{ .name = "aws", .module = aws },
        .{ .name = "internal", .module = internal },
        .{ .name = "io", .module = io },
    };

    for (imports) |import| {
        if (aws != import.module) aws.addImport(import.name, import.module);
        if (io != import.module) io.addImport(import.name, import.module);
    }

    // define executable
    const exe = b.addExecutable(.{
        .name = "picat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = imports[0..],
        }),
    });

    // define meta options for extra global values
    const meta_options = b.addOptions();
    meta_options.addOption([]const u8, "version", zon.version);
    meta_options.addOption(Constraints, "constraints", .{});

    // attach meta options
    exe.root_module.addOptions("meta", meta_options);

    internal.addOptions("meta", meta_options);
    aws.addOptions("meta", meta_options);
    io.addOptions("meta", meta_options);

    // set up exe
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // attach args to exe
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // exe tests
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    // sub modules tests
    var module_tests: [imports.len]*Step.Compile = undefined;

    for (imports, 0..) |import, index| {
        module_tests[index] = b.addTest(.{
            .root_module = import.module,
        });
    }

    var run_modules_tests: [imports.len]*Step.Run = undefined;
    for (module_tests, 0..) |tests, index| {
        run_modules_tests[index] = b.addRunArtifact(tests);
    }

    // set test run dependecies
    const test_step = b.step("test", "Run tests");

    for (run_modules_tests) |tests| {
        test_step.dependOn(&tests.step);
    }

    test_step.dependOn(&run_exe_tests.step);
}
