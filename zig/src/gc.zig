//! GC operations (`runtime-abi.md` §3.4) — the WS-2 reference **Cheney
//! two-space copying collector**, mirroring the Rust reference (`rust/src/gc.rs`).
//!
//! `lo_gc_write_barrier` is **provided** as a bare store (correct for any
//! non-generational collector incl. Cheney; runbook WS-2 §2.6) and left untouched.
//! `lo_gc_collect` performs a flip, a root scan, and a Cheney scan over the
//! to-space (runbook WS-2 §2.4); the allocator's OOM path drives it.
//!
//! ## Forwarding-flag bit (decision (C))
//!
//! Bit 0 of `gc_bits` (`GC_FORWARDED_BIT == 0b1`) is the **forwarding flag** —
//! the *same* bit as the Rust and C++ skeletons, preserving the cross-skeleton
//! byte-identical header invariant. Once an object is evacuated, the bit is set on
//! the from-space original and its `class_descriptor` slot holds the new to-space
//! address (the tombstone). Collector-private; no ABI pin.

const object = @import("object.zig");
const descriptors = @import("descriptors.zig");
const alloc = @import("alloc.zig");
const shadow_stack = @import("shadow_stack.zig");
const Object = object.Object;
const ClassDescriptor = object.ClassDescriptor;
const StringObject = object.StringObject;

/// Forwarding-flag bit in `gc_bits` (decision (C)). See module docs.
pub const GC_FORWARDED_BIT: u32 = 0b1;

/// Pointer-store write barrier. Non-generational: a bare store of `value` into the
/// pointer field at `obj + field_offset` (`runtime-abi.md` §3.4). Correct as-is
/// for Cheney; left untouched (runbook WS-2 §2.6).
pub export fn lo_gc_write_barrier(obj: *Object, field_offset: u32, value: ?*Object) void {
    const slot: *?*Object = @ptrFromInt(@intFromPtr(obj) + field_offset);
    slot.* = value;
}

/// Force a collection (`runtime-abi.md` §3.4): a Cheney flip-and-scan cycle.
/// Reachable objects are copied to the inactive semispace with their interior
/// pointers and the shadow-stack roots rewritten to the new addresses;
/// unreachable objects are reclaimed when the old space is abandoned.
pub export fn lo_gc_collect() void {
    collect();
}

inline fn align8(n: usize) usize {
    return (n + 7) & ~@as(usize, 7);
}

/// True byte size of a heap object — the count `forward` copies and the stride
/// `scan` advances by (runbook WS-2 §2.2). Strings are variable-size: their inline
/// tail starts at `@offsetOf(StringObject, "data")` (= 20 on 64-bit), **not**
/// `@sizeOf` — the offset-of-not-size-of rule (`runtime-abi.md` §2.2).
fn objectSize(p: *Object) usize {
    const class = p.class_descriptor.?;
    if (class == &descriptors.LO_STRING_CLASS) {
        const so: *const StringObject = @ptrCast(@alignCast(p));
        return align8(object.stringDataOffset() + so.length);
    }
    return align8(class.instance_size);
}

/// Evacuate `p` from the from-space `[from_base, from_limit)` into the to-space,
/// bumping `free` (runbook WS-2 §2.3). Returns `p`'s new address. Null and
/// non-from-space (immortal / `.rodata`, e.g. `LO_EMPTY_STRING`) pointers are
/// returned untouched — the range-check is what keeps immortal objects safe with
/// no special case. An already-evacuated object (forwarding bit set) returns the
/// new address stored in its clobbered `class_descriptor` slot.
///
/// Order matters: the size is read and the bytes copied **before** the original's
/// `class_descriptor` is overwritten; the copy carries the intact descriptor into
/// to-space with the forwarding flag still clear, and only the original becomes a
/// tombstone.
fn forward(p: ?*Object, from_base: usize, from_limit: usize, free: *usize) ?*Object {
    const obj = p orelse return null;
    const addr = @intFromPtr(obj);
    if (addr < from_base or addr >= from_limit) {
        return p; // immortal / non-heap: leave untouched
    }
    if (obj.gc_bits & GC_FORWARDED_BIT != 0) {
        // Already moved; the class_descriptor slot holds the new address.
        return @ptrFromInt(@intFromPtr(obj.class_descriptor.?));
    }
    const n = objectSize(obj);
    const dst = free.*;
    const src: [*]const u8 = @ptrCast(obj);
    const dest: [*]u8 = @ptrFromInt(dst);
    @memcpy(dest[0..n], src[0..n]);
    // Install the tombstone in the *original* — after the copy.
    obj.class_descriptor = @ptrFromInt(dst);
    obj.gc_bits |= GC_FORWARDED_BIT;
    free.* = dst + n;
    return @ptrFromInt(dst);
}

/// One Cheney collection cycle (runbook WS-2 §2.4).
fn collect() void {
    const from_base = alloc.fromBase();
    const from_limit = alloc.fromLimit();
    var free = alloc.toSpaceBase();
    var scan = free;

    // 1–2. Scan the root set: every slot of every shadow-stack frame, walking
    // `current_frame` -> `parent` to null (ABI §3.3).
    var frame = shadow_stack.currentFrame();
    while (frame) |f| {
        const roots_base = @intFromPtr(f) + object.shadowFrameRootsOffset();
        var i: u32 = 0;
        while (i < f.num_roots) : (i += 1) {
            const slot: *?*Object = @ptrFromInt(roots_base + i * @sizeOf(?*Object));
            slot.* = forward(slot.*, from_base, from_limit, &free);
        }
        frame = f.parent;
    }

    // 3. Cheney loop: scan copied objects in to-space, forwarding each pointer
    // field, until `scan` catches `free`. Strings have `pointer_count == 0`, so
    // they only advance `scan` — but `objectSize` still uses the variable-size
    // branch to advance correctly.
    while (scan < free) {
        const obj: *Object = @ptrFromInt(scan);
        const class = obj.class_descriptor.?;
        if (class.pointer_offsets) |offsets| {
            var i: u32 = 0;
            while (i < class.pointer_count) : (i += 1) {
                const slot: *?*Object = @ptrFromInt(scan + offsets[i]);
                slot.* = forward(slot.*, from_base, from_limit, &free);
            }
        }
        scan += objectSize(obj);
    }

    // 4. Commit: swap the semispace roles; the old from-space is now free.
    alloc.flip(free);
}

// --- Tests (runbook WS-2 §3, step A.4; mirrors rust/src/gc.rs) ---------------
// The Zig test runner is single-process and runs these sequentially, so each
// brackets the runtime with init/shutdown. `LO_HEAP_SIZE` is set inside the test
// for the allocation-pressure case.

const std = @import("std");
const init = @import("init.zig");

// A test class with one pointer field at offset 16 (a linked-list "Node"):
// instance_size 24, one pointer field.
const NODE_PTR_OFFSETS = [_]u32{16};
const NODE_CLASS: ClassDescriptor = .{
    .name = "Node",
    .name_len = 4,
    .parent = null,
    .instance_size = 24,
    .pointer_offsets = &NODE_PTR_OFFSETS,
    .pointer_count = 1,
    .vtable_size = 0,
    .vtable = null,
};

/// A shadow-stack frame with `n` inline roots, byte-compatible with the ABI's
/// `ShadowFrame { parent, num_roots, roots: [n]?*Object }`.
fn TestFrame(comptime n: u32) type {
    return extern struct {
        parent: ?*object.ShadowFrame = null,
        num_roots: u32 = n,
        roots: [n]?*Object = [_]?*Object{null} ** n,

        fn asFrame(self: *@This()) *object.ShadowFrame {
            return @ptrCast(@alignCast(self));
        }
    };
}

fn setField(obj: *Object, off: usize, val: ?*Object) void {
    const slot: *?*Object = @ptrFromInt(@intFromPtr(obj) + off);
    slot.* = val;
}
fn getField(obj: *Object, off: usize) ?*Object {
    const slot: *?*Object = @ptrFromInt(@intFromPtr(obj) + off);
    return slot.*;
}

// (i) A known live graph survives: reachable objects are preserved with updated
// addresses, and both the root slot and the interior pointer field are rewritten.
test "live graph preserved and pointers rewritten" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    var frame = TestFrame(1){};
    shadow_stack.lo_push_frame(frame.asFrame());
    defer shadow_stack.lo_pop_frame();

    const a = alloc.lo_alloc(&NODE_CLASS);
    const b = alloc.lo_alloc(&NODE_CLASS);
    setField(a, 16, b); // a.next = b
    frame.roots[0] = a;

    lo_gc_collect();

    const a2 = frame.roots[0].?;
    try std.testing.expect(a2 != a);
    try std.testing.expectEqual(&NODE_CLASS, a2.class_descriptor.?);

    const b2 = getField(a2, 16).?;
    try std.testing.expect(b2 != b);
    try std.testing.expectEqual(&NODE_CLASS, b2.class_descriptor.?);
    try std.testing.expect(getField(b2, 16) == null); // b.next was null
}

// (ii) An unreachable object is reclaimed: heap occupancy drops by its size.
test "unreachable object reclaimed" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    var frame = TestFrame(1){};
    shadow_stack.lo_push_frame(frame.asFrame());
    defer shadow_stack.lo_pop_frame();

    const live = alloc.lo_alloc(&NODE_CLASS);
    frame.roots[0] = live;
    _ = alloc.lo_alloc(&NODE_CLASS); // not rooted -> unreachable

    try std.testing.expectEqual(@as(usize, 48), alloc.heapUsed());

    lo_gc_collect();

    try std.testing.expectEqual(@as(usize, 24), alloc.heapUsed());
    const live2 = frame.roots[0].?;
    try std.testing.expectEqual(&NODE_CLASS, live2.class_descriptor.?);
}

// (iii) A variable-size String survives a collection intact (bytes round-trip).
test "string survives collection" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    var frame = TestFrame(1){};
    shadow_stack.lo_push_frame(frame.asFrame());
    defer shadow_stack.lo_pop_frame();

    const bytes = "hello, Cheney";
    const s = alloc.bumpAllocString(bytes.len);
    const data: [*]u8 = @ptrFromInt(@intFromPtr(s) + object.stringDataOffset());
    @memcpy(data[0..bytes.len], bytes);
    frame.roots[0] = s;

    lo_gc_collect();

    const s2 = frame.roots[0].?;
    try std.testing.expect(s2 != s);
    try std.testing.expectEqual(&descriptors.LO_STRING_CLASS, s2.class_descriptor.?);
    const so: *const StringObject = @ptrCast(@alignCast(s2));
    try std.testing.expectEqual(@as(u32, bytes.len), so.length);
    const data2: [*]const u8 = @ptrFromInt(@intFromPtr(s2) + object.stringDataOffset());
    try std.testing.expectEqualStrings(bytes, data2[0..bytes.len]);
}

// (iv) LO_EMPTY_STRING is immortal: a moved object's field referencing it still
// points at the same `.rodata` address after collection (forward's range-check).
test "empty string not moved" {
    init.lo_runtime_init();
    defer init.lo_runtime_shutdown();

    var frame = TestFrame(1){};
    shadow_stack.lo_push_frame(frame.asFrame());
    defer shadow_stack.lo_pop_frame();

    const holder = alloc.lo_alloc(&NODE_CLASS);
    const empty: *Object = @ptrCast(@constCast(&descriptors.LO_EMPTY_STRING));
    setField(holder, 16, empty); // holder.next = &LO_EMPTY_STRING
    frame.roots[0] = holder;

    lo_gc_collect();

    const holder2 = frame.roots[0].?;
    try std.testing.expect(holder2 != holder);
    try std.testing.expectEqual(empty, getField(holder2, 16).?);
}

// (v) Allocation pressure past one semispace triggers GC through lo_alloc's OOM
// path and continues; only a genuine live-set overflow would abort.
test "allocation pressure triggers gc" {
    // Total 4 KiB -> 2 KiB per semispace (~85 nodes). Use the explicit-size init
    // hook (the env path is covered by the Rust reference). 600 dead allocations
    // force many collections; the single rooted node survives them all.
    alloc.heapInitWith(4096);
    shadow_stack.reset();
    defer {
        shadow_stack.reset();
        alloc.heapShutdown();
    }

    var frame = TestFrame(1){};
    shadow_stack.lo_push_frame(frame.asFrame());
    defer shadow_stack.lo_pop_frame();

    const live = alloc.lo_alloc(&NODE_CLASS);
    frame.roots[0] = live;

    var i: usize = 0;
    while (i < 600) : (i += 1) {
        // Not rooted: each becomes garbage the next collection reclaims.
        _ = alloc.lo_alloc(&NODE_CLASS);
    }

    // Reaching here means GC repeatedly reclaimed and allocation continued (a
    // missing trigger would abort with exit 137). The rooted node survived.
    const live2 = frame.roots[0].?;
    try std.testing.expectEqual(&NODE_CLASS, live2.class_descriptor.?);
}
