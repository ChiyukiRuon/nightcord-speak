import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/platform/device_info.dart';

void main() {
  test('browser device information recognizes mobile and desktop systems', () {
    for (final agent in [
      'Mozilla/5.0 (Linux; Android 16; Tablet)',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X)',
      'Mozilla/5.0 (iPad; CPU OS 19_0 like Mac OS X)',
    ]) {
      expect(
        browserDeviceClass(userAgent: agent, maxTouchPoints: 5),
        DeviceClass.mobile,
      );
    }
    for (final agent in [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      'Mozilla/5.0 (X11; Linux x86_64)',
      'Mozilla/5.0 (X11; CrOS x86_64)',
    ]) {
      expect(
        browserDeviceClass(userAgent: agent, maxTouchPoints: 0),
        DeviceClass.desktop,
      );
    }
    // Windows touchscreens are desktop devices, while iPadOS masks its OS.
    expect(
      browserDeviceClass(userAgent: 'Windows NT 10.0', maxTouchPoints: 10),
      DeviceClass.desktop,
    );
    expect(
      browserDeviceClass(userAgent: 'Macintosh', maxTouchPoints: 5),
      DeviceClass.mobile,
    );
    expect(
      browserDeviceClass(userAgent: 'unrecognized browser', maxTouchPoints: 0),
      DeviceClass.unknown,
    );
  });
}
