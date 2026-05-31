//! Special exported statics (`runtime-abi.md` §2.3): the built-in class
//! descriptors and the canonical empty-string singleton, referenced by codegen.

const object = @import("object.zig");
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

/// The canonical length-0 `StringObject` (`runtime-abi.md` §2.3, runbook WS-2
/// §2.5). Defined as a **read-only static object** (`export const` → `.rodata`),
/// not heap-allocated: the symbol denotes the object itself, its address is a
/// link-time constant outside the managed heap, and codegen references it
/// directly (no load). This replaces the WS-1 init-time allocation — the
/// collector never moves or reclaims it (it is never *in* from-space), so no
/// special case is needed in `forward`.
pub export const LO_EMPTY_STRING: StringObject = .{
    .header = .{
        .class_descriptor = &LO_STRING_CLASS,
        .gc_bits = 0,
        .flags = 0,
    },
    .length = 0,
    .data = .{},
};
