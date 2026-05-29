#include "lo_runtime/cast.h"

#include <stdexcept>

// Both stubbed — the team implements these in P3.
//
// Hints (from the ABI): lo_cast_check returns obj if its class is target or a
// descendant, else aborts (exit 101); null obj short-circuits to null.
// lo_instanceof returns a bool and never aborts; null receiver yields false.
// Both walk ClassDescriptor::parent up the single-inheritance chain.

extern "C" Object *lo_cast_check(Object *obj, const ClassDescriptor *target) {
  (void)obj;
  (void)target;
  throw std::runtime_error("lo_cast_check: team implements per P3");
}

extern "C" bool lo_instanceof(Object *obj, const ClassDescriptor *target) {
  (void)obj;
  (void)target;
  throw std::runtime_error("lo_instanceof: team implements per P3");
}
