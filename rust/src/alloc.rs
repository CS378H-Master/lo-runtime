//! Bump allocator backing `lo_alloc` (`runtime-abi.md` §3.1).
//!
//! This is the *provided* allocator: it hands out 8-byte-aligned, zero-initialized
//! slabs from a single contiguous heap until the heap is full, then aborts. There
//! is no GC yet — reclaiming the OOM path is the team's P3 work. Because memory is
//! only ever handed out once (never reused), bump-allocated regions are already
//! zero from the initial `alloc_zeroed`; `lo_alloc` re-zeroes anyway so the
//! invariant still holds once a real collector starts recycling memory.
//!
//! The heap and bump pointer are `static mut` raw scalars (the runbook explicitly
//! sanctions `static mut` for the bump pointer). Every access is by value or
//! through a raw pointer — never `&`/`&mut` of the statics — which keeps this
//! module clear of the `static_mut_refs` lint while staying single-`unsafe`-block
//! tight. Invariant: only `heap_init`/`heap_shutdown`/`lo_alloc`/`alloc_raw`
//! touch these, and only on the single runtime thread.

use core::alloc::Layout;
use core::ptr;

use crate::descriptors::LO_STRING_CLASS;
use crate::object::{string_data_offset, ClassDescriptor, Object, StringObject};

/// Default heap size (16 MiB), overridable via `LO_HEAP_SIZE` at init.
const DEFAULT_HEAP_SIZE: usize = 16 * 1024 * 1024;
/// All allocations are aligned to this; covers `Object`'s 8-byte pointer field
/// with headroom.
const HEAP_ALIGN: usize = 16;

static mut HEAP_BASE: *mut u8 = ptr::null_mut();
static mut HEAP_END: *mut u8 = ptr::null_mut();
static mut BUMP_PTR: *mut u8 = ptr::null_mut();
static mut HEAP_LAYOUT: Option<Layout> = None;

#[inline]
const fn align_up(n: usize, align: usize) -> usize {
    (n + align - 1) & !(align - 1)
}

/// Allocate the heap region. Called from `lo_runtime_init`.
pub(crate) fn heap_init() {
    let size = std::env::var("LO_HEAP_SIZE")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .filter(|&n| n >= HEAP_ALIGN)
        .unwrap_or(DEFAULT_HEAP_SIZE);
    let layout = Layout::from_size_align(size, HEAP_ALIGN).expect("valid heap layout");
    // SAFETY: `layout` has non-zero size; `alloc_zeroed` returns either a valid
    // zeroed region of `size` bytes or null (handled). Writes below are by-value
    // stores to the bump-allocator statics on the single runtime thread.
    unsafe {
        let base = std::alloc::alloc_zeroed(layout);
        if base.is_null() {
            std::alloc::handle_alloc_error(layout);
        }
        HEAP_BASE = base;
        HEAP_END = base.add(size);
        BUMP_PTR = base;
        HEAP_LAYOUT = Some(layout);
    }
}

/// Release the heap region. Called from `lo_runtime_shutdown`.
pub(crate) fn heap_shutdown() {
    // SAFETY: by-value reads of the statics; `dealloc` is paired with the
    // `alloc_zeroed` in `heap_init` using the stored layout. Idempotent: a null
    // base (never inited, or already shut down) is a no-op.
    unsafe {
        let base = HEAP_BASE;
        let layout = HEAP_LAYOUT;
        if !base.is_null() {
            if let Some(layout) = layout {
                std::alloc::dealloc(base, layout);
            }
            HEAP_BASE = ptr::null_mut();
            HEAP_END = ptr::null_mut();
            BUMP_PTR = ptr::null_mut();
            HEAP_LAYOUT = None;
        }
    }
}

/// Carve `size` zero-initialized bytes from the heap and stamp the object header.
///
/// # Safety
/// `class` must point at a valid, live `ClassDescriptor`. `size` must be at least
/// `size_of::<Object>()` so the header fits.
unsafe fn alloc_raw(size: usize, class: *const ClassDescriptor) -> *mut Object {
    let bump = BUMP_PTR;
    let end = HEAP_END;
    // Address arithmetic for the bounds check avoids forming an out-of-bounds
    // pointer when the request would overflow the heap.
    let new_addr = (bump as usize).wrapping_add(size);
    if bump.is_null() || new_addr > end as usize {
        crate::abort::runtime_abort("lo_alloc: out of memory", 137);
    }
    BUMP_PTR = bump.add(size);

    ptr::write_bytes(bump, 0, size);
    let obj = bump as *mut Object;
    (*obj).class_descriptor = class;
    (*obj).gc_bits = 0;
    (*obj).flags = 0;
    obj
}

/// Allocate a zero-initialized object of `class.instance_size` bytes
/// (`runtime-abi.md` §3.1). Fills in the header. Aborts (exit 137) on OOM — the
/// team replaces that path with a GC-trigger-and-retry in P3.
///
/// Codegen is responsible for finalizing String-typed fields to `LO_EMPTY_STRING`
/// immediately after this returns (see `runtime-abi.md` §3.1); `lo_alloc` is
/// deliberately type-agnostic.
///
/// # Safety
/// `class` must point at a valid `ClassDescriptor` whose `instance_size` is at
/// least `size_of::<Object>()`.
#[no_mangle]
pub unsafe extern "C" fn lo_alloc(class: *const ClassDescriptor) -> *mut Object {
    let size = align_up((*class).instance_size as usize, 8);
    alloc_raw(size, class)
}

/// Allocate a `StringObject` with room for `len` inline bytes, header stamped to
/// `LO_STRING_CLASS` and `length` set. The caller fills the `len` data bytes
/// (already zeroed) at `base + string_data_offset()`.
///
/// This is the internal variable-size string allocator used by the provided
/// `lo_read_string` and by `LO_EMPTY_STRING` init. `lo_alloc` cannot size a
/// string itself (it only knows the class's fixed `instance_size`); the
/// team-implemented `lo_string_*` ops use this same pattern.
///
/// # Safety
/// Must be called after `heap_init`. Returns a valid `*mut Object`/`*mut
/// StringObject` or aborts on OOM.
pub(crate) unsafe fn bump_alloc_string(len: u32) -> *mut Object {
    let size = align_up(string_data_offset() + len as usize, 8);
    let obj = alloc_raw(size, &LO_STRING_CLASS);
    let so = obj as *mut StringObject;
    (*so).length = len;
    obj
}
