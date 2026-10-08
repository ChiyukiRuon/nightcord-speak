cmake_minimum_required(VERSION 3.20)
project(screen_capture_smoke LANGUAGES CXX)

get_filename_component(WEBRTC_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../../../../vendor/flutter-webrtc" ABSOLUTE)
add_executable(screen_capture_smoke
  "../screen_capture_smoke.cc"
  "${WEBRTC_ROOT}/windows/wgc_screen_capturer.cc")
target_compile_features(screen_capture_smoke PRIVATE cxx_std_17)
# This macro changes the factory's vtable layout and must match the DLL.
target_compile_definitions(screen_capture_smoke PRIVATE
  LIB_WEBRTC_API_DLL RTC_DESKTOP_DEVICE NOMINMAX)
target_compile_options(screen_capture_smoke PRIVATE /utf-8 /W4 /WX /wd4100 /EHsc)
target_include_directories(screen_capture_smoke PRIVATE
  "${WEBRTC_ROOT}/windows"
  "${WEBRTC_ROOT}/third_party/libwebrtc/include")
target_link_libraries(screen_capture_smoke PRIVATE
  "${WEBRTC_ROOT}/third_party/libwebrtc/lib/libwebrtc.dll.lib"
  d3d11 dxgi windowsapp runtimeobject)
add_custom_command(TARGET screen_capture_smoke POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${WEBRTC_ROOT}/third_party/libwebrtc/lib/libwebrtc.dll"
    "$<TARGET_FILE_DIR:screen_capture_smoke>")
