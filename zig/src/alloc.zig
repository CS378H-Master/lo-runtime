//! Bump allocator backing `lo_alloc` (`runtime-abi.md` §3.1).
//!
//! The *provided* allocator: hands out 8-byte-aligned, zero-initialized slabs
//! from a single contiguous heap (allocated via `std.heap.page_allocator` at
//! init) until full, then aborts (exit 137). No GC yet — the OOM-retry path is
//! the team's P3 work. The heap and bump cursor are module-private globals,
//! touched only on the single runtime thread.

const std = @import("std");
const builtin = @import("builtin");

const object = @import("object.zig");
const descriptors = @import("descriptors.zig");
const abort = @import("abort.zig");
const Object = object.Object;
const ClassDescriptor = object.ClassDescriptor;
const StringObject = object.StringObject;

/// Default heap size (16 MiB), overridable via `LO_HEAP_SIZE` at init.
const DEFAULT_HEAP_SIZE: usize = 16 * 1024 * 1024;
const HEAP_ALIGN: usize = 16;
const is_wasm = builtin.cpu.arch.isWasm();

var heap_slice: ?[]u8 = null;
var bump_ptr: usize = 0;
var heap_end: usize = 0;

inline fn alignUp(n: usize, a: usize) usize {
    return (n + a - 1) & ~(a - 1);
}

fn readHeapSize() usize {
    if (comptime is_wasm) {
        return DEFAULT_HEAP_SIZE;
    } else {
        const v = std.process.getEnvVarOwned(std.heap.page_allocator, "LO_HEAP_SIZE") catch
            return DEFAULT_HEAP_SIZE;
        defer std.heap.page_allocator.free(v);
        const n = std.fmt.parseInt(usize, v, 10) catch return DEFAULT_HEAP_SIZE;
        return if (n >= HEAP_ALIGN) n else DEFAULT_HEAP_SIZE;
    }
}

/// Allocate the heap region. Called from `lo_runtime_init`.
pub fn heapInit() void {
    const size = readHeapSize();
    const slice = std.heap.page_allocator.alignedAlloc(u8, HEAP_ALIGN, size) catch
        abort.runtimeAbort("lo_alloc: out of memory", 137);
    @memset(slice, 0);
    heap_slice = slice;
    bump_ptr = @intFromPtr(slice.ptr);
    heap_end = bump_ptr + size;
}

/// Release the heap region. Called from `lo_runtime_shutdown`. Idempotent.
pub fn heapShutdown() void {
    if (heap_slice) |slice| {
        std.heap.page_allocator.free(slice);
        heap_slice = null;
    }
    bump_ptr = 0;
    heap_end = 0;
}

/// Carve `size` zero-initialized bytes and stamp the object header.
fn allocRaw(size: usize, class: *const ClassDescriptor) *Object {
    if (bump_ptr == 0 or size > heap_end - bump_ptr) {
        abort.runtimeAbort("lo_alloc: out of memory", 137);
    }
    const p = bump_ptr;
    bump_ptr += size;
    const bytes: [*]u8 = @ptrFromInt(p);
    @memset(bytes[0..size], 0);
    const o: *Object = @ptrCast(@alignCast(bytes));
    o.class_descriptor = class;
    o.gc_bits = 0;
    o.flags = 0;
    return o;
}

/// Allocate a zero-initialized object of `class.instance_size` bytes
/// (`runtime-abi.md` §3.1), header filled in. Aborts (exit 137) on OOM — the team
/// replaces that with a GC-trigger-and-retry in P3. Codegen finalizes String
/// fields to `LO_EMPTY_STRING` after this returns.
pub export fn lo_alloc(class: *const ClassDescriptor) *Object {
    const size = alignUp(class.instance_size, 8);
    return allocRaw(size, class);
}

/// Allocate a `StringObject` with room for `len` inline bytes, header stamped to
/// `LO_STRING_CLASS` and `length` set; the caller fills the (zeroed) data bytes.
/// Internal variable-size string allocator used by the provided `lo_read_string`
/// and the team-implemented `lo_string_*` ops; `lo_alloc` can't size a string
/// itself.
pub fn bumpAllocString(len: u32) *Object {
    const size = alignUp(object.stringDataOffset() + len, 8);
    const o = allocRaw(size, &descriptors.LO_STRING_CLASS);
    const so: *StringObject = @ptrCast(@alignCast(o));
    so.length = len;
    return o;
}
