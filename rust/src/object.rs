//! ABI-visible type definitions.
//!
//! Every type here is laid out to match `runtime-abi.md` §2 byte-for-byte on the
//! target. All structs are `#[repr(C)]` so the layout is the platform C ABI;
//! that is what keeps the three skeletons (Rust / Zig / C++) in agreement — see
//! the cross-skeleton audit in WS-1 Phase 4.
//!
//! Sizes quoted in comments assume 64-bit pointers (`x86_64`). On
//! `wasm32-unknown-unknown` the pointer-sized fields shrink to 4 bytes and the
//! offsets adjust accordingly; the code never hard-codes a 64-bit offset — it
//! computes everything from `size_of` / `offset_of` so both targets are correct.

/// A vtable entry is a raw, pointer-sized function pointer. Methods are stored
/// in resolved order; the skeleton's built-in classes have empty vtables.
pub type VTableEntry = *const core::ffi::c_void;

/// The fixed header every heap object begins with (`runtime-abi.md` §2).
///
/// 16 bytes on 64-bit (`8 + 4 + 4`), 12 bytes on WASM. Fields declared after the
/// header live at offsets taken from the class descriptor.
#[repr(C)]
pub struct Object {
    /// Points at the object's `ClassDescriptor` (in read-only memory).
    pub class_descriptor: *const ClassDescriptor,
    /// Mark / age / forwarding flag — owned by the GC the team implements.
    pub gc_bits: u32,
    /// Reserved; LO-5 may extend.
    pub flags: u32,
}

/// Compile-time, codegen-generated metadata for a class (`runtime-abi.md` §2.1).
///
/// Field order is the ABI's; with `#[repr(C)]` the compiler inserts the same
/// padding the C ABI would, so a Zig `extern struct` and a C++ `struct` with the
/// same field order are byte-identical.
#[repr(C)]
pub struct ClassDescriptor {
    /// UTF-8, null-terminated.
    pub name: *const u8,
    pub name_len: u32,
    /// Null at the root of the hierarchy.
    pub parent: *const ClassDescriptor,
    /// Total bytes including the header.
    pub instance_size: u32,
    /// Offsets at which pointer fields live (for the GC to scan).
    pub pointer_offsets: *const u32,
    /// Length of `pointer_offsets`.
    pub pointer_count: u32,
    pub vtable_size: u32,
    /// Method pointers in resolved order.
    pub vtable: *const VTableEntry,
}

// SAFETY: `ClassDescriptor` carries raw pointers (so it is not `Sync` by
// default), but descriptors are immutable, read-only data generated once and
// never mutated, and the runtime is single-threaded (`runtime-abi.md` §1). It is
// therefore sound to place them in `static` items, which requires `Sync`.
unsafe impl Sync for ClassDescriptor {}

/// A shadow-stack frame (`runtime-abi.md` §3.3).
///
/// The ABI lays the frame out as `{ parent, num_roots, roots: [*mut Object; N] }`
/// with the roots array **inline** after the header — codegen stack-allocates the
/// whole thing and the (team-implemented) GC walks `roots[0..num_roots]`. Because
/// `N` varies per function, this type declares only the fixed header plus a
/// zero-length `roots` marker; the inline tail begins at
/// [`shadow_frame_roots_offset`]. This mirrors the [`StringObject`] flexible-tail
/// convention below.
///
/// (Note: this is the inline-array layout from ABI §3.3. The WS-1 runbook step
/// 1.3 sketched an alternative `roots: *mut *mut Object` representation, but that
/// would be a *pointer* field rather than an inline array and would not match the
/// frames codegen emits — the ABI is authoritative and wins, per the runbook's
/// own "when in doubt, the ABI wins". Flagged in the Phase 1 notes for SC.)
#[repr(C)]
pub struct ShadowFrame {
    pub parent: *mut ShadowFrame,
    pub num_roots: u32,
    /// Marker for the inline `[*mut Object; num_roots]` tail. Zero-size: it only
    /// exists so [`shadow_frame_roots_offset`] can name the tail's start.
    pub roots: [*mut Object; 0],
}

/// A heap string (`runtime-abi.md` §2.2): an `Object` header, a `u32` length, and
/// `length` UTF-8 bytes stored **inline** in the tail.
///
/// `data` is a zero-length array marking where the inline bytes begin; the real
/// allocation reserves `string_data_offset() + length` bytes (rounded for
/// alignment). Read/write the bytes at `base + string_data_offset()`.
#[repr(C)]
pub struct StringObject {
    pub header: Object,
    pub length: u32,
    /// Marker for the inline `[u8; length]` tail (see [`string_data_offset`]).
    pub data: [u8; 0],
}

/// Byte offset of the inline string data within a [`StringObject`].
///
/// This is `offset_of!(StringObject, data)` — the flexible-array-member start
/// (20 on 64-bit, 16 on WASM), **not** `size_of::<StringObject>()`, which would
/// include trailing padding (24 on 64-bit) and point past where the bytes
/// actually begin. All three skeletons must use this offset for the layouts to
/// agree.
#[inline]
pub const fn string_data_offset() -> usize {
    core::mem::offset_of!(StringObject, data)
}

/// Byte offset of the inline roots array within a [`ShadowFrame`].
#[inline]
pub const fn shadow_frame_roots_offset() -> usize {
    core::mem::offset_of!(ShadowFrame, roots)
}

// Compile-time layout locks (the Rust analog of C++'s `static_assert` /
// Zig's `comptime` checks). Gated per pointer width so both the 64-bit native
// build and the 32-bit `wasm32` build stay correct.
#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(core::mem::size_of::<Object>() == 16);
    assert!(core::mem::align_of::<Object>() == 8);
    assert!(string_data_offset() == 20);
    assert!(shadow_frame_roots_offset() == 16);
};
#[cfg(target_pointer_width = "32")]
const _: () = {
    assert!(core::mem::size_of::<Object>() == 12);
    assert!(core::mem::align_of::<Object>() == 4);
    assert!(string_data_offset() == 16);
    assert!(shadow_frame_roots_offset() == 8);
};

#[cfg(test)]
mod layout_tests {
    use super::*;

    // 64-bit layout assumptions from runtime-abi.md §2. These run on the host
    // (x86_64 / aarch64, both LP64) and lock the byte layout the cross-skeleton
    // audit (Phase 4) depends on.
    #[test]
    fn object_is_16_bytes() {
        assert_eq!(core::mem::size_of::<Object>(), 16);
        assert_eq!(core::mem::align_of::<Object>(), 8);
    }

    #[test]
    fn string_data_starts_at_20() {
        assert_eq!(string_data_offset(), 20);
    }

    #[test]
    fn shadow_frame_roots_start_at_16() {
        assert_eq!(shadow_frame_roots_offset(), 16);
    }
}
