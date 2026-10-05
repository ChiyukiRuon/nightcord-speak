import '../voice/browser_voice.dart';
import 'client_transport.dart';
import 'remote_transport.dart';
import 'socket_web.dart';
import 'device_store_web.dart';

ClientTransport createTransport() => RemoteTransport(
  socketFactory: BrowserSocket.new,
  voice: BrowserVoice(),
  deviceStore: BrowserDeviceStore(),
);
