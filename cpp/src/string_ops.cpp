#include "lo_runtime/string_ops.h"

#include <stdexcept>

// All stubbed — the team implements these in P3. Each carries the exact C-ABI
// signature so the skeleton links; calling one throws.
//
// Hints (from the ABI): lo_string_repeat aborts on negative count (exit 120);
// lo_string_compare is lexicographic UTF-8 byte ordering; lo_string_reverse
// reverses codepoints, not bytes. Build results with lo::bump_alloc_string.

extern "C" Object *lo_string_new(const char *bytes, std::uint32_t len) {
  (void)bytes;
  (void)len;
  throw std::runtime_error("lo_string_new: team implements per P3");
}

extern "C" Object *lo_string_concat(Object *a, Object *b) {
  (void)a;
  (void)b;
  throw std::runtime_error("lo_string_concat: team implements per P3");
}

extern "C" Object *lo_string_repeat(Object *s, std::int32_t n) {
  (void)s;
  (void)n;
  throw std::runtime_error("lo_string_repeat: team implements per P3");
}

extern "C" std::int32_t lo_string_compare(Object *a, Object *b) {
  (void)a;
  (void)b;
  throw std::runtime_error("lo_string_compare: team implements per P3");
}

extern "C" Object *lo_string_reverse(Object *s) {
  (void)s;
  throw std::runtime_error("lo_string_reverse: team implements per P3");
}
