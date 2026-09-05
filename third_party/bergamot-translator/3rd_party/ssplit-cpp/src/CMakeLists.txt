include_directories(ssplit)
add_library(ssplit STATIC ssplit/ssplit.cpp ssplit/regex.cpp)
target_link_libraries(ssplit ${EXT_LIBS})

# FindPCRE2 exposes the bundled archive as a path rather than an imported
# CMake target, so PCRE2's interface definition cannot propagate naturally.
# Static consumers need this definition to avoid importing __imp_pcre2_* DLL
# symbols that do not exist in pcre2-8-static.lib.
if(SSPLIT_USE_INTERNAL_PCRE2)
  target_compile_definitions(ssplit PRIVATE PCRE2_STATIC)
endif()

set_target_properties(ssplit PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

if (NOT COMPILE_LIBRARY_ONLY)
  include_directories(3rd-party/CLI11)
  if (NOT WIN32)
    # ssplit-main has some mmap() code, and include "sys/mman.h"
    # which is only available on *nix
    add_executable(ssplit_executable command/ssplit_main.cpp)
    target_link_libraries(ssplit_executable ssplit)
    set_target_properties(ssplit_executable PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}
      OUTPUT_NAME ssplit)
  endif (NOT WIN32)

  add_executable(ssplit_test_executable command/test_ssplit.cpp)
  target_link_libraries(ssplit_test_executable ssplit)
  set_target_properties(ssplit_test_executable PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}
    OUTPUT_NAME test_ssplit)
endif(NOT COMPILE_LIBRARY_ONLY)
