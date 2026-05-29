//! GC operations (`runtime-abi.md` §3.4). `lo_gc_write_barrier` is **provided**
//! (the bare-store non-generational barrier); `lo_gc_collect` is **stubbed** —
//! implementing it (and the OOM-retry on `lo_alloc`) is the core of P3.

const object = @import("object.zig");
const Object = object.Object;

/// Pointer-store write barrier. Non-generational: a bare store of `value` into
/// the pointer field at `obj + field_offset`. Codegen emits a call at every
/// pointer store, making the collector a runtime-only choice. Teams using a
/// generational GC replace this body with remembered-set / card-table logic.
pub export fn lo_gc_write_barrier(obj: *Object, field_offset: u32, value: ?*Object) void {
    const slot: *?*Object = @ptrFromInt(@intFromPtr(obj) + field_offset);
    slot.* = value;
}

/// Force a collection. Stubbed — the team implements the chosen collector.
pub export fn lo_gc_collect() void {
    @panic("lo_gc_collect: team implements per P3");
}
