#include "lo_runtime/descriptors.h"

#include "lo_runtime/alloc.h"

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

Object *LO_EMPTY_STRING = nullptr;

} // extern "C"

namespace lo {

void init_empty_string() { LO_EMPTY_STRING = bump_alloc_string(0); }

void clear_empty_string() { LO_EMPTY_STRING = nullptr; }

} // namespace lo
