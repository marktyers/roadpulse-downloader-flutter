import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/src/download_controller.dart';
import 'package:roadpulse_downloader/src/transport/logger_transport.dart';
import 'package:roadpulse_downloader/src/ui/downloader_page.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('fits the complete workflow in the compact desktop window',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport);
    await _pumpConnected(tester, controller, transport);
    transport.stream.add(framed(validRpb()));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Create email'), findsOneWidget);
    await _dispose(tester, controller, transport);
  });

  testWidgets('shows the waiting state with no USB device', (tester) async {
    final transport = FakeLoggerTransport(devices: const []);
    final controller = DownloadController(transport: transport);
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.text('Plug in RoadPulse Logger'), findsOneWidget);
    expect(find.textContaining('Read-only download'), findsOneWidget);
    await _dispose(tester, controller, transport);
  });

  testWidgets('keeps serial-port details hidden when discovery is ambiguous',
      (tester) async {
    final transport = FakeLoggerTransport(devices: const [
      LoggerDevice('COM1', 'Generic serial', 'COM1'),
      LoggerDevice('COM2', 'Debug adapter', 'COM2'),
    ]);
    final controller = DownloadController(transport: transport);
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<LoggerDevice>), findsNothing);
    expect(find.textContaining('Disconnect other USB serial devices'),
        findsOneWidget);
    expect(transport.connected, isFalse);
    await _dispose(tester, controller, transport);
  });

  testWidgets('shows determinate progress while bytes arrive', (tester) async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport);
    await _pumpConnected(tester, controller, transport);
    final frame = framed(validRpb());
    transport.stream
        .add(Uint8List.fromList(frame.sublist(0, frame.length ~/ 2)));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Downloading retained records…'), findsOneWidget);
    expect(find.textContaining('Downloading:'), findsOneWidget);
    await _dispose(tester, controller, transport);
  });

  testWidgets('defaults desktop delivery to email and can toggle local save',
      (tester) async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport);
    await _pumpConnected(tester, controller, transport);
    transport.stream.add(framed(validRpb(
      sequences: [100, 101],
      recordDates: [DateTime.utc(2026, 6, 23), DateTime.utc(2026, 8, 18)],
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text('Download ready'), findsOneWidget);
    expect(find.text('Download complete'), findsOneWidget);
    expect(find.text('23 June 2026 – 18 August 2026'), findsOneWidget);
    expect(find.text('Send email'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Recording dates'), findsOneWidget);
    expect(find.text('23 June 2026 – 18 August 2026'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Save locally'), findsOneWidget);
    expect(find.text('Create email'), findsOneWidget);
    await tester.tap(find.text('Save locally'));
    await tester.pump();
    expect(find.text('Save RPB'), findsOneWidget);
    await tester.tap(find.text('Email'));
    await tester.pump();
    expect(find.text('Create email'), findsOneWidget);
    await _dispose(tester, controller, transport);
  });

  testWidgets('never enables delivery for a corrupt RPB', (tester) async {
    final transport = FakeLoggerTransport();
    final controller = DownloadController(transport: transport);
    await _pumpConnected(tester, controller, transport);
    final corrupt = validRpb()..[25] ^= 1;
    transport.stream.add(framed(corrupt));
    await tester.pump();
    expect(find.text('Download failed'), findsOneWidget);
    expect(find.text('Create email'), findsNothing);
    expect(find.text('Save RPB'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await _dispose(tester, controller, transport);
  });
}

Widget _app(DownloadController controller) =>
    MaterialApp(home: DownloaderPage(controller: controller));

Future<void> _pumpConnected(WidgetTester tester, DownloadController controller,
    FakeLoggerTransport transport) async {
  await tester.pumpWidget(_app(controller));
  for (var attempt = 0; attempt < 10 && !transport.hasListener; attempt++) {
    await tester.pump();
  }
  expect(transport.connected, isTrue);
  expect(transport.hasListener, isTrue);
}

Future<void> _dispose(WidgetTester tester, DownloadController controller,
    FakeLoggerTransport transport) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await transport.dispose();
}
