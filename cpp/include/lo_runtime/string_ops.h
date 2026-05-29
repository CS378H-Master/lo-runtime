// String operations (runtime-abi.md §3.2). All stubbed — the team implements
// these in P3.
#pragma once

#include "lo_runtime/object.h"

extern "C" {
Object *lo_string_new(const char *bytes, std::uint32_t len);
Object *lo_string_concat(Object *a, Object *b);
Object *lo_string_repeat(Object *s, std::int32_t n);
std::int32_t lo_string_compare(Object *a, Object *b);
Object *lo_string_reverse(Object *s);
}
