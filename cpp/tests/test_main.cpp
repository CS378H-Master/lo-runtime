// Catch2 main translation unit. Keeping CATCH_CONFIG_MAIN in its own TU keeps the
// (slow) Catch2 header compile out of the test bodies' TU.
#define CATCH_CONFIG_MAIN
#include "catch.hpp"
