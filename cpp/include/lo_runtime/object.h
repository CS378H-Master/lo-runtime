// ABI-visible type definitions (runtime-abi.md §2).
//
// Every type is a standard-layout struct, giving the platform C layout — that is
// what keeps this skeleton byte-identical with the Rust and Zig ones (see the
// Phase 4 cross-skeleton audit). Sizes in comments assume 64-bit pointers; the
// offset helpers compute everything from offsetof/sizeof so the 32-bit wasm32
// build is correct too.
#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {

struct ClassDescriptor;

// A vtable entry is a raw, pointer-sized function pointer (modeled as an opaque
// pointer to match the Rust skeleton's *const c_void). Built-in classes have
// empty vtables.
using VTableEntry = const void *;

// The fixed header every heap object begins with. 16 bytes on 64-bit
// (8 + 4 + 4), 12 on WASM.
struct Object {
  const ClassDescriptor *class_descriptor;
  std::uint32_t gc_bits;
  std::uint32_t flags;
};

// Codegen-generated class metadata (runtime-abi.md §2.1). Field order is the
// ABI's; the compiler inserts the same padding the C ABI would. `name` is a
// pointer to null-terminated UTF-8 bytes (the C-string spelling of the ABI's
// *const u8).
struct ClassDescriptor {
  const char *name;
  std::uint32_t name_len;
  const ClassDescriptor *parent;
  std::uint32_t instance_size;
  const std::uint32_t *pointer_offsets;
  std::uint32_t pointer_count;
  std::uint32_t vtable_size;
  const VTableEntry *vtable;
};

// A shadow-stack frame (runtime-abi.md §3.3). The ABI lays the roots out as an
// inline `Object* roots[N]` array after the header; this declares only the fixed
// header, with the inline tail starting at lo::shadow_frame_roots_offset().
struct ShadowFrame {
  ShadowFrame *parent;
  std::uint32_t num_roots;
  // inline: Object* roots[num_roots] at lo::shadow_frame_roots_offset()
};

// A heap string (runtime-abi.md §2.2): header, u32 length, then `length` UTF-8
// bytes inline. The bytes start at lo::string_data_offset(); the allocation
// reserves string_data_offset() + length bytes (rounded).
struct StringObject {
  Object header;
  std::uint32_t length;
  // inline: std::uint8_t data[length] at lo::string_data_offset()
};

} // extern "C"

namespace lo {

// Byte offset of the inline string data within a StringObject.
//
// This is offsetof(length) + sizeof(length) — the flexible-array start (20 on
// 64-bit, 16 on WASM), NOT sizeof(StringObject), which includes trailing padding
// (24) and would point past the bytes. All three skeletons must use this offset.
inline std::size_t string_data_offset() {
  return offsetof(StringObject, length) + sizeof(std::uint32_t);
}

// Byte offset of the inline roots array within a ShadowFrame (the first
// Object*-aligned offset after num_roots).
inline std::size_t shadow_frame_roots_offset() {
  const std::size_t after = offsetof(ShadowFrame, num_roots) + sizeof(std::uint32_t);
  const std::size_t a = alignof(Object *);
  return (after + a - 1) & ~(a - 1);
}

} // namespace lo

// Compile-time layout locks (the analog of the Rust `const _` asserts and Zig
// comptime checks). Gated per pointer width.
#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
static_assert(sizeof(Object) == 16, "Object must be 16 bytes on 64-bit");
static_assert(alignof(Object) == 8);
static_assert(offsetof(StringObject, length) + sizeof(std::uint32_t) == 20,
              "string data must start at offset 20 on 64-bit");
static_assert(((offsetof(ShadowFrame, num_roots) + sizeof(std::uint32_t) + alignof(Object *) - 1) &
               ~(alignof(Object *) - 1)) == 16,
              "shadow frame roots must start at offset 16 on 64-bit");
#else
static_assert(sizeof(Object) == 12, "Object must be 12 bytes on 32-bit/WASM");
static_assert(alignof(Object) == 4);
static_assert(offsetof(StringObject, length) + sizeof(std::uint32_t) == 16,
              "string data must start at offset 16 on 32-bit");
static_assert(((offsetof(ShadowFrame, num_roots) + sizeof(std::uint32_t) + alignof(Object *) - 1) &
               ~(alignof(Object *) - 1)) == 8,
              "shadow frame roots must start at offset 8 on 32-bit");
#endif
