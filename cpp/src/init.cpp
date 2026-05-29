#include "lo_runtime/init.h"

#include "lo_runtime/alloc.h"
#include "lo_runtime/descriptors.h"
#include "lo_runtime/shadow_stack.h"

extern "C" void lo_runtime_init() {
  lo::heap_init();
  lo::reset_shadow_stack();
  lo::init_empty_string();
}

extern "C" void lo_runtime_shutdown() {
  lo::clear_empty_string();
  lo::reset_shadow_stack();
  lo::heap_shutdown();
}
