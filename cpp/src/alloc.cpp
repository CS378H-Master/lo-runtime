#include "lo_runtime/alloc.h"

#include "lo_runtime/abort.h"
#include "lo_runtime/descriptors.h"

#include <cstdlib>
#include <cstring>
#include <vector>

// The provided bump allocator: hands out 8-byte-aligned, zero-initialized slabs
// from a single contiguous heap (a std::vector<uint8_t>, whose storage is
// max_align_t-aligned) until full, then aborts (exit 137). No GC yet — the
// OOM-retry path is the team's P3 work. Single-threaded by spec.

namespace {

std::vector<std::uint8_t> g_heap;
std::size_t g_bump = 0;

constexpr std::size_t kDefaultHeapSize = std::size_t{16} * 1024 * 1024;
constexpr std::size_t kHeapAlign = 16;

std::size_t align_up(std::size_t n, std::size_t a) { return (n + a - 1) & ~(a - 1); }

std::size_t read_heap_size() {
  const char *v = std::getenv("LO_HEAP_SIZE");
  if (v != nullptr) {
    char *end = nullptr;
    const unsigned long long n = std::strtoull(v, &end, 10);
    if (end != v && n >= kHeapAlign) {
      return static_cast<std::size_t>(n);
    }
  }
  return kDefaultHeapSize;
}

Object *alloc_raw(std::size_t size, const ClassDescriptor *cls) {
  if (g_heap.empty() || size > g_heap.size() - g_bump) {
    lo::runtime_abort("lo_alloc: out of memory", 137);
  }
  std::uint8_t *p = g_heap.data() + g_bump;
  g_bump += size;
  std::memset(p, 0, size);
  auto *o = reinterpret_cast<Object *>(p);
  o->class_descriptor = cls;
  o->gc_bits = 0;
  o->flags = 0;
  return o;
}

} // namespace

namespace lo {

void heap_init() {
  g_heap.assign(read_heap_size(), 0);
  g_bump = 0;
}

void heap_shutdown() {
  g_heap.clear();
  g_heap.shrink_to_fit();
  g_bump = 0;
}

Object *bump_alloc_string(std::uint32_t len) {
  const std::size_t size = align_up(string_data_offset() + len, 8);
  Object *o = alloc_raw(size, &LO_STRING_CLASS);
  auto *so = reinterpret_cast<StringObject *>(o);
  so->length = len;
  return o;
}

} // namespace lo

extern "C" Object *lo_alloc(const ClassDescriptor *cls) {
  const std::size_t size = align_up(static_cast<std::size_t>(cls->instance_size), 8);
  return alloc_raw(size, cls);
}
