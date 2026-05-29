#include "lo_runtime/gc.h"

#include <stdexcept>

// lo_gc_write_barrier is provided: the bare-store non-generational barrier.
// Codegen emits a call at every pointer store, making the collector a
// runtime-only choice; generational-GC teams replace this body.
extern "C" void lo_gc_write_barrier(Object *obj, std::uint32_t field_offset, Object *value) {
  auto *slot = reinterpret_cast<Object **>(reinterpret_cast<std::uint8_t *>(obj) + field_offset);
  *slot = value;
}

// Stubbed: the team implements the chosen collector in P3.
extern "C" void lo_gc_collect() {
  throw std::runtime_error("lo_gc_collect: team implements per P3");
}
