// SPDX-License-Identifier: PMPL-1.0-or-later
// Build script for Stapeln Zig FFI library.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "stapeln_ffi",
        .root_module = shared_root_module,
    });
    lib.linkLibC();
    b.installArtifact(lib);

    const static_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stapeln_ffi",
        .root_module = static_root_module,
    });
    static_lib.linkLibC();
    b.installArtifact(static_lib);

    // --- Crypto library (real SHA-256 + Ed25519) ---

    const crypto_shared_module = b.createModule(.{
        .root_source_file = b.path("src/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crypto_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "stapeln_crypto",
        .root_module = crypto_shared_module,
    });
    b.installArtifact(crypto_lib);

    const crypto_static_module = b.createModule(.{
        .root_source_file = b.path("src/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crypto_static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "stapeln_crypto",
        .root_module = crypto_static_module,
    });
    b.installArtifact(crypto_static_lib);

    // --- Tests ---

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.linkLibC();

    const crypto_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/crypto.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const run_crypto_tests = b.addRunArtifact(crypto_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_crypto_tests.step);
}
