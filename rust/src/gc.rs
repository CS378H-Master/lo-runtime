//! GC operations (`runtime-abi.md` §3.4).
//!
//! `lo_gc_write_barrier` is **provided** as a bare store — the correct
//! non-generational barrier (Cheney's semispace, mark-compact) out of the box.
//! Teams choosing a generational collector replace its body with remembered-set
//! / card-table logic. `lo_gc_collect` is **stubbed**: implementing it (and the
//! GC-trigger-and-retry on `lo_alloc`'s OOM path) is the core of P3.

use crate::object::Object;

/// Pointer-store write barrier. Non-generational implementation: a bare store of
/// `value` into the pointer field at `obj + field_offset` (`runtime-abi.md` §3.4).
/// Codegen emits a call to this at *every* pointer store, which makes the choice
/// of collector a runtime-only decision.
///
/// # Safety
/// `obj` must point at a valid object with a pointer-typed field at
/// `field_offset`; `value` must be a valid object pointer or null.
#[no_mangle]
pub unsafe extern "C" fn lo_gc_write_barrier(
    obj: *mut Object,
    field_offset: u32,
    value: *mut Object,
) {
    let slot = (obj as *mut u8).add(field_offset as usize) as *mut *mut Object;
    *slot = value;
}

/// Force a collection (`runtime-abi.md` §3.4). Stubbed — the team implements the
/// collector chosen from the P3 menu (semispace / generational / mark-compact).
#[no_mangle]
pub extern "C" fn lo_gc_collect() {
    unimplemented!("lo_gc_collect: team implements per P3");
}
