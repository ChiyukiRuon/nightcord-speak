import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services.dart';
import 'device_info.dart';

final deviceClassProvider = Provider<DeviceClass>(
  (ref) => platformDeviceClass(),
);

/// Browser logs live on the gateway host and cannot be configured locally.
final logSettingsAvailableProvider = Provider<bool>(
  (ref) => supportsLogSettings,
);
