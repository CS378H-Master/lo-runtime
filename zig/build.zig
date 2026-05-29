//! Build for the LO runtime Zig skeleton.
//!
//!   zig build                                 # native static library
//!   zig build -Dtarget=wasm32-freestanding    # WASM module
//!   zig build test                            # unit tests + I/O round-trip
//!
//! Native builds a static library (`liblo_runtime.a`); a WASM target builds a
//! reactor-style module (`lo_runtime.wasm`) that exports the C-ABI surface.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root = b.path("src/lo_runtime.zig");

    if (target.result.cpu.arch.isWasm()) {
        // Reactor module: no entry point, exported functions kept via rdynamic.
        const wasm = b.addExecutable(.{
            .name = "lo_runtime",
            .root_source_file = root,
            .target = target,
            .optimize = optimize,
        });
        wasm.entry = .disabled;
        wasm.rdynamic = true;
        b.installArtifact(wasm);
    } else {
        const lib = b.addStaticLibrary(.{
            .name = "lo_runtime",
            .root_source_file = root,
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(lib);
    }

    // --- Tests ---------------------------------------------------------------
    const test_step = b.step("test", "Run unit tests and the I/O round-trip");

    const unit_tests = b.addTest(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // I/O round-trip + abort-code checks, native only (they drive real stdio).
    if (!target.result.cpu.arch.isWasm()) {
        const probe = b.addExecutable(.{
            .name = "lo_io_probe",
            .root_source_file = b.path("src/lo_io_probe.zig"),
            .target = target,
            .optimize = optimize,
        });

        const round_trip = b.addRunArtifact(probe);
        round_trip.setStdIn(.{ .bytes = "7\n" });
        round_trip.expectStdOutEqual("7\n42\n");
        round_trip.expectExitCode(0);
        test_step.dependOn(&round_trip.step);

        // read_int EOF -> exit 111.
        const eof_case = b.addRunArtifact(probe);
        eof_case.setStdIn(.{ .bytes = "" });
        eof_case.expectExitCode(111);
        test_step.dependOn(&eof_case.step);

        // read_int malformed token -> exit 110.
        const bad_case = b.addRunArtifact(probe);
        bad_case.setStdIn(.{ .bytes = "abc" });
        bad_case.expectExitCode(110);
        test_step.dependOn(&bad_case.step);
    }
}
