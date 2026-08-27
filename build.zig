const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.addModule("tinymidi", .{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
        .optimize = optimize
    });
    _ = root;
}
