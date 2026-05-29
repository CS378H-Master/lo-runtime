//! The runtime's special exported statics (`runtime-abi.md` §2.3): the built-in
//! class descriptors and the canonical empty-string singleton. Codegen
//! references these by symbol.

use crate::object::{ClassDescriptor, Object, StringObject};

/// Descriptor for the well-known `String` class.
#[no_mangle]
pub static LO_STRING_CLASS: ClassDescriptor = ClassDescriptor {
    name: c"String".as_ptr() as *const u8,
    name_len: 6,
    parent: core::ptr::null(),
    instance_size: core::mem::size_of::<StringObject>() as u32,
    pointer_offsets: core::ptr::null(),
    pointer_count: 0,
    vtable_size: 0,
    vtable: core::ptr::null(),
};

/// Descriptor for a boxed `int` (used only by LO-5 features that need uniform
/// pointer-typed values). Header plus a 4-byte boxed slot.
#[no_mangle]
pub static LO_INT_BOX_CLASS: ClassDescriptor = ClassDescriptor {
    name: c"int".as_ptr() as *const u8,
    name_len: 3,
    parent: core::ptr::null(),
    instance_size: (core::mem::size_of::<Object>() + 4) as u32,
    pointer_offsets: core::ptr::null(),
    pointer_count: 0,
    vtable_size: 0,
    vtable: core::ptr::null(),
};

/// Descriptor for a boxed `bool`. Header plus a 4-byte boxed slot (kept the same
/// width as the int box for a uniform boxed-primitive layout).
#[no_mangle]
pub static LO_BOOL_BOX_CLASS: ClassDescriptor = ClassDescriptor {
    name: c"bool".as_ptr() as *const u8,
    name_len: 4,
    parent: core::ptr::null(),
    instance_size: (core::mem::size_of::<Object>() + 4) as u32,
    pointer_offsets: core::ptr::null(),
    pointer_count: 0,
    vtable_size: 0,
    vtable: core::ptr::null(),
};

/// The canonical length-0 `StringObject`, allocated once by `lo_runtime_init`
/// and never collected. Codegen treats it as a read-only static pointer used to
/// initialize String-typed fields to their LO default (the empty string).
///
/// Held as a `static mut` raw pointer per the runbook's allowance for the few
/// genuinely-global mutable slots. It is written exactly once (during init) and
/// thereafter only read; the single-threaded runtime makes that sound. Access is
/// always by value (never by reference), which keeps it clear of the
/// `static_mut_refs` lint.
#[no_mangle]
pub static mut LO_EMPTY_STRING: *mut Object = core::ptr::null_mut();

/// Allocate the [`LO_EMPTY_STRING`] singleton. Called once from `lo_runtime_init`
/// after the heap is up.
pub(crate) fn init_empty_string() {
    // SAFETY: called once during init, after `heap_init`, on the single runtime
    // thread. `bump_alloc_string(0)` returns a valid zero-length StringObject
    // backed by LO_STRING_CLASS.
    unsafe {
        LO_EMPTY_STRING = crate::alloc::bump_alloc_string(0);
    }
}

/// Reset the singleton pointer (called from `lo_runtime_shutdown` for symmetry).
pub(crate) fn clear_empty_string() {
    // SAFETY: single-threaded; by-value write of a raw pointer.
    unsafe {
        LO_EMPTY_STRING = core::ptr::null_mut();
    }
}
