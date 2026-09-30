// Everything needed to open a connection.
//
// Here rather than in `ffi/`: the request is domain vocabulary — a bookmark
// and the settings together decide what it holds — and the transport seam
// (`core/transport/client_transport.dart`) must not name an FFI type.

import 'bookmarks.dart';
import 'domain.dart';
import 'settings.dart';

/// Everything needed to open a connection.
///
/// Mirrors `ts_core::ConnectRequest`. The identity is deliberately absent: the
/// core owns it, loads it from disk, and never hands key material out (§31).
class ConnectRequest {
  const ConnectRequest({
    required this.address,
    required this.nickname,
    this.profile = 'default',
    this.serverPassword,
    this.channelPassword,
    this.privilegeKey,
    this.defaultChannel,
    this.protocol = ProtocolKind.ts3,
  });

  /// `host`, `host:port`, `ts3://host` or `[::1]:9987`.
  final String address;

  final String nickname;

  /// Identity profile. The same profile presents the same client to every
  /// server, which is what a user expects of "their" identity.
  final String profile;

  final String? serverPassword;
  final String? channelPassword;
  final String? privilegeKey;
  final String? defaultChannel;
  final ProtocolKind protocol;

  /// Builds a request from a saved server, filling the gaps from the settings.
  ///
  /// **This is the only definition of that rule.** A bookmark wins where it has
  /// an opinion — the address, and a nickname it was saved with — and the
  /// settings supply the rest. Both places that connect from a bookmark go
  /// through here, because two copies of "which one wins" is exactly how they
  /// end up disagreeing.
  factory ConnectRequest.fromBookmark(Bookmark bookmark, Settings settings) => ConnectRequest(
    address: bookmark.address,
    nickname: bookmark.nickname ?? settings.connection.nickname,
    profile: settings.connection.profile,
    serverPassword: bookmark.serverPassword,
    protocol: bookmark.protocol,
  );

  Map<String, dynamic> toJson() => {
    'address': address,
    'nickname': nickname,
    'profile': profile,
    if (serverPassword != null && serverPassword!.isNotEmpty)
      'server_password': serverPassword,
    if (channelPassword != null && channelPassword!.isNotEmpty)
      'channel_password': channelPassword,
    if (privilegeKey != null && privilegeKey!.isNotEmpty) 'privilege_key': privilegeKey,
    if (defaultChannel != null && defaultChannel!.isNotEmpty)
      'default_channel': defaultChannel,
    'protocol': protocol.wire,
  };
}
