//! Runtime lifecycle (`runtime-abi.md` §3.6).

const alloc = @import("alloc.zig");
const shadow_stack = @import("shadow_stack.zig");

/// Initialize the runtime: bring up the heap and reset the shadow-stack head.
/// Must be called before any other entry point. `LO_EMPTY_STRING` is a `.rodata`
/// static and needs no initialization (`runtime-abi.md` §2.3, §3.6; runbook WS-2
/// §2.5) — the WS-1 init-time allocation is gone.
pub export fn lo_runtime_init() void {
    alloc.heapInit();
    shadow_stack.reset();
}

/// Tear down the runtime. Optional on native; useful in tests. Safe without a
/// prior init and safe to call more than once.
pub export fn lo_runtime_shutdown() void {
    shadow_stack.reset();
    alloc.heapShutdown();
}
