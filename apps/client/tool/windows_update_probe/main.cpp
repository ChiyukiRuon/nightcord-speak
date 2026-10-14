#include "../../windows/runner/update_launcher.h"

#include <shellapi.h>
#include <filesystem>
#include <fstream>

std::string ToUtf8(const wchar_t* text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, result.data(), size, nullptr, nullptr);
  result.pop_back();
  return result;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  // Deliberately do not attach/create a console: reproduce the GUI caller.
  if (GetConsoleWindow() != nullptr) return 3;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  int count = 0;
  auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!arguments || count != 4) return 2;
  const auto launched = LaunchUpdateHelper(ToUtf8(arguments[1]), ToUtf8(arguments[2]));
  std::ofstream report{std::filesystem::path(arguments[3])};
  report << launched.pid << '\n' << launched.error << '\n';
  report.close();
  LocalFree(arguments);
  CoUninitialize();
  return launched.error == ERROR_SUCCESS ? 0 : 1;
}
