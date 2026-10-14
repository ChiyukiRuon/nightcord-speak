#include "update_launcher.h"

#include <shellapi.h>

namespace {
std::wstring ToWide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                     value.data(), static_cast<int>(value.size()),
                                     nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(), size)) {
    return {};
  }
  return result;
}
}  // namespace

UpdateLaunchResult LaunchUpdateHelper(const std::string& script,
                                     const std::string& configuration) {
  const auto script_path = ToWide(script);
  const auto configuration_path = ToWide(configuration);
  if (script_path.empty() || configuration_path.empty() ||
      script_path.find(L'"') != std::wstring::npos ||
      configuration_path.find(L'"') != std::wstring::npos) {
    return {0, ERROR_INVALID_PARAMETER};
  }
  wchar_t system_directory[MAX_PATH];
  const UINT length = GetSystemDirectoryW(system_directory, MAX_PATH);
  if (length == 0) return {0, GetLastError()};
  if (length >= MAX_PATH) return {0, ERROR_INSUFFICIENT_BUFFER};
  const std::wstring powershell = std::wstring(system_directory) +
      L"\\WindowsPowerShell\\v1.0\\powershell.exe";
  const std::wstring arguments =
      L"-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden "
      L"-File \"" + script_path + L"\" -Configuration \"" + configuration_path + L"\"";
  SHELLEXECUTEINFOW launch{};
  launch.cbSize = sizeof(launch);
  launch.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
  launch.lpVerb = L"open";
  launch.lpFile = powershell.c_str();
  launch.lpParameters = arguments.c_str();
  launch.nShow = SW_HIDE;
  // Shell launch supplies a real console for PowerShell even when the client
  // has none. Do not inherit Dart's detached/invalid standard handles.
  if (!ShellExecuteExW(&launch)) return {0, GetLastError()};
  if (!launch.hProcess) return {0, ERROR_INVALID_HANDLE};
  const DWORD pid = GetProcessId(launch.hProcess);
  const DWORD error = pid ? ERROR_SUCCESS : GetLastError();
  CloseHandle(launch.hProcess);
  return {pid, error};
}
