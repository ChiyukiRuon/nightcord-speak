import '../../ffi/rust_client.dart';
import 'client_transport.dart';

ClientTransport createTransport() => RustClient.start();
