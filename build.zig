const std = @import("std");

pub fn build(b: *std.Build) void {
    const root = b.option([]const u8, "root", "override root dir") orelse "src";
    //build settings
    const bin = b.addExecutable(.{
        .name = "wreck",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ root, "main.zig" })),
            .target = b.graph.host,
        }),
    });

    b.installArtifact(bin);

    //for 'zig build run'
    const run_bin = b.addRunArtifact(bin);
    if (b.args) |args| {
        run_bin.addArgs(args);
    }
    const run_step = b.step("run", "run the program");
    run_step.dependOn(&run_bin.step);
}
