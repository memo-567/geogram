# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "whisper_flutter_new")
project(${PROJECT_NAME} LANGUAGES CXX C)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)

# Optimization flags for release builds
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -fdata-sections -ffunction-sections")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -fdata-sections -ffunction-sections")

# Suppress deprecated literal operator warning from json.hpp (third-party code)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-deprecated-literal-operator")

# Build whisper library from source
file(GLOB WHISPER_SRC
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/whisper.cpp/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/whisper.cpp/*.c"
)

add_library(whisper STATIC ${WHISPER_SRC})
target_include_directories(whisper PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../src/whisper.cpp")
target_compile_options(whisper PRIVATE -fPIC)

# Build plugin shared library
add_library(${PLUGIN_NAME} SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/main.cpp"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/json"
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/whisper.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  OUTPUT_NAME "whisper"
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE DART_SHARED_LIB)
target_link_libraries(${PLUGIN_NAME} PRIVATE whisper pthread)

# Bundle the shared library so it's copied to the app's lib directory
set(whisper_flutter_new_bundled_libraries
  "$<TARGET_FILE:${PLUGIN_NAME}>"
  PARENT_SCOPE
)
