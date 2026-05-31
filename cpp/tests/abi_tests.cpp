// Language-native ABI smoke tests for the provided entry points, driven through
// the C-ABI surface (runtime-abi.md §4.4). Stubbed entry points are not tested —
// calling them throws by design. Catch2 runs sections sequentially in one
// process, so bracketing each with init/shutdown is enough.

#include "catch.hpp"

#include "lo_runtime/lo_runtime.h"

#include <cstdint>

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
