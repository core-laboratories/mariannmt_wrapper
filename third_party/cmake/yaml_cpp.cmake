# YAML-cpp library (required for bergamot-translator parser)
# Located at: third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/yaml-cpp/
set(YAML_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator/3rd_party/marian-dev/src/3rd_party/yaml-cpp")
file(GLOB YAML_CPP_SOURCES 
    ${YAML_CPP_DIR}/*.cpp
    ${YAML_CPP_DIR}/contrib/*.cpp
)

# Create yaml-cpp static library
add_library(yaml-cpp STATIC ${YAML_CPP_SOURCES})

# Set properties for yaml-cpp
set_target_properties(yaml-cpp PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

# Add include directories for yaml-cpp
target_include_directories(yaml-cpp PUBLIC
    ${YAML_CPP_DIR}/..
    ${YAML_CPP_DIR}
)

# Add compiler-specific warning options for yaml-cpp.
if(MSVC)
    target_compile_options(yaml-cpp PRIVATE /W3 /wd4244 /wd4267 /wd4996)
    target_compile_definitions(yaml-cpp PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(yaml-cpp PRIVATE
        -Wno-unused-value
        -Wno-unused-parameter
        -Wno-unused-variable
        -Wno-deprecated-declarations
    )
endif()
