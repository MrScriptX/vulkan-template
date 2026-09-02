const std = @import("std");
const builtin = @import("builtin");

pub fn addCompileShadersStep(b: *std.Build, vk_sdk_path: []const u8, out_dir: []const u8) *std.Build.Step {
    const step = b.step("shaders", "Compile slang shaders to SPIR-V");
    const io = b.graph.io;

    const slangc_path = if (builtin.os.tag == .windows)
        b.fmt("{s}/Bin/slangc.exe", .{vk_sdk_path})
    else
        b.fmt("{s}/bin/slangc", .{vk_sdk_path});

    std.Io.Dir.cwd().createDirPath(io, out_dir) catch |err| {
        std.debug.panic("failed to create shader output dir '{s}': {t}", .{ out_dir, err });
    };

    addShaderDirStep(b, io, step, slangc_path, "modules/shaders", out_dir);

    return step;
}

fn addShaderDirStep(b: *std.Build, io: std.Io, step: *std.Build.Step, slangc_path: []const u8, in_dir: []const u8, out_dir: []const u8) void {
    var dir = b.build_root.handle.openDir(io, in_dir, .{ .iterate = true }) catch |err|
        std.debug.panic("failed to open {s}: {t}", .{ in_dir, err });
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch @panic("failed to iterate shader dir")) |entry| {
        if (entry.kind == .directory) {
            const sub_in_dir = b.fmt("{s}/{s}", .{ in_dir, entry.name });
            const sub_out_dir = b.fmt("{s}/{s}", .{ out_dir, entry.name });

            std.Io.Dir.cwd().createDirPath(io, sub_out_dir) catch |err| {
                std.debug.panic("failed to create shader output dir '{s}': {t}", .{ sub_out_dir, err });
            };

            addShaderDirStep(b, io, step, slangc_path, sub_in_dir, sub_out_dir);
            continue;
        }

        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".slang")) continue;

        const stem = entry.name[0 .. entry.name.len - ".slang".len];
        const in_file = b.fmt("{s}/{s}", .{ in_dir, entry.name });
        const out_file = b.fmt("{s}/{s}.spirv", .{ out_dir, stem });

        const compile = b.addSystemCommand(&.{ slangc_path, in_file, "-target", "spirv", "-o", out_file });
        step.dependOn(&compile.step);
    }
}
