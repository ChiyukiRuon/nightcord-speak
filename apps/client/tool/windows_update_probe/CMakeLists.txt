cmake_minimum_required(VERSION 3.14)
project(windows_update_probe LANGUAGES CXX)
add_executable(windows-update-probe WIN32
  "main.cpp"
  "../../windows/runner/update_launcher.cpp"
)
target_compile_features(windows-update-probe PRIVATE cxx_std_17)
target_compile_definitions(windows-update-probe PRIVATE NOMINMAX UNICODE _UNICODE)
target_compile_options(windows-update-probe PRIVATE /W4 /WX /utf-8 /EHsc)
target_link_libraries(windows-update-probe PRIVATE shell32 ole32)
