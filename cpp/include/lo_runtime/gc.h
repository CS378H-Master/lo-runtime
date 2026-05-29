// GC operations (runtime-abi.md §3.4).
#pragma once

#include "lo_runtime/object.h"

extern "C" {
// Provided: non-generational bare-store write barrier.
void lo_gc_write_barrier(Object *obj, std::uint32_t field_offset, Object *value);
// Stubbed: the team implements the chosen collector in P3.
void lo_gc_collect();
}
