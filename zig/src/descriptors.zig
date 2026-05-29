//! Special exported statics (`runtime-abi.md` §2.3): the built-in class
//! descriptors and the canonical empty-string singleton, referenced by codegen.

const object = @import("object.zig");
const alloc = @import("alloc.zig");
const ClassDescriptor = object.ClassDescriptor;
const Object = object.Object;
const StringObject = object.StringObject;

/// Descriptor for the well-known `String` class.
pub export const LO_STRING_CLASS: ClassDescriptor = .{
    .name = "String",
    .name_len = 6,
    .parent = null,
    .instance_size = @sizeOf(StringObject),
    .pointer_offsets = null,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = null,
};

/// Descriptor for a boxed `int` (header + a 4-byte boxed slot).
pub export const LO_INT_BOX_CLASS: ClassDescriptor = .{
    .name = "int",
    .name_len = 3,
    .parent = null,
    .instance_size = @sizeOf(Object) + 4,
    .pointer_offsets = null,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = null,
};

/// Descriptor for a boxed `bool` (same width as the int box).
pub export const LO_BOOL_BOX_CLASS: ClassDescriptor = .{
    .name = "bool",
    .name_len = 4,
    .parent = null,
    .instance_size = @sizeOf(Object) + 4,
    .pointer_offsets = null,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = null,
};

/// The canonical length-0 `StringObject`, allocated once by `lo_runtime_init` and
/// never collected. Codegen treats it as a read-only static pointer used to
/// initialize String-typed fields to the empty-string default.
pub export var LO_EMPTY_STRING: ?*Object = null;

/// Allocate the `LO_EMPTY_STRING` singleton. Called once from `lo_runtime_init`
/// after the heap is up.
pub fn initEmptyString() void {
    LO_EMPTY_STRING = alloc.bumpAllocString(0);
}

/// Clear the singleton pointer (called from `lo_runtime_shutdown` for symmetry).
pub fn clearEmptyString() void {
    LO_EMPTY_STRING = null;
}
