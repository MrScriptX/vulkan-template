const std = @import("std");
const shaders_build = @import("modules/shaders/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // c modules
    const c_translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize
    });
    const c_module = c_translate.createModule();

    // SDL 3
    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true
    });
    c_translate.addIncludePath(sdl.path("include")); 
    c_module.addLibraryPath(sdl.path("lib/x64"));
    c_module.linkSystemLibrary("SDL3", .{});

    // Vulkan SDK
    const vk_sdk_path = b.graph.environ_map.get("VULKAN_SDK") orelse @panic("VULKAN_SDK missing !");
    c_translate.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{ vk_sdk_path }) });
    c_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{ vk_sdk_path }) });
    
    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";
    c_module.linkSystemLibrary(vk_lib_name, .{});

    // Shaders
    const shaders_out_dir = b.getInstallPath(.bin, "shaders");
    const shaders_step = shaders_build.addCompileShadersStep(b, vk_sdk_path, shaders_out_dir);

    // VMA
    c_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{ vk_sdk_path }) });
    c_module.addCSourceFile(.{
        .file = b.path("src/vk_mem_alloc.cpp"),
        .language = .cpp,
        .flags = &.{
            "-Wno-nullability-completeness",
            "-std=c++17"
        }
    });

    const zephyr_dep = b.dependency("zephyr", .{
        .target = target,
        .optimize = optimize,
        .registry = @as(std.Build.LazyPath, .{ .cwd_relative = b.fmt("{s}/share/vulkan/registry/vk.xml", .{ vk_sdk_path }) }),
    });
    const vk_module = zephyr_dep.module("vk");

    // We will also create a module for our other entry point, 'main.zig'.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .imports = &.{
            .{
                .name = "c",
                .module = c_module
            },
            .{
                .name = "vk",
                .module = vk_module
            }
        }
    });

    // create exe
    const exe = b.addExecutable(.{
        .name = "vulkan-template",
        .root_module = mod
    });

    b.installArtifact(exe);
    b.getInstallStep().dependOn(shaders_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPathDir(sdl.path("lib/x64").getPath(b));
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(shaders_step);


    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const zephyr_tests = b.addTest(.{
        .root_module = zephyr_dep.module("zephyr"),
    });
    const run_zephyr_tests = b.addRunArtifact(zephyr_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_zephyr_tests.step);
}
