#include "lo_runtime/shadow_stack.h"

#include <cassert>

namespace {
ShadowFrame *g_current = nullptr;
}

extern "C" void lo_push_frame(ShadowFrame *frame) {
  frame->parent = g_current;
  g_current = frame;
}

extern "C" void lo_pop_frame() {
  // A pop with no matching push is a codegen bug; the assertion catches it in
  // development (mirrors the Rust debug_assert / Zig unreachable).
  assert(g_current != nullptr && "lo_pop_frame called with no current frame");
  g_current = g_current->parent;
}

namespace lo {
ShadowFrame *current_frame() { return g_current; }
void reset_shadow_stack() { g_current = nullptr; }
} // namespace lo
