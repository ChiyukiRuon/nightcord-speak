#ifndef RUNNER_UPDATE_LAUNCHER_H_
#define RUNNER_UPDATE_LAUNCHER_H_

#include <windows.h>
#include <string>

struct UpdateLaunchResult {
  DWORD pid;
  DWORD error;
};

// Used by both the Flutter runner and the console-free GUI regression probe.
UpdateLaunchResult LaunchUpdateHelper(const std::string& script,
                                     const std::string& configuration);

#endif  // RUNNER_UPDATE_LAUNCHER_H_
