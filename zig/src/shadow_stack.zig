//! Shadow-stack root tracking (`runtime-abi.md` §3.3). Roots live in a linked
//! list of stack-allocated frames; the runtime keeps the `current_frame` head.

const object = @import("object.zig");
const ShadowFrame = object.ShadowFrame;

var current_frame: ?*ShadowFrame = null;

/// Register `frame` as the current head.
pub export fn lo_push_frame(frame: *ShadowFrame) void {
    frame.parent = current_frame;
    current_frame = frame;
}

/// Unregister the current head, restoring its parent. A pop with no matching push
/// is a codegen bug; the `unreachable` traps it in Debug / ReleaseSafe (the Zig
/// analog of the Rust skeleton's `debug_assert`).
pub export fn lo_pop_frame() void {
    const cur = current_frame orelse unreachable;
    current_frame = cur.parent;
}

/// Reset the head to null (called from init / shutdown).
pub fn reset() void {
    current_frame = null;
}

/// Read the current head. Not part of the ABI — a test/debug hook.
pub fn currentFrame() ?*ShadowFrame {
    return current_frame;
}
