#include "lo_runtime/descriptors.h"

extern "C" {

const ClassDescriptor LO_STRING_CLASS = {
    .name = "String",
    .name_len = 6,
    .parent = nullptr,
    .instance_size = static_cast<std::uint32_t>(sizeof(StringObject)),
    .pointer_offsets = nullptr,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = nullptr,
};

const ClassDescriptor LO_INT_BOX_CLASS = {
    .name = "int",
    .name_len = 3,
    .parent = nullptr,
    .instance_size = static_cast<std::uint32_t>(sizeof(Object) + 4),
    .pointer_offsets = nullptr,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = nullptr,
};

const ClassDescriptor LO_BOOL_BOX_CLASS = {
    .name = "bool",
    .name_len = 4,
    .parent = nullptr,
    .instance_size = static_cast<std::uint32_t>(sizeof(Object) + 4),
    .pointer_offsets = nullptr,
    .pointer_count = 0,
    .vtable_size = 0,
    .vtable = nullptr,
};

// Read-only `.rodata` static object (decision (A), ABI §2.3): the symbol denotes
// the length-0 String itself. A zero-length string has no inline tail, so the
// whole object is a fixed compile-time constant outside the managed heap.
const StringObject LO_EMPTY_STRING = {
    .header = {.class_descriptor = &LO_STRING_CLASS, .gc_bits = 0, .flags = 0},
    .length = 0,
};

} // extern "C"
