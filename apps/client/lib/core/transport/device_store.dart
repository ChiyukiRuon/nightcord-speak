/// An opaque gateway credential, distinct from the TeamSpeak private key.
abstract interface class DeviceStore {
  String? load(Uri gateway);
  void save(Uri gateway, String credential);
}

/// Non-browser remote transports can supply their own durable store.
class MemoryDeviceStore implements DeviceStore {
  final _credentials = <String, String>{};
  @override
  String? load(Uri gateway) => _credentials[gateway.toString()];
  @override
  void save(Uri gateway, String credential) =>
      _credentials[gateway.toString()] = credential;
}
