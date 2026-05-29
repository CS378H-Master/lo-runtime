//! String operations (`runtime-abi.md` §3.2). All **stubbed** — the team
//! implements these in P3. Each carries the exact C-ABI signature so the
//! skeleton links; calling one panics.
//!
//! Hints (from the ABI): `lo_string_repeat` aborts on negative count (exit 120);
//! `lo_string_compare` is lexicographic UTF-8 byte ordering; `lo_string_reverse`
//! reverses codepoints, not bytes. Build results with `alloc.bumpAllocString`.

const object = @import("object.zig");
const Object = object.Object;

/// Construct a string from `len` raw UTF-8 bytes (copied).
pub export fn lo_string_new(bytes: ?[*]const u8, len: u32) ?*Object {
    _ = bytes;
    _ = len;
    @panic("lo_string_new: team implements per P3");
}

/// Return a new string `a + b`.
pub export fn lo_string_concat(a: ?*Object, b: ?*Object) ?*Object {
    _ = a;
    _ = b;
    @panic("lo_string_concat: team implements per P3");
}

/// Return a new string: `s` repeated `n` times. Aborts (exit 120) on negative
/// `n`.
pub export fn lo_string_repeat(s: ?*Object, n: i32) ?*Object {
    _ = s;
    _ = n;
    @panic("lo_string_repeat: team implements per P3");
}

/// Compare two strings: negative / zero / positive by lexicographic UTF-8 byte
/// ordering.
pub export fn lo_string_compare(a: ?*Object, b: ?*Object) i32 {
    _ = a;
    _ = b;
    @panic("lo_string_compare: team implements per P3");
}

/// Return a new string with codepoints reversed.
pub export fn lo_string_reverse(s: ?*Object) ?*Object {
    _ = s;
    @panic("lo_string_reverse: team implements per P3");
}
