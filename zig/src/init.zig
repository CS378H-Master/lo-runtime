//! Runtime lifecycle (`runtime-abi.md` §3.6).

const alloc = @import("alloc.zig");
const shadow_stack = @import("shadow_stack.zig");
const descriptors = @import("descriptors.zig");

/// Initialize the runtime: bring up the heap, reset the shadow-stack head, and
/// allocate `LO_EMPTY_STRING`. Must be called before any other entry point.
pub export fn lo_runtime_init() void {
    alloc.heapInit();
    shadow_stack.reset();
    descriptors.initEmptyString();
}

/// Tear down the runtime. Optional on native; useful in tests. Safe without a
/// prior init and safe to call more than once.
pub export fn lo_runtime_shutdown() void {
    descriptors.clearEmptyString();
    shadow_stack.reset();
    alloc.heapShutdown();
}
