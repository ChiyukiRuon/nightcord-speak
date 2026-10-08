// Regression: the bundled backend supplied only 7-10 fps on display 2, even
// before encoding. Exercise WGC directly, including stop and restart cleanup.
#include <atomic>
#include <chrono>
#include <cstdio>
#include <thread>
#include <future>
#include <windows.h>

#include "libwebrtc.h"
#include "rtc_video_track.h"
#include "wgc_screen_capturer.h"

using namespace libwebrtc;

// A small, unfocused animation makes fresh-frame checks independent of whether
// the user's video happens to be paused. It is destroyed after each cycle.
class Animation {
 public:
  explicit Animation(int display) {
    std::promise<HWND> ready;
    auto result = ready.get_future();
    worker_ = std::thread([display, promise = std::move(ready)]() mutable {
      DISPLAY_DEVICEW device{};
      device.cb = sizeof(device);
      DEVMODEW mode{};
      mode.dmSize = sizeof(mode);
      if (!EnumDisplayDevicesW(nullptr, display, &device, 0) ||
          !EnumDisplaySettingsW(device.DeviceName, ENUM_CURRENT_SETTINGS, &mode)) {
        promise.set_value(nullptr);
        return;
      }
      WNDCLASSW type{};
      type.lpfnWndProc = WindowProc;
      type.hInstance = GetModuleHandleW(nullptr);
      type.lpszClassName = L"NightcordCaptureRegression";
      RegisterClassW(&type);
      const auto window = CreateWindowExW(
          WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
          type.lpszClassName, L"Capture regression", WS_POPUP,
          mode.dmPosition.x + 80, mode.dmPosition.y + 80, 320, 180,
          nullptr, nullptr, type.hInstance, nullptr);
      promise.set_value(window);
      if (!window) return;
      ShowWindow(window, SW_SHOWNOACTIVATE);
      SetTimer(window, 1, 16, nullptr);
      MSG message{};
      while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    });
    window_ = result.get();
  }
  ~Animation() {
    if (window_) PostMessageW(window_, WM_CLOSE, 0, 0);
    if (worker_.joinable()) worker_.join();
  }
  bool valid() const { return window_ != nullptr; }

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message,
                                     WPARAM wparam, LPARAM lparam) {
    if (message == WM_TIMER) {
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        !GetWindowLongPtrW(window, GWLP_USERDATA));
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{};
      const auto dc = BeginPaint(window, &paint);
      const auto brush = CreateSolidBrush(
          GetWindowLongPtrW(window, GWLP_USERDATA) ? RGB(255, 0, 0) : RGB(0, 0, 255));
      FillRect(dc, &paint.rcPaint, brush);
      DeleteObject(brush);
      EndPaint(window, &paint);
      return 0;
    }
    if (message == WM_DESTROY) {
      PostQuitMessage(0);
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
  HWND window_ = nullptr;
  std::thread worker_;
};

class FrameCounter : public RTCVideoRenderer<scoped_refptr<RTCVideoFrame>> {
 public:
  void OnFrame(scoped_refptr<RTCVideoFrame> frame) override {
    width = frame->width();
    height = frame->height();
    if (frame->width() > 160 && frame->height() > 120) {
      const int luma = frame->DataY()[120 * frame->StrideY() + 160];
      const int u = frame->DataU()[60 * frame->StrideU() + 80];
      const int v = frame->DataV()[60 * frame->StrideV() + 80];
      if (std::abs(luma - 81) <= 4 && std::abs(u - 90) <= 4 &&
          std::abs(v - 240) <= 4) ++red_frames;
      if (std::abs(luma - 41) <= 4 && std::abs(u - 240) <= 4 &&
          std::abs(v - 110) <= 4) ++blue_frames;
      const int previous = previous_luma.exchange(luma);
      if (previous >= 0 && std::abs(luma - previous) > 8) ++changes;
    }
    ++frames;
  }
  std::atomic<int> frames{0};
  std::atomic<int> width{0};
  std::atomic<int> height{0};
  std::atomic<int> previous_luma{-1};
  std::atomic<int> changes{0};
  std::atomic<int> red_frames{0};
  std::atomic<int> blue_frames{0};
};

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  if (!LibWebRTC::Initialize()) return 1;
  auto factory = LibWebRTC::CreateRTCPeerConnectionFactory();
  if (!factory || !factory->Initialize()) return 1;
  auto constraints = RTCMediaConstraints::Create();
  for (int cycle = 0; cycle < 3; ++cycle) {
    Animation animation(cycle == 2 ? 0 : 1);
    if (!animation.valid()) return 1;
    auto source = factory->CreateCustomVideoSource("wgc-smoke", constraints);
    auto track = factory->CreateVideoTrack(source, "wgc-smoke-track");
    FrameCounter counter;
    track->AddRenderer(&counter);
    int stops = 0;
    auto capture = flutter_webrtc_plugin::CreateWgcScreenCapturer(
        cycle == 2 ? "0" : "1", 60, cycle != 1, source, [&] { ++stops; });
    if (!capture) {
      std::fprintf(stderr, "WGC start failed: cycle=%d\n", cycle);
      track->RemoveRenderer(&counter);
      return 1;
    }
    const int before = counter.frames;
    const auto fresh_before =
        flutter_webrtc_plugin::WgcFreshFrameCount(capture.get());
    std::this_thread::sleep_for(std::chrono::seconds(3));
    capture->StopCapture();
    const int delivered = counter.frames - before;
    const int stopped = counter.frames;
    capture->StopCapture();
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    const auto fresh =
        flutter_webrtc_plugin::WgcFreshFrameCount(capture.get()) - fresh_before;
    std::printf("cycle=%d frames=%d fps=%.1f fresh=%llu changes=%d red=%d blue=%d size=%dx%d stops=%d\n",
                cycle, delivered, delivered / 3.0,
                static_cast<unsigned long long>(fresh), counter.changes.load(),
                counter.red_frames.load(), counter.blue_frames.load(), counter.width.load(),
                counter.height.load(), stops);
    track->RemoveRenderer(&counter);
    if (delivered < 45 || counter.width <= 0 || counter.height <= 0 ||
        fresh < 45 || counter.changes < 45 || counter.red_frames < 5 ||
        counter.blue_frames < 5 || stops != 1 ||
        capture->CaptureStarted() || counter.frames != stopped) {
      return 1;
    }
  }
  auto source = factory->CreateCustomVideoSource("invalid-source", constraints);
  if (flutter_webrtc_plugin::CreateWgcScreenCapturer("invalid", 60, true, source) ||
      flutter_webrtc_plugin::CreateWgcScreenCapturer("999999", 60, true, source) ||
      flutter_webrtc_plugin::CreateWgcScreenCapturer("0", 0, true, source)) {
    return 1;
  }
  std::puts("PASS");
  return 0;
}
