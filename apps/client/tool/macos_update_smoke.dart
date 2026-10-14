import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:nightcord_client/core/updates/update_service.dart';
import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/util/app_exit.dart';

// 单独构建此入口，仅更新包含 fixture.zip 的临时应用。
// 测试使用真实核心、平台通道和更新助手。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final root = await Directory.systemTemp.createTemp('nightcord-flow-smoke-');
  stdout.writeln('SMOKE_ROOT=${root.path}');
  await stdout.flush();
  final client = RustClient.start();
  stdout.writeln('SMOKE_LOG_DIR=${coreLogDirectory()}');
  await stdout.flush();
  await registerMainWindowExit(() {
    client.dispose();
    File('${root.path}/core-shutdown').writeAsStringSync('ok', flush: true);
  });
  final bundle = File(Platform.resolvedExecutable).parent.parent.parent;
  final fixture = File('${bundle.path}/Contents/Resources/fixture.zip');
  final package = await fixture.copy('${root.path}/update.zip');
  final digest = (await sha256.bind(package.openRead()).first).toString();
  final update = DesktopUpdate(
    '0.4.1',
    Uri.file(package.path),
    Uri.file(package.path),
    platform: 'macos',
    arch: 'arm64',
    fileName: 'update.zip',
    size: await package.length(),
    installer: false,
  );
  await NativeUpdateService().install(
    PreparedUpdate(update, root.path, package.path, digest),
    'en',
  );
  await exitForUpdate();
}
