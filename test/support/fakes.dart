import 'dart:async';
import 'dart:typed_data';

import 'package:roadpulse_downloader/src/transport/logger_transport.dart';

final class FakeLoggerTransport implements LoggerTransport {
  FakeLoggerTransport({List<LoggerDevice>? devices})
      : listedDevices =
            devices ?? [const LoggerDevice('fake', 'RoadPulse CDC', 'fake')];
  List<LoggerDevice> listedDevices;
  final stream = StreamController<Uint8List>.broadcast();
  bool connected = false;
  bool closed = false;
  Object? connectError;
  bool get hasListener => stream.hasListener;

  @override
  Future<List<LoggerDevice>> devices() async => listedDevices;

  @override
  Future<LoggerConnection> connect(LoggerDevice device) async {
    if (connectError case final error?) throw error;
    connected = true;
    return FakeLoggerConnection(stream.stream, () => closed = true);
  }

  Future<void> dispose() => stream.close();
}

final class FakeLoggerConnection implements LoggerConnection {
  FakeLoggerConnection(this.bytes, this.onClose);
  @override
  final Stream<Uint8List> bytes;
  final void Function() onClose;
  @override
  Future<void> close() async => onClose();
}

Uint8List framed(List<int> payload) {
  const digits = '0123456789ABCDEF';
  final result = StringBuffer('RPB_HEX_BEGIN ${payload.length}\n');
  for (final byte in payload) {
    result
      ..write(digits[byte >> 4])
      ..write(digits[byte & 15]);
  }
  result.write('\nRPB_HEX_END\n');
  return Uint8List.fromList(result.toString().codeUnits);
}

Uint8List validRpb({
  int deviceId = 0x8fcba4,
  List<int> sequences = const [],
  List<DateTime>? recordDates,
  List<String> tags = const [],
}) {
  assert(recordDates == null || recordDates.length == sequences.length);
  final extensionSize = tags.isEmpty
      ? 0
      : 12 + tags.fold<int>(0, (size, tag) => size + 1 + tag.length);
  final headerSize = 64 + extensionSize;
  final manifestOffset = headerSize;
  final recordsOffset = manifestOffset + 16;
  final data = Uint8List(recordsOffset + sequences.length * 41);
  final view = ByteData.sublistView(data);
  view.setUint32(0, 0x48425052, Endian.little);
  view.setUint16(4, tags.isEmpty ? 1 : 2, Endian.little);
  view.setUint16(6, headerSize, Endian.little);
  view.setUint16(8, 1, Endian.little);
  view.setUint16(10, 41, Endian.little);
  view.setUint32(12, deviceId, Endian.little);
  data[47] = 1;
  if (tags.isNotEmpty) {
    view.setUint32(64, 0x53474154, Endian.little);
    view.setUint16(68, extensionSize, Endian.little);
    data[70] = tags.length;
    var offset = 72;
    for (final tag in tags) {
      data[offset++] = tag.length;
      data.setRange(offset, offset + tag.length, tag.codeUnits);
      offset += tag.length;
    }
    view.setUint32(
        headerSize - 4, crc32(data.sublist(64, headerSize - 4)), Endian.little);
  }
  view.setUint32(manifestOffset, sequences.length, Endian.little);
  if (sequences.isNotEmpty) {
    view.setUint32(manifestOffset + 4, sequences.first, Endian.little);
    view.setUint32(manifestOffset + 8, sequences.last, Endian.little);
    for (var index = 0; index < sequences.length; index++) {
      final offset = recordsOffset + index * 41;
      view.setUint32(offset, sequences[index], Endian.little);
      if (recordDates != null) {
        final days =
            recordDates[index].toUtc().difference(DateTime.utc(2020)).inDays;
        view.setUint16(offset + 4, days, Endian.little);
      }
    }
  }
  view.setUint32(60, crc32(data.sublist(0, 60)), Endian.little);
  view.setUint32(manifestOffset + 12,
      crc32(data.sublist(manifestOffset, manifestOffset + 12)), Endian.little);
  return data;
}

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
