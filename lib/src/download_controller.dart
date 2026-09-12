import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'protocol/rpb_validator.dart';
import 'protocol/usb_frame_parser.dart';
import 'transport/logger_transport.dart';

enum DownloadPhase { waiting, connecting, downloading, ready, failed }

final class DownloadController extends ChangeNotifier {
  DownloadController({LoggerTransport? transport})
      : _transport = transport ?? LoggerTransport.forCurrentPlatform();
  final LoggerTransport _transport;
  Timer? _scanTimer;
  Timer? _inactivityTimer;
  StreamSubscription<Uint8List>? _subscription;
  LoggerConnection? _connection;
  UsbFrameParser? _parser;
  bool _scanning = false;

  DownloadPhase phase = DownloadPhase.waiting;
  String status = 'Open this app, then plug in the RoadPulse logger.';
  String detail = 'Waiting for logger…';
  List<LoggerDevice> devices = const [];
  LoggerDevice? selectedDevice;
  Uint8List? payload;
  RpbInfo? info;
  double progress = 0;

  void start() {
    refreshDevices();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) => refreshDevices());
  }

  Future<void> refreshDevices() async {
    if (_scanning || phase == DownloadPhase.downloading || phase == DownloadPhase.connecting) return;
    _scanning = true;
    try {
      final found = await _transport.devices();
      devices = found;
      if (selectedDevice == null || !found.any((d) => d.id == selectedDevice!.id)) {
        selectedDevice = _preferred(found);
      }
      notifyListeners();
      if (phase == DownloadPhase.waiting && selectedDevice != null) await connect();
    } finally {
      _scanning = false;
    }
  }

  LoggerDevice? _preferred(List<LoggerDevice> found) {
    if (found.isEmpty) return null;
    final likely = found.where((d) {
      final text = '${d.id} ${d.label}'.toLowerCase();
      return text.contains('usbmodem') || text.contains('roadpulse') || text.contains('cdc');
    }).toList();
    if (likely.length == 1) return likely.single;
    return found.length == 1 ? found.single : null;
  }

  void selectDevice(LoggerDevice? device) { selectedDevice = device; notifyListeners(); }

  Future<void> connect() async {
    final device = selectedDevice;
    if (device == null) return;
    await _closeConnection();
    payload = null; info = null; progress = 0;
    phase = DownloadPhase.connecting;
    status = 'Logger connected'; detail = 'Preparing download…'; notifyListeners();
    try {
      _parser = UsbFrameParser();
      _connection = await _transport.connect(device);
      phase = DownloadPhase.downloading;
      detail = 'Downloading retained records…'; notifyListeners();
      _resetInactivityTimer();
      _subscription = _connection!.bytes.listen(_onBytes, onError: _fail, onDone: () {
        if (phase == DownloadPhase.downloading) _fail('The logger disconnected before the export completed.');
      });
    } catch (error) { _fail(error); }
  }

  void _onBytes(Uint8List bytes) {
    _resetInactivityTimer();
    try {
      final result = _parser!.append(bytes);
      final expected = _parser!.expectedPayloadBytes;
      if (expected != null && expected > 0) {
        progress = _parser!.receivedPayloadBytes / expected;
        detail = 'Downloading: ${(_parser!.receivedPayloadBytes / 1000).toStringAsFixed(1)} of '
            '${(expected / 1000).toStringAsFixed(1)} KB (${(progress * 100).toStringAsFixed(1)}%)';
      }
      if (result != null) {
        final validated = RpbValidator.validate(result);
        payload = result; info = validated; progress = 1;
        phase = DownloadPhase.ready; status = 'Download ready';
        detail = '${(result.length / 1000).toStringAsFixed(1)} KB received. Flash was not changed.';
        _inactivityTimer?.cancel(); _closeConnection();
      }
      notifyListeners();
    } catch (error) { _fail(error); }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 30), () =>
      _fail('The logger stopped sending data before the export completed.'));
  }

  void _fail(Object error) {
    if (phase == DownloadPhase.failed) return;
    _inactivityTimer?.cancel(); _closeConnection();
    phase = DownloadPhase.failed; status = 'Download failed';
    detail = '$error Unplug and reconnect the logger.'; notifyListeners();
  }

  void reset() {
    _closeConnection(); payload = null; info = null; progress = 0;
    phase = DownloadPhase.waiting; status = 'Waiting for logger';
    detail = 'Plug in a RoadPulse logger to start a new download.'; notifyListeners();
  }

  Future<void> _closeConnection() async {
    await _subscription?.cancel(); _subscription = null;
    await _connection?.close(); _connection = null;
  }

  @override
  void dispose() { _scanTimer?.cancel(); _inactivityTimer?.cancel(); _closeConnection(); super.dispose(); }
}
