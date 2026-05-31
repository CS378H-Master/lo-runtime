#include "lo_runtime/gc.h"

#include "lo_runtime/alloc.h"
#include "lo_runtime/descriptors.h"
#include "lo_runtime/shadow_stack.h"

#include <cstring>

// GC operations (runtime-abi.md §3.4) — the WS-2 reference Cheney two-space
// copying collector, mirroring the Rust reference (rust/src/gc.rs).
//
// lo_gc_write_barrier is provided as a bare store (correct for any
// non-generational collector incl. Cheney; runbook WS-2 §2.6) and left untouched.
// lo_gc_collect performs a flip, a root scan, and a Cheney scan over the to-space
// (runbook WS-2 §2.4); the allocator's OOM path drives it.
//
// Forwarding-flag bit (decision (C)): bit 0 of gc_bits — the SAME bit as the Rust
// and Zig skeletons, preserving the cross-skeleton byte-identical header
// invariant. Once an object is evacuated, the bit is set on the from-space
// original and its class_descriptor slot holds the new to-space address (the
// tombstone). Collector-private; no ABI pin.

namespace {

constexpr std::uint32_t kGcForwardedBit = 0x1;

std::size_t align8(std::size_t n) { return (n + 7) & ~std::size_t{7}; }

// True byte size of a heap object — the count forward copies and the stride scan
// advances by (runbook WS-2 §2.2). Strings are variable-size: their inline tail
// starts at string_data_offset() (= 20 on 64-bit), NOT sizeof — the
// offset-of-not-size-of rule (runtime-abi.md §2.2).
std::size_t object_size(Object *p) {
  const ClassDescriptor *cls = p->class_descriptor;
  if (cls == &LO_STRING_CLASS) {
    auto *so = reinterpret_cast<StringObject *>(p);
    return align8(lo::string_data_offset() + so->length);
  }
  return align8(cls->instance_size);
}

// Evacuate `p` from the from-space [from_base, from_limit) into the to-space,
// bumping *free (runbook WS-2 §2.3). Returns p's new address. Null and
// non-from-space (immortal / .rodata, e.g. LO_EMPTY_STRING) pointers are returned
// untouched — the range-check is what keeps immortal objects safe with no special
// case. An already-evacuated object (forwarding bit set) returns the new address
// stored in its clobbered class_descriptor slot.
//
// Order matters: the size is read and the bytes copied BEFORE the original's
// class_descriptor is overwritten; the copy carries the intact descriptor into
// to-space with the forwarding flag still clear, and only the original becomes a
// tombstone.
Object *forward(Object *p, std::uint8_t *from_base, std::uint8_t *from_limit, std::uint8_t **free) {
  if (p == nullptr) {
    return nullptr;
  }
  auto *addr = reinterpret_cast<std::uint8_t *>(p);
  if (addr < from_base || addr >= from_limit) {
    return p; // immortal / non-heap: leave untouched
  }
  if ((p->gc_bits & kGcForwardedBit) != 0) {
    // Already moved; the class_descriptor slot holds the new address.
    return reinterpret_cast<Object *>(const_cast<ClassDescriptor *>(p->class_descriptor));
  }
  const std::size_t n = object_size(p);
  std::uint8_t *dst = *free;
  std::memcpy(dst, addr, n);
  // Install the tombstone in the *original* — after the copy.
  p->class_descriptor = reinterpret_cast<const ClassDescriptor *>(dst);
  p->gc_bits |= kGcForwardedBit;
  *free = dst + n;
  return reinterpret_cast<Object *>(dst);
}

} // namespace

// Provided: the bare-store non-generational barrier. Codegen emits a call at
// every pointer store, making the collector a runtime-only choice; generational
// teams replace this body. Correct as-is for Cheney; left untouched.
extern "C" void lo_gc_write_barrier(Object *obj, std::uint32_t field_offset, Object *value) {
  auto *slot = reinterpret_cast<Object **>(reinterpret_cast<std::uint8_t *>(obj) + field_offset);
  *slot = value;
}

// One Cheney collection cycle (runbook WS-2 §2.4): flip, scan the shadow-stack
// root set, Cheney-scan the to-space, commit.
extern "C" void lo_gc_collect() {
  std::uint8_t *from_base = lo::from_base();
  std::uint8_t *from_limit = lo::from_limit();
  std::uint8_t *free = lo::to_space_base();
  std::uint8_t *scan = free;

  // 1–2. Scan the root set: every slot of every shadow-stack frame, walking
  // current_frame -> parent to null (ABI §3.3).
  for (ShadowFrame *f = lo::current_frame(); f != nullptr; f = f->parent) {
    auto *roots_base = reinterpret_cast<std::uint8_t *>(f) + lo::shadow_frame_roots_offset();
    for (std::uint32_t i = 0; i < f->num_roots; ++i) {
      auto *slot = reinterpret_cast<Object **>(roots_base + i * sizeof(Object *));
      *slot = forward(*slot, from_base, from_limit, &free);
    }
  }

  // 3. Cheney loop: scan copied objects in to-space, forwarding each pointer
  // field, until scan catches free. Strings have pointer_count == 0, so they only
  // advance scan — but object_size still uses the variable-size branch.
  while (scan < free) {
    auto *obj = reinterpret_cast<Object *>(scan);
    const ClassDescriptor *cls = obj->class_descriptor;
    for (std::uint32_t i = 0; i < cls->pointer_count; ++i) {
      const std::uint32_t off = cls->pointer_offsets[i];
      auto *slot = reinterpret_cast<Object **>(scan + off);
      *slot = forward(*slot, from_base, from_limit, &free);
    }
    scan += object_size(obj);
  }

  // 4. Commit: swap the semispace roles; the old from-space is now free.
  lo::flip(free);
}
