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
  const DesktopUpdate(this.version, this.page);
  final String version;
  final Uri page;
}

abstract class UpdateService {
  bool get available;
  Future<DesktopUpdate?> check();
  Future<void> open(DesktopUpdate update);
}

/// A platform-only patch must not advertise an update to the other platform.
DesktopUpdate? selectDesktopUpdate(
  List<dynamic> releases,
  String current,
  String platform,
) {
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
    final names = platform == 'windows'
        ? [
            'Nightcord-Speak-$productVersion-windows-x64-setup.exe',
            'Nightcord-Speak-$productVersion-windows-x64.zip',
          ]
        : [
            'Nightcord-Speak-$productVersion-macos-arm64.zip',
            'Nightcord-Speak-$productVersion-macos-x64.zip',
          ];
    if (!assets.whereType<Map>().any(
      (asset) => names.contains(asset['name']) && asset['state'] == 'uploaded',
    )) {
      continue;
    }
    final page = Uri.parse(
      'https://github.com/ChiyukiRuon/nightcord-speak/releases/tag/$tag',
    );
    newest = version;
    result = DesktopUpdate(productVersion, page);
  }
  return result;
}
