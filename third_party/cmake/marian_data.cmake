# Build minimal marian data library (for Word::ZERO, FastOpt::uniqueNullPtr, createLoggers and other static symbols)
# We need to compile vocab.cpp which contains the definitions of Word::ZERO, Word::NONE, etc.
# and fastopt.cpp which contains FastOpt::uniqueNullPtr
# and logging.cpp which contains createLoggers function
# and options.cpp which contains Options class (needed for parseOptionsFromString)
# and config_parser.cpp, config.cpp, config_validator.cpp for ConfigParser and ConfigValidator
# Located at: third_party/bergamot-translator/3rd_party/marian-dev/src/
# Pathie library sources (needed for filesystem operations)
set(PATHIE_CPP_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/pathie-cpp/src")
set(PATHIE_SOURCES
    ${PATHIE_CPP_DIR}/path.cpp
    ${PATHIE_CPP_DIR}/pathie.cpp
    ${PATHIE_CPP_DIR}/errors.cpp
    ${PATHIE_CPP_DIR}/pathie_ifstream.cpp
    ${PATHIE_CPP_DIR}/pathie_ofstream.cpp
    ${PATHIE_CPP_DIR}/entry_iterator.cpp
    ${PATHIE_CPP_DIR}/temp.cpp
)

set(MARIAN_DATA_SOURCES
    ${MARIAN_DEV_INCLUDE_DIR}/data/vocab.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/data/default_vocab.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/data/sentencepiece_vocab.cpp  # createSentencePieceVocab function (used by vocab.cpp)
    ${MARIAN_DEV_INCLUDE_DIR}/common/fastopt.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/logging.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/options.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/config.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/config_parser.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/config_validator.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/cli_helper.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/cli_wrapper.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/utils.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/types.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/version.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/aliases.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/filesystem.cpp
    ${MARIAN_DEV_INCLUDE_DIR}/common/io.cpp  # marian::io::isBin and other IO functions
    ${MARIAN_DEV_INCLUDE_DIR}/common/binary.cpp  # Required by io.cpp for binary file support
    ${MARIAN_DEV_INCLUDE_DIR}/common/file_stream.cpp  # InputFileStream and OutputFileStream (used by binary.cpp)
    ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/phf/phf.cc  # PHF library for PerfectHash (used by FastOpt)
    ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/cnpy/cnpy.cpp  # Required by io.cpp for npz file support
    ${PATHIE_SOURCES}
)

# ExceptionWithCallStack.cpp uses backtrace()/backtrace_symbols(), which are not available in Android NDK builds.
# Upstream marian-dev also excludes it on Android:
#   if (NOT USE_WASM_COMPATIBLE_SOURCE AND NOT ANDROID) ... ExceptionWithCallStack.cpp ...
if(NOT ANDROID)
    list(APPEND MARIAN_DATA_SOURCES
        ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/ExceptionWithCallStack.cpp  # GetCallStack function (used by logging.cpp)
    )
endif()

# Create minimal marian data static library
add_library(marian-data STATIC ${MARIAN_DATA_SOURCES})

# Set properties for marian-data
set_target_properties(marian-data PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

# Link include directories and yaml-cpp (marian-data uses YAML::Clone)
target_link_libraries(marian-data PUBLIC 
    third_party_includes
    yaml-cpp
)

# Link intgemm library if available (required for intgemm_config.h and intgemm functions)
# Only enable on platforms where USE_INTGEMM is intended (not Android ARM).
if(USE_INTGEMM AND TARGET intgemm)
    target_link_libraries(marian-data PUBLIC intgemm)
    message(STATUS "Linking intgemm library to marian-data")
endif()

# Link SentencePiece library if available (required for .spm vocab files)
# SentencePiece should have been built by the add_subdirectory call above
# Now check if SentencePiece targets are available
if(TARGET sentencepiece-static)
    # Ensure SentencePiece has correct include directories for its internal headers
    # SentencePiece uses relative paths like:
    #   - "third_party/absl/strings/string_view.h" (needs sentencepiece/ root)
    #   - "google/protobuf/..." (needs sentencepiece/third_party/protobuf-lite/)
    get_target_property(SPM_INCLUDE_DIRS sentencepiece-static INTERFACE_INCLUDE_DIRECTORIES)
    if(NOT SPM_INCLUDE_DIRS)
        set(SPM_INCLUDE_DIRS "")
    endif()
    # Add SentencePiece root directory and protobuf-lite to include path if not already present
    set(SPM_ROOT_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece")
    set(SPM_PROTOBUF_LITE_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece/third_party/protobuf-lite")
    list(FIND SPM_INCLUDE_DIRS "${SPM_ROOT_DIR}" SPM_ROOT_DIR_FOUND)
    list(FIND SPM_INCLUDE_DIRS "${SPM_PROTOBUF_LITE_DIR}" SPM_PROTOBUF_LITE_DIR_FOUND)
    if(SPM_ROOT_DIR_FOUND EQUAL -1 OR SPM_PROTOBUF_LITE_DIR_FOUND EQUAL -1)
        set(SPM_EXTRA_INCLUDES "")
        if(SPM_ROOT_DIR_FOUND EQUAL -1)
            list(APPEND SPM_EXTRA_INCLUDES ${SPM_ROOT_DIR})
        endif()
        if(SPM_PROTOBUF_LITE_DIR_FOUND EQUAL -1)
            list(APPEND SPM_EXTRA_INCLUDES ${SPM_PROTOBUF_LITE_DIR})
        endif()
        target_include_directories(sentencepiece-static PRIVATE ${SPM_EXTRA_INCLUDES})
        message(STATUS "Added SentencePiece include directories: ${SPM_EXTRA_INCLUDES}")
    endif()
    target_link_libraries(marian-data PRIVATE sentencepiece-static)
    message(STATUS "Linking SentencePiece library (static) to marian-data")
elseif(TARGET sentencepiece)
    # Same for shared library
    get_target_property(SPM_INCLUDE_DIRS sentencepiece INTERFACE_INCLUDE_DIRECTORIES)
    if(NOT SPM_INCLUDE_DIRS)
        set(SPM_INCLUDE_DIRS "")
    endif()
    set(SPM_ROOT_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece")
    set(SPM_PROTOBUF_LITE_DIR "${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece/third_party/protobuf-lite")
    list(FIND SPM_INCLUDE_DIRS "${SPM_ROOT_DIR}" SPM_ROOT_DIR_FOUND)
    list(FIND SPM_INCLUDE_DIRS "${SPM_PROTOBUF_LITE_DIR}" SPM_PROTOBUF_LITE_DIR_FOUND)
    if(SPM_ROOT_DIR_FOUND EQUAL -1 OR SPM_PROTOBUF_LITE_DIR_FOUND EQUAL -1)
        set(SPM_EXTRA_INCLUDES "")
        if(SPM_ROOT_DIR_FOUND EQUAL -1)
            list(APPEND SPM_EXTRA_INCLUDES ${SPM_ROOT_DIR})
        endif()
        if(SPM_PROTOBUF_LITE_DIR_FOUND EQUAL -1)
            list(APPEND SPM_EXTRA_INCLUDES ${SPM_PROTOBUF_LITE_DIR})
        endif()
        target_include_directories(sentencepiece PRIVATE ${SPM_EXTRA_INCLUDES})
        message(STATUS "Added SentencePiece include directories: ${SPM_EXTRA_INCLUDES}")
    endif()
    target_link_libraries(marian-data PRIVATE sentencepiece)
    message(STATUS "Linking SentencePiece library (shared) to marian-data")
else()
    message(WARNING "SentencePiece library not found. .spm vocab files may not work correctly.")
    message(WARNING "  This may cause crashes when loading .spm vocabulary files.")
    message(WARNING "  Ensure USE_SENTENCEPIECE=ON is set and bergamot-translator/3rd_party is included.")
endif()

# Add COMPILE_CPU definition (required for intgemm support)
# This is needed because prepareAndTransposeB and other CPU-specific functions require COMPILE_CPU to be defined
# Reference: marian-dev/CMakeLists.txt line 640: add_definitions(-DCOMPILE_CPU=1)
target_compile_definitions(marian-data PRIVATE COMPILE_CPU=1)

# Add USE_INTGEMM definition (required for intgemm matrix operations)
# Reference: marian-dev/CMakeLists.txt line 87-91: set(USE_INTGEMM ON) and add_compile_definitions(USE_INTGEMM=1)
# Only define when USE_INTGEMM is enabled; otherwise Marian will use the RUY/NEON path.
if(USE_INTGEMM)
    target_compile_definitions(marian-data PRIVATE USE_INTGEMM=1)
endif()

# Add USE_RUY_SGEMM definition (required for CPU matrix multiplication)
# RUY library is already in include path (third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy)
# This enables the use of RUY library for optimized float matrix multiplication on CPU
target_compile_definitions(marian-data PRIVATE USE_RUY_SGEMM=1)

# Add compiler-specific warning options.
if(MSVC)
    target_compile_options(marian-data PRIVATE /W3 /wd4244 /wd4267 /wd4996)
    target_compile_definitions(marian-data PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(marian-data PRIVATE
        -Wno-unused-parameter
        -Wno-unused-variable
        -Wno-unused-value
        -Wno-deprecated-declarations
        -Wno-unknown-pragmas
    )
endif()

# For Android ARM platforms, ensure ARM, FMA, and SSE macros are defined
# This is required for simd_utils.h to work correctly on ARM
# Reference: marian-dev/CMakeLists.txt line 96: add_compile_definitions(ARM FMA SSE) for ARM
if(ANDROID AND ANDROID_ABI MATCHES "arm")
    target_compile_definitions(marian-data PRIVATE ARM FMA SSE)
    message(STATUS "Adding ARM FMA SSE compile definitions for marian-data on Android ${ANDROID_ABI}")
endif()

# For Android platforms, define PATHIE_ASSUME_UTF8_ON_UNIX to avoid iconv/nl_langinfo dependencies
# Android uses UTF-8 as filesystem encoding, so this is safe
# Reference: pathie-cpp/README.md: PATHIE_ASSUME_UTF8_ON_UNIX forces Pathie to assume UTF-8 on UNIX
# Note: This only affects utf8_to_filename and filename_to_utf8, not convert_encodings
if(ANDROID)
    target_compile_definitions(marian-data PRIVATE PATHIE_ASSUME_UTF8_ON_UNIX)
    message(STATUS "Adding PATHIE_ASSUME_UTF8_ON_UNIX compile definition for marian-data on Android")
    
    # Disable backtrace on Android (not available in Android NDK)
    # Reference: ExceptionWithCallStack.cpp uses backtrace() which is not available on Android
    target_compile_definitions(marian-data PRIVATE ANDROID)
    message(STATUS "Adding ANDROID compile definition for marian-data to disable backtrace")
endif()

# Create dummy version headers if they don't exist (needed by version.cpp)
# These are workarounds for files that include git_revision.h and project_version.h
# The files need to be in the common/ directory because version.cpp uses #include "common/git_revision.h"
set(COMMON_DIR "${MARIAN_DEV_INCLUDE_DIR}/common")
set(GIT_REVISION_HEADER "${COMMON_DIR}/git_revision.h")
set(PROJECT_VERSION_HEADER "${COMMON_DIR}/project_version.h")

# Create git_revision.h if it doesn't exist
if(NOT EXISTS "${GIT_REVISION_HEADER}")
    file(WRITE "${GIT_REVISION_HEADER}" "#define GIT_REVISION \"unknown\"\n")
endif()

# Create project_version.h if it doesn't exist
if(NOT EXISTS "${PROJECT_VERSION_HEADER}")
    file(WRITE "${PROJECT_VERSION_HEADER}" "#define PROJECT_VERSION \"0.0.0\"\n")
endif()

# Link marian-data to bergamot-translator
target_link_libraries(bergamot-translator PUBLIC marian-data)

# Note: bergamot-translator also depends on full marian and ssplit libraries
# The original bergamot-translator CMakeLists.txt links: marian ssplit
# We're building a minimal marian-data library for essential symbols like Word::ZERO.
# If more marian symbols are needed, the full marian library will need to be built.
