/*
 * Cross-skeleton ABI link test (runtime-abi.md §4, runbook WS-1 Phase 4.4).
 *
 * This is a pure C program — it does NOT include any skeleton's headers. It
 * re-declares only the slice of the C ABI it uses and links against a given
 * skeleton's static library (Rust / Zig / C++). If it links and runs, that
 * skeleton genuinely honors the C ABI from C code — the actual promise the three
 * skeletons make. All three must produce identical output.
 *
 * It also re-declares the Object / ClassDescriptor layout from C and
 * _Static_assert's the sizes/offsets, giving a fourth (C-side) witness to the
 * byte layout the three skeletons' own compile-time checks already pin.
 */
#include <stddef.h>
#include <stdint.h>

/* --- ABI types, as a C consumer sees them (runtime-abi.md §2) ------------- */
typedef struct ClassDescriptor ClassDescriptor;

typedef struct Object {
  const ClassDescriptor *class_descriptor;
  uint32_t gc_bits;
  uint32_t flags;
} Object;

struct ClassDescriptor {
  const char *name;
  uint32_t name_len;
  const ClassDescriptor *parent;
  uint32_t instance_size;
  const uint32_t *pointer_offsets;
  uint32_t pointer_count;
  uint32_t vtable_size;
  const void *vtable;
};

typedef struct StringObject {
  Object header;
  uint32_t length;
  /* inline bytes follow at offsetof(StringObject, length) + sizeof(uint32_t) */
} StringObject;

/* 64-bit layout locks, matching the Rust const_/Zig comptime/C++ static_assert. */
#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
_Static_assert(sizeof(Object) == 16, "Object must be 16 bytes on 64-bit");
_Static_assert(offsetof(StringObject, length) + sizeof(uint32_t) == 20,
               "string data must start at offset 20 on 64-bit");
#endif

/* --- The C-ABI surface this harness exercises (the provided entry points) - */
extern void lo_runtime_init(void);
extern void lo_runtime_shutdown(void);
extern Object *lo_alloc(const ClassDescriptor *cls);
extern void lo_print_int(int32_t n);
extern void lo_print_string(Object *s);
extern void lo_println(void);

/* Exported statics codegen references by symbol. */
extern const ClassDescriptor LO_INT_BOX_CLASS;
extern const ClassDescriptor LO_STRING_CLASS;
extern Object *LO_EMPTY_STRING;

int main(void) {
  lo_runtime_init();

  /* Allocate an object through the bump allocator and confirm the header the
   * runtime stamped is the descriptor we passed. */
  Object *o = lo_alloc(&LO_INT_BOX_CLASS);
  if (o == NULL || o->class_descriptor != &LO_INT_BOX_CLASS) {
    return 2;
  }

  /* The empty-string singleton must be a valid length-0 String after init. */
  if (LO_EMPTY_STRING == NULL ||
      LO_EMPTY_STRING->class_descriptor != &LO_STRING_CLASS) {
    return 3;
  }

  /* Output the canonical line the cross-skeleton check compares: "42\n". */
  lo_print_int(42);
  lo_println();

  lo_runtime_shutdown();
  return 0;
}
