#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "update_launcher.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "nightcord/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "startUpdateHelper") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!arguments) {
            result->Error("invalid_arguments", "Missing update helper paths");
            return;
          }
          const auto script = arguments->find(flutter::EncodableValue("script"));
          const auto configuration = arguments->find(flutter::EncodableValue("configuration"));
          if (script == arguments->end() || configuration == arguments->end() ||
              !std::holds_alternative<std::string>(script->second) ||
              !std::holds_alternative<std::string>(configuration->second)) {
            result->Error("invalid_arguments", "Invalid update helper paths");
            return;
          }
          const auto launched = LaunchUpdateHelper(
              std::get<std::string>(script->second),
              std::get<std::string>(configuration->second));
          if (launched.error != ERROR_SUCCESS) {
            result->Error("launch_failed", "Windows update helper launch failed; win32=" +
                          std::to_string(launched.error));
            return;
          }
          result->Success(flutter::EncodableValue(static_cast<int64_t>(launched.pid)));
          return;
        }
        if (call.method_name() != "quitForUpdate") {
          result->NotImplemented();
          return;
        }
        // Route update exit through the main window's normal Dart cleanup.
        if (!PostMessage(GetHandle(), WM_CLOSE, 0, 0)) {
          result->Error("close_failed", "Could not request application exit");
          return;
        }
        result->Success();
      });
  // A window opened by `desktop_multi_window` gets its own engine, and a fresh
  // engine has no plugins until somebody registers them. This builds the app's
  // plugin list into the new one, so `flutter_webrtc` works there too - which
  // the detached screen-share window needs, because a texture belongs to the
  // engine that made it and it cannot borrow the main window's picture.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  lifecycle_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
