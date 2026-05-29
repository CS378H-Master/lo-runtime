//! ABI-visible type definitions (`runtime-abi.md` §2).
//!
//! Every type is an `extern struct`, which gives the platform C layout — that is
//! what keeps this skeleton byte-identical with the Rust and C++ ones (see the
//! Phase 4 cross-skeleton audit). Sizes in comments assume 64-bit pointers; the
//! code computes every offset with `@sizeOf` / `@offsetOf` so the 32-bit `wasm32`
//! build is correct too.

const std = @import("std");
const builtin = @import("builtin");

/// A vtable entry is a raw, pointer-sized function pointer. Modeled as an opaque
/// pointer to match the Rust skeleton's `*const c_void`. Built-in classes have
/// empty vtables.
pub const VTableEntry = ?*const anyopaque;

/// The fixed header every heap object begins with. 16 bytes on 64-bit
/// (`8 + 4 + 4`), 12 on WASM.
pub const Object = extern struct {
    class_descriptor: ?*const ClassDescriptor,
    gc_bits: u32,
    flags: u32,
};

/// Codegen-generated class metadata (`runtime-abi.md` §2.1). Field order is the
/// ABI's; `extern struct` inserts the same padding the C ABI would.
pub const ClassDescriptor = extern struct {
    /// UTF-8, null-terminated.
    name: [*:0]const u8,
    name_len: u32,
    parent: ?*const ClassDescriptor,
    /// Total bytes including the header.
    instance_size: u32,
    pointer_offsets: ?[*]const u32,
    pointer_count: u32,
    vtable_size: u32,
    vtable: ?[*]const VTableEntry,
};

/// A shadow-stack frame (`runtime-abi.md` §3.3). The ABI lays the roots out as an
/// **inline** `[*mut Object; N]` array after the header; this declares the fixed
/// header plus a zero-length `roots` marker, with the real tail starting at
/// `shadowFrameRootsOffset()`. (The Rust skeleton documents why this inline-array
/// layout is used rather than a pointer field — the ABI is authoritative.)
pub const ShadowFrame = extern struct {
    parent: ?*ShadowFrame,
    num_roots: u32,
    /// Marker for the inline `[num_roots]?*Object` tail (see
    /// `shadowFrameRootsOffset`).
    roots: [0]?*Object,
};

/// A heap string (`runtime-abi.md` §2.2): header, `u32` length, then `length`
/// UTF-8 bytes inline. `data` marks where the inline tail begins (see
/// `stringDataOffset`); the allocation reserves `stringDataOffset() + length`
/// bytes (rounded).
pub const StringObject = extern struct {
    header: Object,
    length: u32,
    /// Marker for the inline `[length]u8` tail.
    data: [0]u8,
};

/// Byte offset of the inline string data within a `StringObject`.
///
/// This is `@offsetOf(StringObject, "data")` — the flexible-array start (20 on
/// 64-bit, 16 on WASM), NOT `@sizeOf(StringObject)`, which would include trailing
/// padding (24) and point past the bytes. All three skeletons must use this.
pub inline fn stringDataOffset() usize {
    return @offsetOf(StringObject, "data");
}

/// Byte offset of the inline roots array within a `ShadowFrame`.
pub inline fn shadowFrameRootsOffset() usize {
    return @offsetOf(ShadowFrame, "roots");
}

// Compile-time layout locks (the comptime analog of the Rust `const _` asserts
// and a C++ `static_assert`). Gated per pointer width.
comptime {
    if (@sizeOf(usize) == 8) {
        std.debug.assert(@sizeOf(Object) == 16);
        std.debug.assert(@alignOf(Object) == 8);
        std.debug.assert(@offsetOf(StringObject, "data") == 20);
        std.debug.assert(@offsetOf(ShadowFrame, "roots") == 16);
    } else {
        std.debug.assert(@sizeOf(Object) == 12);
        std.debug.assert(@alignOf(Object) == 4);
        std.debug.assert(@offsetOf(StringObject, "data") == 16);
        std.debug.assert(@offsetOf(ShadowFrame, "roots") == 8);
    }
}

test "layout matches the ABI on 64-bit" {
    if (@sizeOf(usize) != 8) return error.SkipZigTest;
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Object));
    try std.testing.expectEqual(@as(usize, 20), stringDataOffset());
    try std.testing.expectEqual(@as(usize, 16), shadowFrameRootsOffset());
}
