import 'dart:typed_data';

final class RpbValidationException implements Exception {
  const RpbValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class RpbInfo {
  const RpbInfo({
    required this.deviceId,
    required this.recordCount,
    this.earliestRecordDate,
    this.latestRecordDate,
  });
  final String deviceId;
  final int recordCount;
  final DateTime? earliestRecordDate;
  final DateTime? latestRecordDate;
}

abstract final class RpbValidator {
  static const headerSize = 64;
  static const manifestSize = 16;
  static const recordSize = 41;
  static const headerMagic = 0x48425052;

  static RpbInfo validate(Uint8List data) {
    if (data.length < headerSize + manifestSize) {
      throw const RpbValidationException('The RPB file is truncated.');
    }
    final view = ByteData.sublistView(data);
    if (view.getUint32(0, Endian.little) != headerMagic ||
        view.getUint16(6, Endian.little) != headerSize ||
        view.getUint16(10, Endian.little) != recordSize ||
        data[47] != 1) {
      throw const RpbValidationException('The RPB header is unsupported.');
    }
    if (_crc32(data.sublist(0, 60)) != view.getUint32(60, Endian.little)) {
      throw const RpbValidationException('The RPB header checksum is invalid.');
    }
    final count = view.getUint32(64, Endian.little);
    final expected = headerSize + manifestSize + count * recordSize;
    if (data.length != expected) {
      throw RpbValidationException(
          'Invalid RPB length: expected $expected, got ${data.length}.');
    }
    if (_crc32(data.sublist(64, 76)) != view.getUint32(76, Endian.little)) {
      throw const RpbValidationException(
          'The RPB manifest checksum is invalid.');
    }
    DateTime? earliestRecordDate;
    DateTime? latestRecordDate;
    if (count > 0) {
      final first = view.getUint32(80, Endian.little);
      final last = view.getUint32(80 + (count - 1) * recordSize, Endian.little);
      if (first != view.getUint32(68, Endian.little) ||
          last != view.getUint32(72, Endian.little)) {
        throw const RpbValidationException(
            'Manifest sequence bounds do not match the records.');
      }
      final epoch = DateTime.utc(2020);
      for (var index = 0; index < count; index++) {
        final offset = 80 + index * recordSize;
        final date = epoch
            .add(Duration(days: view.getUint16(offset + 4, Endian.little)));
        if (earliestRecordDate == null || date.isBefore(earliestRecordDate)) {
          earliestRecordDate = date;
        }
        if (latestRecordDate == null || date.isAfter(latestRecordDate)) {
          latestRecordDate = date;
        }
      }
    }
    final id = view
        .getUint32(12, Endian.little)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(6, '0');
    return RpbInfo(
      deviceId: 'RP-$id',
      recordCount: count,
      earliestRecordDate: earliestRecordDate,
      latestRecordDate: latestRecordDate,
    );
  }

  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
