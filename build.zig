const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "MazeGen",
        .root_module = b.createModule(.{
            .optimize = .ReleaseSafe,
            .target = b.standardTargetOptions(.{}),
            .root_source_file = b.path("main.zig"),
            .link_libc = true,
        }),
        .use_llvm = false,
        .use_lld = false,
    });

    exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
    exe.root_module.linkSystemLibrary("SDL3", .{ .needed = true });

    b.installArtifact(exe);
}
