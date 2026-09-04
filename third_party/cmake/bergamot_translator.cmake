# Build bergamot-translator library
# Collect all source files from bergamot-translator
set(BERGAMOT_TRANSLATOR_SOURCES
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/byte_array_util.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/text_processor.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/translation_model.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/request.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/batching_pool.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/aggregate_batching_pool.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/response_builder.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/quality_estimator.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/batch.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/annotation.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/service.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/parser.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/response.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/html.cpp
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}/translator/xh_scanner.cpp
)

# Create bergamot-translator static library
add_library(bergamot-translator STATIC ${BERGAMOT_TRANSLATOR_SOURCES})

# Set C++ standard for bergamot-translator
set_target_properties(bergamot-translator PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON  # Required for linking into shared libraries
)

# Link include directories and yaml-cpp library
target_link_libraries(bergamot-translator PUBLIC 
    third_party_includes
    yaml-cpp
)

# Link intgemm library if available (required for intgemm_config.h and intgemm functions)
# Only enable on platforms where USE_INTGEMM is intended (not Android ARM).
if(USE_INTGEMM AND TARGET intgemm)
    target_link_libraries(bergamot-translator PUBLIC intgemm)
    message(STATUS "Linking intgemm library to bergamot-translator")
endif()

# Add COMPILE_CPU definition (required for intgemm support)
# This is needed because prepareAndTransposeB and other CPU-specific functions require COMPILE_CPU to be defined
target_compile_definitions(bergamot-translator PRIVATE COMPILE_CPU=1)

# Add USE_INTGEMM definition (required for intgemm matrix operations)
# Reference: marian-dev/CMakeLists.txt line 87-91: set(USE_INTGEMM ON) and add_compile_definitions(USE_INTGEMM=1)
# Only define when USE_INTGEMM is enabled; otherwise Marian will use the RUY/NEON path.
if(USE_INTGEMM)
    target_compile_definitions(bergamot-translator PRIVATE USE_INTGEMM=1)
endif()

# Add USE_RUY_SGEMM definition (required for CPU matrix multiplication)
# RUY library is already in include path (third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/ruy)
# This enables the use of RUY library for optimized float matrix multiplication on CPU
target_compile_definitions(bergamot-translator PRIVATE USE_RUY_SGEMM=1)

# Add compile options to handle potential issues
if(MSVC)
    target_compile_options(bergamot-translator PRIVATE /W3 /wd4244 /wd4267 /wd4996)
    target_compile_definitions(bergamot-translator PRIVATE
        NOMINMAX
        _CRT_SECURE_NO_WARNINGS
        WIN32_LEAN_AND_MEAN
    )
else()
    target_compile_options(bergamot-translator PRIVATE
        -Wno-unused-parameter
        -Wno-unused-variable
        -Wno-unused-value
        -Wno-deprecated-declarations
    )
endif()

# For Android ARM platforms, ensure ARM, FMA, and SSE macros are defined
# This is required for simd_utils.h to work correctly on ARM
# Reference: marian-dev/CMakeLists.txt line 96: add_compile_definitions(ARM FMA SSE) for ARM
if(ANDROID AND ANDROID_ABI MATCHES "arm")
    target_compile_definitions(bergamot-translator PRIVATE ARM FMA SSE)
    message(STATUS "Adding ARM FMA SSE compile definitions for bergamot-translator on Android ${ANDROID_ABI}")
endif()
