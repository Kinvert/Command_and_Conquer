const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const generated_rules = b.createModule(.{
        .root_source_file = b.path("generated/td_micro_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generated_map = b.createModule(.{
        .root_source_file = b.path("generated/scenario1_map.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rules_manifest = b.createModule(.{
        .root_source_file = b.path("rules/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const td_micro = b.addModule("td_micro", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generated_rules", .module = generated_rules },
            .{ .name = "generated_map", .module = generated_map },
            .{ .name = "rules_manifest", .module = rules_manifest },
        },
    });

    const c_api_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "generated_rules", .module = generated_rules },
            .{ .name = "generated_map", .module = generated_map },
            .{ .name = "rules_manifest", .module = rules_manifest },
        },
    });
    const library = b.addLibrary(.{
        .name = "td_micro",
        .linkage = .static,
        .root_module = c_api_module,
    });
    const install_library = b.addInstallArtifact(library, .{});
    const install_header = b.addInstallHeaderFile(b.path("include/td_micro_api.h"), "td_micro_api.h");
    b.getInstallStep().dependOn(&install_library.step);
    b.getInstallStep().dependOn(&install_header.step);
    const library_step = b.step("lib", "Build the TD Micro C ABI static library");
    library_step.dependOn(&install_library.step);
    library_step.dependOn(&install_header.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "td_micro", .module = td_micro }},
        }),
    });
    const test_step = b.step("test", "Run TD Micro unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const generator = b.addExecutable(.{
        .name = "generate-rules",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/generate_rules.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    const generate_step = b.step("generate-rules", "Regenerate Zig and C rules from the JSON manifest");
    generate_step.dependOn(&b.addRunArtifact(generator).step);

    const map_generator = b.addExecutable(.{
        .name = "generate-map",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/generate_map.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    const generate_map_step = b.step("generate-map", "Regenerate the Zig map from the Vanilla oracle fixture");
    generate_map_step.dependOn(&b.addRunArtifact(map_generator).step);
}
