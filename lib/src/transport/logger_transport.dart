import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:usb_serial/usb_serial.dart';

final class LoggerDevice {
  const LoggerDevice(this.id, this.label, this.nativeDevice);
  final String id;
  final String label;
  final Object nativeDevice;
}

abstract interface class LoggerConnection {
  Stream<Uint8List> get bytes;
  Future<void> close();
}

abstract interface class LoggerTransport {
  Future<List<LoggerDevice>> devices();
  Future<LoggerConnection> connect(LoggerDevice device);

  factory LoggerTransport.forCurrentPlatform() => Platform.isAndroid
      ? AndroidLoggerTransport()
      : Platform.isMacOS || Platform.isWindows
          ? DesktopLoggerTransport()
          : UnsupportedLoggerTransport();
}

final class UnsupportedLoggerTransport implements LoggerTransport {
  @override
  Future<List<LoggerDevice>> devices() async => const [];

  @override
  Future<LoggerConnection> connect(LoggerDevice device) {
    throw UnsupportedError(
        'Direct USB serial access is unavailable on this platform.');
  }
}

final class DesktopLoggerTransport implements LoggerTransport {
  @override
  Future<List<LoggerDevice>> devices() async {
    return SerialPort.availablePorts.map((address) {
      final port = SerialPort(address);
      try {
        final details = [port.description, port.manufacturer]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join(' — ');
        return LoggerDevice(address,
            details.isEmpty ? address : '$address — $details', address);
      } finally {
        port.dispose();
      }
    }).toList();
  }

  @override
  Future<LoggerConnection> connect(LoggerDevice device) async {
    final port = SerialPort(device.nativeDevice as String);
    if (!port.openReadWrite()) {
      final message =
          SerialPort.lastError?.message ?? 'Unknown serial-port error';
      port.dispose();
      throw StateError('Could not open ${device.id}: $message');
    }
    final config = port.config;
    config.baudRate = 115200;
    config.bits = 8;
    config.stopBits = 1;
    config.parity = SerialPortParity.none;
    config.setFlowControl(SerialPortFlowControl.none);
    port.config = config;
    // SerialPort retains this configuration and disposes it with the port.
    // Disposing it here causes a second sp_free_config when a completed
    // download closes the connection, which aborts the macOS process.
    return _DesktopConnection(port);
  }
}

final class _DesktopConnection implements LoggerConnection {
  _DesktopConnection(this._port) : _reader = SerialPortReader(_port);
  final SerialPort _port;
  final SerialPortReader _reader;
  @override
  Stream<Uint8List> get bytes => _reader.stream;
  @override
  Future<void> close() async {
    _reader.close();
    _port.close();
    _port.dispose();
  }
}

final class AndroidLoggerTransport implements LoggerTransport {
  @override
  Future<List<LoggerDevice>> devices() async {
    final devices = await UsbSerial.listDevices();
    return devices
        .map((device) => LoggerDevice(
              '${device.vid ?? 0}:${device.pid ?? 0}:${device.deviceId}',
              [
                device.productName,
                device.manufacturerName,
                'USB ${device.deviceId}'
              ]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' — '),
              device,
            ))
        .toList();
  }

  @override
  Future<LoggerConnection> connect(LoggerDevice device) async {
    final usbDevice = device.nativeDevice as UsbDevice;
    final port = await usbDevice.create();
    if (port == null || !await port.open()) {
      throw StateError(
          'USB permission was denied or the logger could not be opened.');
    }
    await port.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
    await port.setDTR(false);
    await port.setRTS(false);
    return _AndroidConnection(port);
  }
}

final class _AndroidConnection implements LoggerConnection {
  _AndroidConnection(this._port);
  final UsbPort _port;
  @override
  Stream<Uint8List> get bytes => _port.inputStream!;
  @override
  Future<void> close() => _port.close();
}
