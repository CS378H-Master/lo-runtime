//! Runtime lifecycle (`runtime-abi.md` §3.6).

/// Initialize the runtime. Must be called before any other entry point: brings
/// up the heap, resets the shadow-stack head, and allocates the
/// `LO_EMPTY_STRING` singleton. Codegen emits a call at the top of `main`
/// (native) or in the WASM `start` function.
#[no_mangle]
pub extern "C" fn lo_runtime_init() {
    crate::alloc::heap_init();
    crate::shadow_stack::reset();
    crate::descriptors::init_empty_string();
}

/// Tear down the runtime. Optional on native (the OS reclaims memory); useful in
/// tests to validate no-leak invariants. Safe to call without a prior init and
/// safe to call more than once.
#[no_mangle]
pub extern "C" fn lo_runtime_shutdown() {
    crate::descriptors::clear_empty_string();
    crate::shadow_stack::reset();
    crate::alloc::heap_shutdown();
}
