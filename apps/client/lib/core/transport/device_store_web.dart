import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'device_store.dart';

/// Browser profiles and origins are the device boundary; no fingerprinting.
class BrowserDeviceStore implements DeviceStore {
  final _memory = MemoryDeviceStore();
  String _key(Uri gateway) => 'nightcord.device.${gateway.toString()}';
  @override
  String load(Uri gateway) {
    try {
      final saved = web.window.localStorage.getItem(_key(gateway));
      if (saved != null &&
          RegExp(r'^[0-9a-f]{32}\.[0-9a-f]{32}$').hasMatch(saved)) {
        return saved;
      }
    } catch (_) {
      // Restricted browser storage degrades to this page's memory.
    }
    final cached = _memory.load(gateway);
    if (cached != null) return cached;
    // getRandomValues also works on LAN HTTP; randomUUID requires HTTPS.
    // Save before opening the socket so another tab can reuse the device.
    final bytes = Uint8List(32);
    web.window.crypto.getRandomValues(bytes.toJS);
    String part(int start) => bytes
        .sublist(start, start + 16)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final credential = '${part(0)}.${part(16)}';
    save(gateway, credential);
    return credential;
  }

  @override
  void save(Uri gateway, String credential) {
    _memory.save(gateway, credential);
    try {
      web.window.localStorage.setItem(_key(gateway), credential);
    } catch (_) {}
  }
}
