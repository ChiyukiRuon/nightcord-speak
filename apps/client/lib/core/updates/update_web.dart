import 'update_model.dart';

UpdateService createUpdateService() => UnsupportedUpdateService();

class UnsupportedUpdateService implements UpdateService {
  @override
  bool get available => false;
  @override
  Future<DesktopUpdate?> check() async => null;
  @override
  Future<void> open(DesktopUpdate update) async {}
}
