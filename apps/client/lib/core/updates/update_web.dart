import 'update_model.dart';

UpdateService createUpdateService() => UnsupportedUpdateService();

class UnsupportedUpdateService implements UpdateService {
  @override
  bool get available => false;
  @override
  Future<DesktopUpdate?> check() async => null;
  @override
  Future<PreparedUpdate> download(
    DesktopUpdate update,
    void Function(double) progress,
  ) => Future.error(UnsupportedError('Desktop updates unavailable'));
  @override
  void cancelDownload() {}
  @override
  Future<void> install(PreparedUpdate update, String language) =>
      Future.error(UnsupportedError('Desktop updates unavailable'));
}
