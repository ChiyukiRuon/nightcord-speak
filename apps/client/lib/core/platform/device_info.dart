enum DeviceClass { mobile, desktop, unknown }

/// iPadOS can advertise itself as macOS; touch support disambiguates it.
DeviceClass browserDeviceClass({
  required String userAgent,
  required int maxTouchPoints,
}) {
  if (RegExp(
        r'Android|iPhone|iPad|iPod|Mobile',
        caseSensitive: false,
      ).hasMatch(userAgent) ||
      (userAgent.contains('Macintosh') && maxTouchPoints > 1)) {
    return DeviceClass.mobile;
  }
  if (RegExp(
    r'Windows NT|Macintosh|X11|CrOS',
    caseSensitive: false,
  ).hasMatch(userAgent)) {
    return DeviceClass.desktop;
  }
  return DeviceClass.unknown;
}
