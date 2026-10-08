// Runs against the real native plugin; mocked senders cannot expose SDK copies.
// Build with: flutter build windows --debug -t tool/screen_parameters_smoke.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = File('run/screen-parameters-smoke.json');
  output.parent.createSync(recursive: true);
  RTCPeerConnection? pc;
  var code = 1;
  try {
    pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
    final transceiver = await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
    );
    final audioTransceiver = await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
    );
    await pc.setLocalDescription(
      await pc.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      }),
    );
    final sender = (await pc.getSenders()).firstWhere(
      (sender) => sender.senderId == transceiver.sender.senderId,
    );
    final parameters = sender.parameters;
    final unchangedAccepted = await sender.setParameters(parameters);
    final encoding = parameters.encodings!.single;
    encoding.maxBitrate = 4000000;
    encoding.scaleResolutionDownBy = 2.0;
    encoding.maxFramerate = 30;
    final accepted = await sender.setParameters(parameters);
    // sender.parameters is a Dart cache. Re-enumeration reads the native SDK.
    final actual = (await pc.getSenders())
        .firstWhere((candidate) => candidate.senderId == sender.senderId)
        .parameters
        .encodings!
        .single;
    final audioSender = (await pc.getSenders()).firstWhere(
      (sender) => sender.senderId == audioTransceiver.sender.senderId,
    );
    final audioParameters = audioSender.parameters;
    audioParameters.encodings!.single.maxBitrate = 128000;
    final audioAccepted = await audioSender.setParameters(audioParameters);
    final actualAudio = (await pc.getSenders())
        .firstWhere((sender) => sender.senderId == audioSender.senderId)
        .parameters
        .encodings!
        .single;
    final passed =
        unchangedAccepted &&
        accepted &&
        audioAccepted &&
        actualAudio.maxBitrate == 128000 &&
        actual.maxBitrate == 4000000 &&
        actual.scaleResolutionDownBy == 2.0 &&
        actual.maxFramerate == 30;
    output.writeAsStringSync(
      jsonEncode({
        'passed': passed,
        'accepted': accepted,
        'unchangedAccepted': unchangedAccepted,
        'audioAccepted': audioAccepted,
        'nativeAudioMaxBitrate': actualAudio.maxBitrate,
        'nativeMaxBitrate': actual.maxBitrate,
        'nativeScale': actual.scaleResolutionDownBy,
        'nativeMaxFramerate': actual.maxFramerate,
      }),
    );
    code = passed ? 0 : 1;
  } catch (error) {
    output.writeAsStringSync(jsonEncode({'passed': false, 'error': '$error'}));
  } finally {
    await pc?.close();
    await pc?.dispose();
  }
  exit(code);
}
