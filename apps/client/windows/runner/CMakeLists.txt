cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Keep the logical target separate from the executable filename, which may
# contain spaces. Both names are configured in the top-level CMakeLists.txt.
#
# Any new source files that you add to the application should be added here.
add_executable(${NIGHTCORD_RUNNER_TARGET} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
set_target_properties(${NIGHTCORD_RUNNER_TARGET} PROPERTIES OUTPUT_NAME "${BINARY_NAME}")

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${NIGHTCORD_RUNNER_TARGET})

# Add preprocessor definitions for the build version.
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${NIGHTCORD_RUNNER_TARGET} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${NIGHTCORD_RUNNER_TARGET} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${NIGHTCORD_RUNNER_TARGET} PRIVATE "dwmapi.lib")
target_include_directories(${NIGHTCORD_RUNNER_TARGET} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${NIGHTCORD_RUNNER_TARGET} flutter_assemble)
