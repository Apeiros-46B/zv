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

    // compile shaders
    const vert_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.3",
        "-o"
    });
    const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
    vert_cmd.addFileArg(b.path("shaders/shader.vert"));
    exe.root_module.addAnonymousImport("vertex_shader", .{
        .root_source_file = vert_spv
    });

    const frag_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.3",
        "-o"
    });
    const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
    frag_cmd.addFileArg(b.path("shaders/shader.frag"));
    exe.root_module.addAnonymousImport("fragment_shader", .{
        .root_source_file = frag_spv
    });

    // dependencies
    const vulkan = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe_mod.addImport("vulkan", vulkan);

    const sdk = sdl.init(b, .{});
    sdk.link(exe, .dynamic, sdl.Library.SDL2);
    exe_mod.addImport("sdl2", sdk.getWrapperModuleVulkan(vulkan));

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
}
