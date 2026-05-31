//! LO runtime skeleton (Zig) — CS 378H Compilers, Fall 2026.
//!
//! Root module: re-exports the types for Zig consumers and force-references every
//! implementation module so their `export fn` C-ABI symbols are emitted into the
//! artifact. The module layout mirrors the Rust and C++ skeletons.

const std = @import("std");

pub const object = @import("object.zig");
pub const descriptors = @import("descriptors.zig");
pub const alloc = @import("alloc.zig");
pub const shadow_stack = @import("shadow_stack.zig");
pub const init = @import("init.zig");
pub const io = @import("io.zig");
pub const gc = @import("gc.zig");
pub const string_ops = @import("string_ops.zig");
pub const cast = @import("cast.zig");
pub const abort = @import("abort.zig");

// Re-exported types / helpers for Zig consumers.
pub const Object = object.Object;
pub const ClassDescriptor = object.ClassDescriptor;
pub const ShadowFrame = object.ShadowFrame;
pub const StringObject = object.StringObject;
pub const VTableEntry = object.VTableEntry;
pub const stringDataOffset = object.stringDataOffset;
pub const shadowFrameRootsOffset = object.shadowFrameRootsOffset;

// Force every module to be analyzed so its `export fn` / exported statics land in
// the static library and WASM module.
comptime {
    _ = descriptors;
    _ = alloc;
    _ = shadow_stack;
    _ = init;
    _ = io;
    _ = gc;
    _ = string_ops;
    _ = cast;
    _ = abort;
}

// ---------------------------------------------------------------------------
// Language-native ABI tests (run via `zig build test`). The Zig test runner is
// single-threaded, so bracketing each test with init/shutdown is enough; no
// extra serialization is needed. Stubbed entry points are not tested — calling
// one panics by design.
// ---------------------------------------------------------------------------

test {
    // Pull in object.zig's own layout test.
    std.testing.refAllDecls(object);
}

test "init and shutdown are clean" {
    init.lo_runtime_init();
    init.lo_runtime_shutdown();
    // A second cycle, plus a shutdown with no prior init, must not crash.
    init.lo_runtime_init();
    init.lo_runtime_shutdown();
    init.lo_runtime_shutdown();
}

test "alloc returns zeroed memory with a stamped header" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    const o = alloc.lo_alloc(&descriptors.LO_INT_BOX_CLASS);
    try std.testing.expectEqual(&descriptors.LO_INT_BOX_CLASS, o.class_descriptor.?);
    try std.testing.expectEqual(@as(u32, 0), o.gc_bits);
    try std.testing.expectEqual(@as(u32, 0), o.flags);

    // Every byte after the 16-byte header up to the rounded size (24) is zero.
    const base: [*]const u8 = @ptrCast(o);
    var off: usize = @sizeOf(Object);
    while (off < 24) : (off += 1) {
        try std.testing.expectEqual(@as(u8, 0), base[off]);
    }
}

test "distinct allocations do not alias and advance by the rounded size" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    const a = alloc.lo_alloc(&descriptors.LO_INT_BOX_CLASS);
    const b = alloc.lo_alloc(&descriptors.LO_INT_BOX_CLASS);
    try std.testing.expect(a != b);
    // instance_size 20 rounds to 24.
    try std.testing.expectEqual(@as(usize, 24), @intFromPtr(b) - @intFromPtr(a));
}

test "shadow stack push/pop maintains the list" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    try std.testing.expect(shadow_stack.currentFrame() == null);

    var f1: ShadowFrame = .{ .parent = null, .num_roots = 0, .roots = .{} };
    var f2: ShadowFrame = .{ .parent = null, .num_roots = 0, .roots = .{} };

    shadow_stack.lo_push_frame(&f1);
    try std.testing.expectEqual(&f1, shadow_stack.currentFrame().?);

    shadow_stack.lo_push_frame(&f2);
    try std.testing.expectEqual(&f2, shadow_stack.currentFrame().?);
    try std.testing.expectEqual(&f1, f2.parent.?);

    shadow_stack.lo_pop_frame();
    try std.testing.expectEqual(&f1, shadow_stack.currentFrame().?);

    shadow_stack.lo_pop_frame();
    try std.testing.expect(shadow_stack.currentFrame() == null);
}

test "LO_EMPTY_STRING is a .rodata static empty string" {
    // .rodata static *object* (decision (A), ABI §2.3): the symbol denotes the
    // object itself, valid independent of any init/shutdown cycle.
    const so: *const StringObject = &descriptors.LO_EMPTY_STRING;
    try std.testing.expectEqual(&descriptors.LO_STRING_CLASS, so.header.class_descriptor.?);
    try std.testing.expectEqual(@as(u32, 0), so.length);
}
