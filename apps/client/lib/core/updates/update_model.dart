/// Version ordering follows the release tags, ignoring CI build numbers.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.numbers, this.stage, this.sequence);
  final List<int> numbers;
  final String? stage;
  final int sequence;

  static ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?(?:\+[0-9]+)?$',
    ).firstMatch(value);
    if (match == null) return null;
    return ReleaseVersion(
      [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)],
      match.group(4),
      int.parse(match.group(5) ?? '0'),
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final order = numbers[i].compareTo(other.numbers[i]);
      if (order != 0) return order;
    }
    const stages = ['alpha', 'beta', 'rc', null];
    final order = stages.indexOf(stage).compareTo(stages.indexOf(other.stage));
    return order != 0 ? order : sequence.compareTo(other.sequence);
  }
}

class DesktopUpdate {
  const DesktopUpdate(
    this.version,
    this.asset,
    this.manifest, {
    required this.platform,
    required this.arch,
    required this.fileName,
    required this.size,
    required this.installer,
  });
  final String version;
  final Uri asset;
  final Uri manifest;
  final String platform;
  final String arch;
  final String fileName;
  final int size;
  final bool installer;
}

class PreparedUpdate {
  const PreparedUpdate(this.update, this.directory, this.file, this.sha256);
  final DesktopUpdate update;
  final String directory;
  final String file;
  final String sha256;
}

class UpdateCancelled implements Exception {}

class UpdateInstallCancelled implements Exception {}

abstract class UpdateService {
  bool get available;
  Future<DesktopUpdate?> check();
  Future<PreparedUpdate> download(
    DesktopUpdate update,
    void Function(double) progress,
  );
  void cancelDownload();
  Future<void> install(PreparedUpdate update, String language);
}

bool isReleaseAssetUrl(Uri uri, String tag, String name) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    uri.query.isEmpty &&
    uri.fragment.isEmpty &&
    uri.path == '/ChiyukiRuon/nightcord-speak/releases/download/$tag/$name';

/// A platform-only patch must not advertise an update to the other platform.
DesktopUpdate? selectDesktopUpdate(
  List<dynamic> releases,
  String current,
  String platform, {
  String arch = 'x64',
  bool installer = true,
}) {
  final installed = ReleaseVersion.parse(current);
  if (installed == null) {
    throw const FormatException('Invalid installed version');
  }
  ReleaseVersion newest = installed;
  DesktopUpdate? result;
  for (final item in releases.whereType<Map<String, dynamic>>()) {
    if (item['draft'] != false) continue;
    final tag = item['tag_name'];
    if (tag is! String) continue;
    final version = ReleaseVersion.parse(tag);
    if (version == null || version.compareTo(newest) <= 0) continue;
    // GitHub also marks unsuffixed 0.x releases as prerelease; those are public builds.
    if (installed.stage == null && version.stage != null) continue;
    final assets = item['assets'];
    if (assets is! List) continue;
    final productVersion = tag.startsWith('v') ? tag.substring(1) : tag;
    final setup = platform == 'windows' && installer;
    final stem =
        'Nightcord-Speak-$productVersion-$platform-$arch${setup ? '-setup' : ''}';
    final name = '$stem.${setup ? 'exe' : 'zip'}';
    Map? artifact;
    Map? manifest;
    for (final asset in assets.whereType<Map>()) {
      if (asset['state'] != 'uploaded') continue;
      if (asset['name'] == name) artifact = asset;
      if (asset['name'] == '$stem.json') manifest = asset;
    }
    if (artifact == null || manifest == null) continue;
    final url = Uri.tryParse(
      artifact['browser_download_url']?.toString() ?? '',
    );
    final manifestUrl = Uri.tryParse(
      manifest['browser_download_url']?.toString() ?? '',
    );
    final size = artifact['size'];
    if (url == null ||
        manifestUrl == null ||
        size is! int ||
        size <= 0 ||
        size > 512 * 1024 * 1024 ||
        !isReleaseAssetUrl(url, tag, name) ||
        !isReleaseAssetUrl(manifestUrl, tag, '$stem.json')) {
      continue;
    }
    newest = version;
    result = DesktopUpdate(
      productVersion,
      url,
      manifestUrl,
      platform: platform,
      arch: arch,
      fileName: name,
      size: size,
      installer: setup,
    );
  }
  return result;
}
