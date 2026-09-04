# SentencePiece library configuration and building
# SentencePiece is built as part of bergamot-translator's marian-dev submodule

# Ensure SentencePiece root directory and protobuf-lite are in include path before building
# SentencePiece headers use relative paths like:
#   - "third_party/absl/strings/string_view.h" (at sentencepiece/third_party/absl/...)
#   - "google/protobuf/generated_message_table_driven.h" (at sentencepiece/third_party/protobuf-lite/google/protobuf/...)
# SentencePiece's CMakeLists.txt sets include_directories, but we need to ensure
# these paths are available during compilation
set(SPM_ROOT_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece")
set(SPM_PROTOBUF_LITE_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece/third_party/protobuf-lite")
include_directories(${SPM_ROOT_DIR} ${SPM_PROTOBUF_LITE_DIR})

# Temporarily set C++14 for SentencePiece subdirectory
# SentencePiece requires C++11, but trainer_interface.cc needs C++14 for constexpr with static_cast
# In C++11, static_cast for enum types is not considered a constant expression
# C++14 relaxed constexpr rules to allow static_cast in constexpr contexts
set(_SAVED_CMAKE_CXX_STANDARD ${CMAKE_CXX_STANDARD})
set(_SAVED_CMAKE_CXX_STANDARD_REQUIRED ${CMAKE_CXX_STANDARD_REQUIRED})
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include bergamot-translator's 3rd_party subdirectory to build SentencePiece and intgemm
# This will build marian-dev, SentencePiece, and intgemm libraries
# NOTE: This must be done BEFORE creating marian-data library so SentencePiece and intgemm targets are available
# SentencePiece's CMakeLists.txt sets CMAKE_CXX_STANDARD to 11, but we override to 14 for trainer_interface.cc compatibility
add_subdirectory(${BERGAMOT_TRANSLATOR_ROOT_INCLUDE_DIR}/3rd_party EXCLUDE_FROM_ALL)

# Marian enables /WX for its own targets on MSVC. Recent Visual Studio releases
# report narrowing conversions in Ruy's templated matrix adapter as C4244,
# which makes the bundled third-party code fail before the wrapper is linked.
# Keep warnings enabled, but do not promote upstream warnings to errors, and
# silence the known conversion diagnostics on the target that compiles Ruy.
if(MSVC AND TARGET marian)
    target_compile_options(marian PRIVATE
        /WX-
        /wd4244
        /wd4267
    )
    message(STATUS "Configured Marian warning compatibility for MSVC")
endif()

# Suppress zlib compilation warnings
# zlib is built as part of the 3rd_party subdirectory
if(TARGET zlib AND NOT MSVC)
    target_compile_options(zlib PRIVATE -Wno-deprecated-non-prototype)
    message(STATUS "Added -Wno-deprecated-non-prototype to zlib target to suppress function prototype warnings")
endif()

# Restore C++ standard setting after SentencePiece subdirectory
set(CMAKE_CXX_STANDARD ${_SAVED_CMAKE_CXX_STANDARD})
set(CMAKE_CXX_STANDARD_REQUIRED ${_SAVED_CMAKE_CXX_STANDARD_REQUIRED})

# Link intgemm library if it was built (required for intgemm_config.h and intgemm functions)
# intgemm is built when USE_INTGEMM is ON, which we set above
# The intgemm target provides the build directory include path (for intgemm_config.h)
if(TARGET intgemm)
    # intgemm's PUBLIC include directories will be automatically propagated when linking
    # This ensures intgemm_config.h can be found
    message(STATUS "intgemm library found, will be linked via marian library")
else()
    message(WARNING "intgemm library target not found. This may cause 'intgemm_config.h' not found errors.")
endif()

# Ensure SentencePiece targets use C++14 standard (required for constexpr compatibility)
# SentencePiece's CMakeLists.txt sets C++11, but parent C++17 setting may override it
# The constexpr issue in trainer_interface.cc:211 requires C++14
# In C++11, constexpr with static_cast may not be recognized as constant expression in C++17 mode
# We need to force C++14 standard for all SentencePiece targets using compile options
# NOTE: Only set properties on actual targets (sentencepiece-static, sentencepiece_train-static)
# ALIAS targets (sentencepiece, sentencepiece_train) will inherit properties from their aliased targets
if(TARGET sentencepiece-static)
    # Force C++14 standard using compile options (this overrides any parent C++17 setting)
    # C++14 is needed for constexpr compatibility in trainer_interface.cc
    if(NOT MSVC)
        target_compile_options(sentencepiece-static PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:-std=c++14>
        )
    endif()
    # Also set target properties for consistency
    set_target_properties(sentencepiece-static PROPERTIES
        CXX_STANDARD 14
        CXX_STANDARD_REQUIRED ON
    )
    if(MSVC)
        # Modern CMake selects the runtime through this property. Match the
        # dynamic runtime used by Marian and the Flutter Windows runner.
        set_property(TARGET sentencepiece-static PROPERTY
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
        )
    endif()
endif()
if(TARGET sentencepiece_train-static)
    # trainer_interface.cc is part of sentencepiece_train-static and has constexpr issue
    # In C++11, static_cast for enum types is not considered a constant expression
    # We need C++14 or later for constexpr with static_cast to work properly
    # Force C++14 for the entire target to allow constexpr with static_cast
    if(NOT MSVC)
        target_compile_options(sentencepiece_train-static PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:-std=c++14>
        )
    endif()
    set_target_properties(sentencepiece_train-static PROPERTIES
        CXX_STANDARD 14
        CXX_STANDARD_REQUIRED ON
    )
    if(MSVC)
        set_property(TARGET sentencepiece_train-static PROPERTY
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
        )
    endif()
    # Ensure trainer_interface.cc uses C++14 to allow constexpr with static_cast
    # C++14 relaxed constexpr rules to allow static_cast in constexpr contexts
    if(NOT MSVC)
        set_source_files_properties(
            "${BERGAMOT_TRANSLATOR_ROOT_INCLUDE_DIR}/3rd_party/marian-dev/src/3rd_party/sentencepiece/src/trainer_interface.cc"
            PROPERTIES
                COMPILE_FLAGS "-std=c++14"
                CXX_STANDARD 14
        )
    endif()
endif()
