const std = @import("std");

pub fn build(b: *std.Build) !void {
    // these are boiler plate code until you know what you are doing
    // and you need to add additional options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // this is your own program
    const exe = b.addExecutable(.{
        // the name of your project
        .name = "zig-llm",
        // your main function
        .root_source_file = .{ .path = "main.zig" },
        // references the ones you declared above
        .target = target,
        .optimize = optimize,
    });

    // now install your own executable after it's built correctly
    b.installArtifact(exe);
}
