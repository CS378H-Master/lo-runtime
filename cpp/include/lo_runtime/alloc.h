// Bump allocator backing lo_alloc (runtime-abi.md §3.1).
#pragma once

#include "lo_runtime/object.h"

extern "C" {
// Allocate a zero-initialized object of class->instance_size bytes, header filled
// in. Aborts (exit 137) on OOM.
Object *lo_alloc(const ClassDescriptor *cls);
}

namespace lo {
void heap_init();
void heap_shutdown();
// Internal variable-size string allocator (lo_alloc can't size a string itself).
Object *bump_alloc_string(std::uint32_t len);
} // namespace lo
