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
// Like heap_init but with an explicit total size — a test hook so the
// allocation-pressure test can force a small heap deterministically. Not part of
// the ABI.
void heap_init_with(std::size_t total);
void heap_shutdown();
// Internal variable-size string allocator (lo_alloc can't size a string itself).
Object *bump_alloc_string(std::uint32_t len);

// --- Collector seam (driven by gc.cpp) ------------------------------------
// Range-check from-space, locate the to-space, and commit the flip, without
// re-deriving heap geometry.
std::uint8_t *from_base();
std::uint8_t *from_limit();
std::uint8_t *to_space_base();
void flip(std::uint8_t *new_free);
// Live bytes occupied in the active semispace (test/diagnostic hook).
std::size_t heap_used();
} // namespace lo
