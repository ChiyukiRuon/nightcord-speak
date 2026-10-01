// The address book: servers the user has saved (§40).
//
// The shape mirrors `ts_settings::BookmarkList` field for field, because this is
// what goes over the FFI as JSON — with one deviation, noted on [Bookmark.port]:
// a missing port has to mean the default rather than making the entry
// unreadable, since a hand-edited file is a supported way to use this.

import 'domain.dart';

/// One server the user has saved.
class Bookmark {
  const Bookmark({
    this.name = '',
    this.host = '',
    this.port = 9987,
    this.nickname,
    this.protocol = ProtocolKind.ts3,
    this.serverPassword,
  });

  /// What the user calls this entry.
  final String name;

  /// Host, without the port. The core normalises whatever was typed, so a
  /// pasted `ts3://example.com` never lands here with its scheme attached.
  final String host;

  final int port;

  /// Nickname to use here, or null to take the one from the settings.
  ///
  /// Null is what makes a change to the default nickname reach the servers the
  /// user had not overridden — which is what a default is for.
  final String? nickname;

  final ProtocolKind protocol;

  /// The server's own password, if it has one.
  final String? serverPassword;

  /// The address to hand to a connection.
  String get address => '$host:$port';

  /// What to show when the user has not named it.
  String get displayName => name.trim().isEmpty ? host : name;

  Bookmark copyWith({
    String? name,
    String? host,
    int? port,
    String? nickname,
    bool clearNickname = false,
    ProtocolKind? protocol,
    String? serverPassword,
    bool clearServerPassword = false,
  }) => Bookmark(
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    nickname: clearNickname ? null : (nickname ?? this.nickname),
    protocol: protocol ?? this.protocol,
    serverPassword: clearServerPassword ? null : (serverPassword ?? this.serverPassword),
  );

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    // A hand-written entry that omits the port gets the default rather than
    // making the whole file unreadable — the struct this replaced had no
    // default, and one missing line cost the entire address book.
    port: json['port'] as int? ?? 9987,
    nickname: json['nickname'] as String?,
    protocol: ProtocolKind.fromWire(json['protocol'] as String?),
    serverPassword: json['server_password'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'port': port,
    'nickname': nickname,
    'protocol': protocol.wire,
    'server_password': serverPassword,
  };
}

/// What the connect screen collects, before the core parses the address.
///
/// Deliberately not a [Bookmark]: the address here is whatever the user typed,
/// including a scheme or a port, and the core turns it into the stored form.
class NewBookmark {
  const NewBookmark({
    this.name = '',
    required this.address,
    this.nickname,
    this.protocol = ProtocolKind.ts3,
    this.serverPassword,
    this.replaces,
  });

  /// What the user calls it. Empty falls back to the host.
  final String name;

  /// Whatever was typed. The core parses it, so `host`, `host:port` and
  /// `ts3://host` all mean the same thing here as they do on the connect
  /// screen — this front-end never has to agree with the core about syntax.
  final String address;

  final String? nickname;
  final ProtocolKind protocol;
  final String? serverPassword;

  /// The address of an entry this one supersedes, when editing rather than
  /// adding.
  ///
  /// An address is an entry's *identity* — saving replaces the row with the
  /// same host and port — so changing the address is not an update at all
  /// unless the core is told which row to drop.
  final String? replaces;

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'nickname': nickname,
    'protocol': protocol.wire,
    'server_password': serverPassword,
    'replaces': replaces,
  };
}

/// The saved servers, as the core stores them.
class BookmarkList {
  const BookmarkList({this.version = 1, this.bookmarks = const []});

  /// Format version. The core refuses one it does not know.
  final int version;

  final List<Bookmark> bookmarks;

  factory BookmarkList.fromJson(Map<String, dynamic> json) {
    final raw = json['bookmarks'];
    return BookmarkList(
      version: json['version'] as int? ?? 1,
      bookmarks: raw is List
          ? raw
                .whereType<Map>()
                .map((entry) => Bookmark.fromJson(entry.cast<String, dynamic>()))
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'bookmarks': bookmarks.map((server) => server.toJson()).toList(growable: false),
  };

  /// Adds an entry, replacing any that points at the same address.
  ///
  /// Matching on the address rather than the name: the name is a label the user
  /// is free to change, and two entries for one server is how a list quietly
  /// fills with duplicates.
  BookmarkList upsert(Bookmark bookmark) {
    final next = [...bookmarks];
    final at = next.indexWhere((s) => s.host == bookmark.host && s.port == bookmark.port);
    if (at >= 0) {
      next[at] = bookmark;
    } else {
      next.add(bookmark);
    }
    return BookmarkList(version: version, bookmarks: next);
  }

  /// Removes the entry at [index], if there is one.
  BookmarkList removeAt(int index) {
    if (index < 0 || index >= bookmarks.length) return this;
    final next = [...bookmarks]..removeAt(index);
    return BookmarkList(version: version, bookmarks: next);
  }

  /// Replaces the entry at [index], if there is one.
  BookmarkList replaceAt(int index, Bookmark bookmark) {
    if (index < 0 || index >= bookmarks.length) return this;
    final next = [...bookmarks]..[index] = bookmark;
    return BookmarkList(version: version, bookmarks: next);
  }
}
