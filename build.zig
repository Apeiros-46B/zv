const std = @import("std");
const sdl = @import("sdl");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // declare modules
    const exe_mod = b.createModule(.{

        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zvoxels",
        .root_module = exe_mod,
    });

    // dependencies
    const zgl = b.dependency("zgl", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zgl", zgl.module("zgl"));

    const sdl_sdk = sdl.init(b, .{});
    sdl_sdk.link(exe, .dynamic, sdl.Library.SDL2);
    exe_mod.addImport("sdl2", sdl_sdk.getWrapperModule());

    // install step
    b.installArtifact(exe);

    // add a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // add a testing step
    const unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const exe_check = b.addExecutable(.{
        .name = "zvoxels",
        .root_module = exe_mod,
    });
    const check = b.step("check", "Check if the app compiles");
    check.dependOn(&exe_check.step);
}
