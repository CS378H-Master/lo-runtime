cmake_minimum_required(VERSION 3.28)
project(lo_runtime LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# --- Static library (native AOT linkage target) -----------------------------
add_library(lo_runtime STATIC
  src/abort.cpp
  src/alloc.cpp
  src/cast.cpp
  src/descriptors.cpp
  src/gc.cpp
  src/init.cpp
  src/io.cpp
  src/shadow_stack.cpp
  src/string_ops.cpp)
target_include_directories(lo_runtime PUBLIC include)
# Strict warnings on our own code only (not the vendored Catch2 header or tests).
target_compile_options(lo_runtime PRIVATE -Wall -Wextra -Werror)

# WASM: the course's C++/WASM toolchain (Emscripten vs wasm-clang) is an open DC
# decision (see runbook open items + cc-phase3-notes.md). The sources are
# WASM-ready via `#ifdef __wasm__` host-import branches; wiring an actual WASM
# target is deferred until the toolchain is fixed. To build manually once chosen,
# e.g.: clang++ --target=wasm32 -fno-exceptions -nostdlib -c src/*.cpp

# --- Tests ------------------------------------------------------------------
enable_testing()

# Catch2 (vendored single header under tests/) ABI smoke suite.
add_executable(lo_runtime_tests tests/test_main.cpp tests/abi_tests.cpp)
target_link_libraries(lo_runtime_tests PRIVATE lo_runtime)
target_include_directories(lo_runtime_tests PRIVATE tests)
add_test(NAME lo_runtime_tests COMMAND lo_runtime_tests)

# I/O round-trip + abort-code checks via a probe + shell harness.
add_executable(lo_io_probe tests/lo_io_probe.cpp)
target_link_libraries(lo_io_probe PRIVATE lo_runtime)
add_test(NAME io_round_trip
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/io_roundtrip.sh $<TARGET_FILE:lo_io_probe>)
