import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/src/download_controller.dart';
import 'package:roadpulse_downloader/src/transport/logger_transport.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto-connects when one device is available', () async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport)..start();
    await _settle();
    expect(transport.connected, isTrue);
    expect(controller.phase, DownloadPhase.downloading);
    controller.dispose();
    await transport.dispose();
  });

  test('does not guess between multiple unknown serial devices', () async {
    final transport = FakeLoggerTransport(devices: const [
      LoggerDevice('COM1', 'Generic serial', 'COM1'),
      LoggerDevice('COM2', 'Another serial', 'COM2'),
    ]);
    final controller = DownloadController(transport: transport)..start();
    await _settle();
    expect(transport.connected, isFalse);
    expect(controller.selectedDevice, isNull);
    expect(controller.devices, hasLength(2));
    expect(controller.detail, contains('Disconnect other USB serial devices'));
    controller.dispose();
    await transport.dispose();
  });

  test('publishes incremental progress and a validated result', () async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport)..start();
    await _settle();
    final payload = validRpb(sequences: [7, 8]);
    final frame = framed(payload);
    transport.stream
        .add(Uint8List.fromList(frame.sublist(0, frame.length ~/ 2)));
    await _settle();
    expect(controller.phase, DownloadPhase.downloading);
    expect(controller.progress, greaterThan(0));
    transport.stream.add(Uint8List.fromList(frame.sublist(frame.length ~/ 2)));
    await _settle();
    expect(controller.phase, DownloadPhase.ready);
    expect(controller.info?.deviceId, 'RP-8FCBA4');
    expect(controller.info?.recordCount, 2);
    expect(controller.payload, payload);
    expect(transport.closed, isTrue);
    controller.dispose();
    await transport.dispose();
  });

  test('refuses a framed RPB whose checksum is corrupt', () async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport)..start();
    await _settle();
    final payload = validRpb()..[20] ^= 1;
    transport.stream.add(framed(payload));
    await _settle();
    expect(controller.phase, DownloadPhase.failed);
    expect(controller.payload, isNull);
    expect(controller.detail, contains('checksum'));
    controller.dispose();
    await transport.dispose();
  });

  test('reports a serial connection error', () async {
    final transport = FakeLoggerTransport()..connectError = StateError('busy');
    final controller = DownloadController(transport: transport)..start();
    await _settle();
    expect(controller.phase, DownloadPhase.failed);
    expect(controller.detail, contains('busy'));
    controller.dispose();
    await transport.dispose();
  });

  testWidgets('fails after 30 seconds without incoming bytes', (tester) async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport)..start();
    await tester.pump();
    expect(controller.phase, DownloadPhase.downloading);
    await tester.pump(const Duration(seconds: 30));
    expect(controller.phase, DownloadPhase.failed);
    expect(controller.detail, contains('stopped sending data'));
    controller.dispose();
    await transport.dispose();
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
