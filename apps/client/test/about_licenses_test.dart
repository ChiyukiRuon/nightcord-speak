import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/features/settings/sections/about_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled notices cover the native core and fonts, without duplicate registration', () async {
    await loadBundledLicenses();
    await loadBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final protocol = entries.where((e) => e.packages.any((p) => p.startsWith('tsclientlib ')));
    expect(protocol, hasLength(1));
    expect(protocol.single.paragraphs.map((p) => p.text).join('\n'), contains('Apache'));
    expect(entries.any((e) => e.packages.any((p) => p.startsWith('audiopus_sys '))), isTrue);
    expect(entries.any((e) => e.packages.contains('Noto Sans / Noto Sans CJK')), isTrue);
    expect(entries.any((e) => e.packages.contains('Nightcord Speak')), isTrue);
  });
}
