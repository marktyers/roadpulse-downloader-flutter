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
  static const baseHeaderSize = 64;
  static const manifestSize = 16;
  static const recordSize = 41;
  static const headerMagic = 0x48425052;
  static const tagsMagic = 0x53474154;

  static RpbInfo validate(Uint8List data) {
    if (data.length < baseHeaderSize + manifestSize) {
      throw const RpbValidationException('The RPB file is truncated.');
    }
    final view = ByteData.sublistView(data);
    final version = view.getUint16(4, Endian.little);
    final headerSize = view.getUint16(6, Endian.little);
    if (view.getUint32(0, Endian.little) != headerMagic ||
        view.getUint16(10, Endian.little) != recordSize ||
        data[47] != 1 ||
        !((version == 1 && headerSize == baseHeaderSize) ||
            (version == 2 && headerSize >= baseHeaderSize + 12))) {
      throw const RpbValidationException('The RPB header is unsupported.');
    }
    if (_crc32(data.sublist(0, 60)) != view.getUint32(60, Endian.little)) {
      throw const RpbValidationException('The RPB header checksum is invalid.');
    }
    if (data.length < headerSize + manifestSize) {
      throw const RpbValidationException('The RPB file is truncated.');
    }
    if (version == 2) {
      _validateTagsExtension(data, view, headerSize);
    }
    final manifestOffset = headerSize;
    final recordsOffset = manifestOffset + manifestSize;
    final count = view.getUint32(manifestOffset, Endian.little);
    final expected = headerSize + manifestSize + count * recordSize;
    if (data.length != expected) {
      throw RpbValidationException(
          'Invalid RPB length: expected $expected, got ${data.length}.');
    }
    if (_crc32(data.sublist(manifestOffset, manifestOffset + 12)) !=
        view.getUint32(manifestOffset + 12, Endian.little)) {
      throw const RpbValidationException(
          'The RPB manifest checksum is invalid.');
    }
    DateTime? earliestRecordDate;
    DateTime? latestRecordDate;
    if (count > 0) {
      final first = view.getUint32(recordsOffset, Endian.little);
      final last = view.getUint32(
          recordsOffset + (count - 1) * recordSize, Endian.little);
      if (first != view.getUint32(manifestOffset + 4, Endian.little) ||
          last != view.getUint32(manifestOffset + 8, Endian.little)) {
        throw const RpbValidationException(
            'Manifest sequence bounds do not match the records.');
      }
      final epoch = DateTime.utc(2020);
      for (var index = 0; index < count; index++) {
        final offset = recordsOffset + index * recordSize;
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

  static void _validateTagsExtension(
      Uint8List data, ByteData view, int headerSize) {
    final extensionSize = headerSize - baseHeaderSize;
    if (view.getUint32(64, Endian.little) != tagsMagic ||
        view.getUint16(68, Endian.little) != extensionSize ||
        data[71] != 0 ||
        _crc32(data.sublist(64, headerSize - 4)) !=
            view.getUint32(headerSize - 4, Endian.little)) {
      throw const RpbValidationException('The RPB tags extension is invalid.');
    }

    final count = data[70];
    if (count == 0 || count > 8) {
      throw const RpbValidationException('The RPB tags extension is invalid.');
    }
    var offset = 72;
    final tags = <String>{};
    for (var index = 0; index < count; index++) {
      if (offset >= headerSize - 4) {
        throw const RpbValidationException(
            'The RPB tags extension is truncated.');
      }
      final length = data[offset++];
      if (length == 0 || length > 32 || offset + length > headerSize - 4) {
        throw const RpbValidationException(
            'The RPB tags extension is invalid.');
      }
      final bytes = data.sublist(offset, offset + length);
      if (bytes.any((byte) => byte < 0x21 || byte > 0x7e)) {
        throw const RpbValidationException(
            'The RPB tags extension is invalid.');
      }
      final tag = String.fromCharCodes(bytes);
      if (!tags.add(tag)) {
        throw const RpbValidationException(
            'The RPB tags extension contains duplicate tags.');
      }
      offset += length;
    }
    if (offset != headerSize - 4) {
      throw const RpbValidationException(
          'The RPB tags extension has an invalid length.');
    }
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
