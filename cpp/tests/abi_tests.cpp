// Language-native ABI smoke tests for the provided entry points, driven through
// the C-ABI surface (runtime-abi.md §4.4). Stubbed entry points are not tested —
// calling them throws by design. Catch2 runs sections sequentially in one
// process, so bracketing each with init/shutdown is enough.

#include "catch.hpp"

#include "lo_runtime/lo_runtime.h"

#include <cstdint>
#include <cstring>

TEST_CASE("layout matches the ABI") {
  // These mirror the static_asserts in object.h; redundant but explicit.
  REQUIRE(sizeof(Object) == (sizeof(void *) == 8 ? 16U : 12U));
  REQUIRE(lo::string_data_offset() == (sizeof(void *) == 8 ? 20U : 16U));
  REQUIRE(lo::shadow_frame_roots_offset() == (sizeof(void *) == 8 ? 16U : 8U));
}

TEST_CASE("init and shutdown are clean") {
  lo_runtime_init();
  lo_runtime_shutdown();
  lo_runtime_init();
  lo_runtime_shutdown();
  // Shutdown with no prior init must not crash.
  lo_runtime_shutdown();
}

TEST_CASE("alloc returns zeroed memory with a stamped header") {
  lo_runtime_init();

  Object *o = lo_alloc(&LO_INT_BOX_CLASS);
  REQUIRE(o != nullptr);
  REQUIRE(o->class_descriptor == &LO_INT_BOX_CLASS);
  REQUIRE(o->gc_bits == 0);
  REQUIRE(o->flags == 0);

  // Every byte after the 16-byte header up to the rounded size (24) is zero.
  const auto *base = reinterpret_cast<const std::uint8_t *>(o);
  for (std::size_t off = sizeof(Object); off < 24; ++off) {
    REQUIRE(base[off] == 0);
  }

  lo_runtime_shutdown();
}

TEST_CASE("distinct allocations do not alias and advance by the rounded size") {
  lo_runtime_init();

  Object *a = lo_alloc(&LO_INT_BOX_CLASS);
  Object *b = lo_alloc(&LO_INT_BOX_CLASS);
  REQUIRE(a != b);
  // instance_size 20 rounds to 24.
  const auto delta = reinterpret_cast<std::uintptr_t>(b) - reinterpret_cast<std::uintptr_t>(a);
  REQUIRE(delta == 24);

  lo_runtime_shutdown();
}

TEST_CASE("shadow stack push/pop maintains the list") {
  lo_runtime_init();

  REQUIRE(lo::current_frame() == nullptr);

  ShadowFrame f1{};
  ShadowFrame f2{};

  lo_push_frame(&f1);
  REQUIRE(lo::current_frame() == &f1);

  lo_push_frame(&f2);
  REQUIRE(lo::current_frame() == &f2);
  REQUIRE(f2.parent == &f1);

  lo_pop_frame();
  REQUIRE(lo::current_frame() == &f1);

  lo_pop_frame();
  REQUIRE(lo::current_frame() == nullptr);

  lo_runtime_shutdown();
}

TEST_CASE("LO_EMPTY_STRING is a .rodata static empty string") {
  // .rodata static *object* (decision (A), ABI §2.3): the symbol denotes the
  // object itself, valid independent of any init/shutdown cycle.
  REQUIRE(LO_EMPTY_STRING.header.class_descriptor == &LO_STRING_CLASS);
  REQUIRE(LO_EMPTY_STRING.length == 0);
}

// --- Cheney collector tests (runbook WS-2 §3, step A.4; mirrors rust/src/gc.rs).

namespace {

// A test class with one pointer field at offset 16 (a linked-list "Node"):
// instance_size 24, one pointer field.
const std::uint32_t kNodePtrOffsets[] = {16};
const ClassDescriptor kNodeClass = {
    .name = "Node",
    .name_len = 4,
    .parent = nullptr,
    .instance_size = 24,
    .pointer_offsets = kNodePtrOffsets,
    .pointer_count = 1,
    .vtable_size = 0,
    .vtable = nullptr,
};

// A shadow-stack frame with N inline roots, byte-compatible with the ABI's
// ShadowFrame { parent, num_roots, roots: Object*[N] }.
template <std::uint32_t N> struct TestFrame {
  ShadowFrame *parent = nullptr;
  std::uint32_t num_roots = N;
  Object *roots[N] = {};
  ShadowFrame *as_frame() { return reinterpret_cast<ShadowFrame *>(this); }
};

void set_field(Object *obj, std::size_t off, Object *val) {
  *reinterpret_cast<Object **>(reinterpret_cast<std::uint8_t *>(obj) + off) = val;
}
Object *get_field(Object *obj, std::size_t off) {
  return *reinterpret_cast<Object **>(reinterpret_cast<std::uint8_t *>(obj) + off);
}

} // namespace

// (i) A known live graph survives: reachable objects are preserved with updated
// addresses, and both the root slot and the interior pointer field are rewritten.
TEST_CASE("live graph preserved and pointers rewritten") {
  lo_runtime_init();
  TestFrame<1> frame;
  lo_push_frame(frame.as_frame());

  Object *a = lo_alloc(&kNodeClass);
  Object *b = lo_alloc(&kNodeClass);
  set_field(a, 16, b); // a.next = b
  frame.roots[0] = a;

  lo_gc_collect();

  Object *a2 = frame.roots[0];
  REQUIRE(a2 != a);
  REQUIRE(a2->class_descriptor == &kNodeClass);

  Object *b2 = get_field(a2, 16);
  REQUIRE(b2 != nullptr);
  REQUIRE(b2 != b);
  REQUIRE(b2->class_descriptor == &kNodeClass);
  REQUIRE(get_field(b2, 16) == nullptr); // b.next was null

  lo_pop_frame();
  lo_runtime_shutdown();
}

// (ii) An unreachable object is reclaimed: heap occupancy drops by its size.
TEST_CASE("unreachable object reclaimed") {
  lo_runtime_init();
  TestFrame<1> frame;
  lo_push_frame(frame.as_frame());

  Object *live = lo_alloc(&kNodeClass);
  frame.roots[0] = live;
  (void)lo_alloc(&kNodeClass); // not rooted -> unreachable

  REQUIRE(lo::heap_used() == 48); // two 24-byte nodes

  lo_gc_collect();

  REQUIRE(lo::heap_used() == 24); // only the live node survives
  Object *live2 = frame.roots[0];
  REQUIRE(live2->class_descriptor == &kNodeClass);

  lo_pop_frame();
  lo_runtime_shutdown();
}

// (iii) A variable-size String survives a collection intact (bytes round-trip).
TEST_CASE("string survives collection") {
  lo_runtime_init();
  TestFrame<1> frame;
  lo_push_frame(frame.as_frame());

  const char *bytes = "hello, Cheney";
  const std::uint32_t len = 13;
  Object *s = lo::bump_alloc_string(len);
  std::memcpy(reinterpret_cast<std::uint8_t *>(s) + lo::string_data_offset(), bytes, len);
  frame.roots[0] = s;

  lo_gc_collect();

  Object *s2 = frame.roots[0];
  REQUIRE(s2 != s);
  REQUIRE(s2->class_descriptor == &LO_STRING_CLASS);
  auto *so = reinterpret_cast<StringObject *>(s2);
  REQUIRE(so->length == len);
  const auto *data2 = reinterpret_cast<const char *>(s2) + lo::string_data_offset();
  REQUIRE(std::memcmp(data2, bytes, len) == 0);

  lo_pop_frame();
  lo_runtime_shutdown();
}

// (iv) LO_EMPTY_STRING is immortal: a moved object's field referencing it still
// points at the same .rodata address after collection (forward's range-check).
TEST_CASE("empty string not moved") {
  lo_runtime_init();
  TestFrame<1> frame;
  lo_push_frame(frame.as_frame());

  Object *holder = lo_alloc(&kNodeClass);
  auto *empty = reinterpret_cast<Object *>(const_cast<StringObject *>(&LO_EMPTY_STRING));
  set_field(holder, 16, empty); // holder.next = &LO_EMPTY_STRING
  frame.roots[0] = holder;

  lo_gc_collect();

  Object *holder2 = frame.roots[0];
  REQUIRE(holder2 != holder);
  REQUIRE(get_field(holder2, 16) == empty); // immortal: not relocated

  lo_pop_frame();
  lo_runtime_shutdown();
}

// (v) Allocation pressure past one semispace triggers GC through lo_alloc's OOM
// path and continues; only a genuine live-set overflow would abort.
TEST_CASE("allocation pressure triggers gc") {
  // Total 4 KiB -> 2 KiB per semispace (~85 nodes). Use the explicit-size init
  // hook (the env path is covered by the Rust reference). 600 dead allocations
  // force many collections; the single rooted node survives them all.
  lo::heap_init_with(4096);
  lo::reset_shadow_stack();
  TestFrame<1> frame;
  lo_push_frame(frame.as_frame());

  Object *live = lo_alloc(&kNodeClass);
  frame.roots[0] = live;

  for (int i = 0; i < 600; ++i) {
    (void)lo_alloc(&kNodeClass); // not rooted -> reclaimed each collection
  }

  // Reaching here means GC repeatedly reclaimed and allocation continued (a
  // missing trigger would abort with exit 137). The rooted node survived.
  Object *live2 = frame.roots[0];
  REQUIRE(live2->class_descriptor == &kNodeClass);

  lo_pop_frame();
  lo_runtime_shutdown();
}
