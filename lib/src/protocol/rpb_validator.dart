import 'dart:typed_data';

import 'rpb_profile.dart';

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
    required this.tags,
    required this.profile,
    this.earliestRecordDate,
    this.latestRecordDate,
  });
  final String deviceId;
  final int recordCount;
  final List<String> tags;
  final RpbRecordProfile profile;
  final DateTime? earliestRecordDate;
  final DateTime? latestRecordDate;
}

abstract final class RpbValidator {
  static const commonHeaderSize = 12;
  static const manifestSize = 16;
  static const headerMagic = 0x48425052;
  static const tagsMagic = 0x53474154;

  static RpbInfo validate(Uint8List data) {
    if (data.length < commonHeaderSize) {
      throw const RpbValidationException('The RPB header is truncated.');
    }
    final view = ByteData.sublistView(data);
    final version = view.getUint16(4, Endian.little);
    final headerSize = view.getUint16(6, Endian.little);
    final schemaVersion = view.getUint16(8, Endian.little);
    final declaredRecordSize = view.getUint16(10, Endian.little);
    final profile = RpbProfileRegistry.lookup(schemaVersion, schemaVersion);
    if (profile == null) {
      throw RpbValidationException(
        'Unknown RPB profile identifier $schemaVersion '
        '(schema version $schemaVersion, record size '
        '$declaredRecordSize bytes).',
      );
    }
    if (!profile.supported) {
      throw RpbValidationException(
        'RPB profile identifier ${profile.identifier} '
        '(schema version ${profile.schemaVersion}) is not supported.',
      );
    }
    if (data.length < profile.baseHeaderSize) {
      throw RpbValidationException(
        'The ${profile.name} RPB header is truncated.',
      );
    }
    if (view.getUint32(0, Endian.little) != headerMagic ||
        declaredRecordSize != profile.recordSize ||
        data[47] != 1) {
      throw const RpbValidationException('The RPB header is unsupported.');
    }
    if (profile.extensionProfile case final expected?) {
      final actual = data[50];
      if (actual != expected) {
        throw RpbValidationException(
          'Unknown RPB extension profile $actual '
          '(schema version $schemaVersion).',
        );
      }
    }
    final hasTags = headerSize > profile.baseHeaderSize;
    final expectedVersion = profile.binaryFormatVersion + (hasTags ? 1 : 0);
    if (headerSize < profile.baseHeaderSize || version != expectedVersion) {
      throw const RpbValidationException('The RPB header is unsupported.');
    }
    final headerCrcOffset = profile.baseHeaderSize - 4;
    if (_crc32(data.sublist(0, headerCrcOffset)) !=
        view.getUint32(headerCrcOffset, Endian.little)) {
      throw const RpbValidationException('The RPB header checksum is invalid.');
    }
    if (data.length < headerSize + manifestSize) {
      throw const RpbValidationException('The RPB file is truncated.');
    }
    final tags = hasTags
        ? _validateTagsExtension(data, view, profile.baseHeaderSize, headerSize)
        : const <String>[];
    final manifestOffset = headerSize;
    final recordsOffset = manifestOffset + manifestSize;
    final count = view.getUint32(manifestOffset, Endian.little);
    final payloadLength = data.length - recordsOffset;
    if (payloadLength % profile.recordSize != 0) {
      throw RpbValidationException(
        'The RPB payload ends with a partial ${profile.recordSize}-byte '
        'record (${payloadLength % profile.recordSize} trailing bytes).',
      );
    }
    final actualCount = payloadLength ~/ profile.recordSize;
    if (actualCount != count) {
      throw RpbValidationException(
        'RPB record-count mismatch: header declares $count records '
        'but the payload contains $actualCount.',
      );
    }
    if (_crc32(data.sublist(manifestOffset, manifestOffset + 12)) !=
        view.getUint32(manifestOffset + 12, Endian.little)) {
      throw const RpbValidationException(
          'The RPB manifest checksum is invalid.');
    }
    DateTime? earliestRecordDate;
    DateTime? latestRecordDate;
    if (count > 0) {
      final first = profile.decoder.sequence(view, recordsOffset);
      final last = profile.decoder
          .sequence(view, recordsOffset + (count - 1) * profile.recordSize);
      if (first != view.getUint32(manifestOffset + 4, Endian.little) ||
          last != view.getUint32(manifestOffset + 8, Endian.little)) {
        throw const RpbValidationException(
            'Manifest sequence bounds do not match the records.');
      }
      final gpsEpochYear = view.getUint16(48, Endian.little);
      for (var index = 0; index < count; index++) {
        final offset = recordsOffset + index * profile.recordSize;
        final date = profile.decoder.recordDate(view, offset, gpsEpochYear);
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
      tags: tags,
      profile: profile,
      earliestRecordDate: earliestRecordDate,
      latestRecordDate: latestRecordDate,
    );
  }

  static List<String> _validateTagsExtension(
      Uint8List data, ByteData view, int baseHeaderSize, int headerSize) {
    final extensionSize = headerSize - baseHeaderSize;
    if (extensionSize < 12 ||
        view.getUint32(baseHeaderSize, Endian.little) != tagsMagic ||
        view.getUint16(baseHeaderSize + 4, Endian.little) != extensionSize ||
        data[baseHeaderSize + 7] != 0 ||
        _crc32(data.sublist(baseHeaderSize, headerSize - 4)) !=
            view.getUint32(headerSize - 4, Endian.little)) {
      throw const RpbValidationException('The RPB tags extension is invalid.');
    }

    final count = data[baseHeaderSize + 6];
    if (count == 0 || count > 8) {
      throw const RpbValidationException('The RPB tags extension is invalid.');
    }
    var offset = baseHeaderSize + 8;
    final uniqueTags = <String>{};
    final tags = <String>[];
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
      if (!uniqueTags.add(tag)) {
        throw const RpbValidationException(
            'The RPB tags extension contains duplicate tags.');
      }
      tags.add(tag);
      offset += length;
    }
    if (offset != headerSize - 4) {
      throw const RpbValidationException(
          'The RPB tags extension has an invalid length.');
    }
    return List.unmodifiable(tags);
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
