if(TARGET cld2)
    return()
endif()


# Get the correct path to cld2 (works with Flutter plugin symlinks)
# If CLD2_DIR is not already set, calculate it from the current file location
if(NOT DEFINED CLD2_DIR)
    # Try relative path first (when called from third_party/CMakeLists.txt)
    get_filename_component(CLD2_DIR_CANDIDATE "${CMAKE_CURRENT_LIST_DIR}/../cld2" ABSOLUTE)
    # Check if the directory exists
    if(EXISTS "${CLD2_DIR_CANDIDATE}")
        set(CLD2_DIR "${CLD2_DIR_CANDIDATE}")
    else()
        # Try the symlink path (for Flutter plugin symlinks)
        get_filename_component(CLD2_DIR "${CMAKE_CURRENT_LIST_DIR}/../../third_party/cld2" ABSOLUTE)
    endif()
endif()

# Collect all source files
set(CLD2_SOURCES
    ${CLD2_DIR}/internal/cldutil.cc
    ${CLD2_DIR}/internal/cldutil_shared.cc
    ${CLD2_DIR}/internal/compact_lang_det.cc
    ${CLD2_DIR}/internal/compact_lang_det_hint_code.cc
    ${CLD2_DIR}/internal/compact_lang_det_impl.cc
    ${CLD2_DIR}/internal/debug.cc
    ${CLD2_DIR}/internal/fixunicodevalue.cc
    ${CLD2_DIR}/internal/generated_entities.cc
    ${CLD2_DIR}/internal/generated_language.cc
    ${CLD2_DIR}/internal/generated_ulscript.cc
    ${CLD2_DIR}/internal/getonescriptspan.cc
    ${CLD2_DIR}/internal/lang_script.cc
    ${CLD2_DIR}/internal/offsetmap.cc
    ${CLD2_DIR}/internal/scoreonescriptspan.cc
    ${CLD2_DIR}/internal/tote.cc
    ${CLD2_DIR}/internal/utf8statetable.cc
    ${CLD2_DIR}/internal/cld_generated_cjk_uni_prop_80.cc
    ${CLD2_DIR}/internal/cld2_generated_cjk_compatible.cc
    ${CLD2_DIR}/internal/cld_generated_cjk_delta_bi_4.cc
    ${CLD2_DIR}/internal/generated_distinct_bi_0.cc
    ${CLD2_DIR}/internal/cld2_generated_quadchrome_2.cc
    ${CLD2_DIR}/internal/cld2_generated_deltaoctachrome.cc
    ${CLD2_DIR}/internal/cld2_generated_distinctoctachrome.cc
    ${CLD2_DIR}/internal/cld_generated_score_quad_octa_2.cc
)

# Create static library
add_library(cld2 STATIC ${CLD2_SOURCES})

# Set properties for the library
set_target_properties(cld2 PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    SOVERSION 1
    VERSION 1.0.0
)

if(MSVC)
    target_compile_options(cld2 PRIVATE /W3 /wd4244 /wd4267 /wd4996)
    target_compile_definitions(cld2 PRIVATE NOMINMAX _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(cld2 PRIVATE
        -Wno-narrowing
        -Wno-non-c-typedef-for-linkage
        -Wno-deprecated-declarations
    )
endif()

# Add include directories
target_include_directories(cld2
    PUBLIC
        ${CLD2_DIR}
        ${CLD2_DIR}/public
        ${CLD2_DIR}/internal
)
