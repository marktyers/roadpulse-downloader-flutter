import 'dart:typed_data';

abstract interface class RpbRecordDecoder {
  int sequence(ByteData data, int offset);
  DateTime recordDate(ByteData data, int offset, int gpsEpochYear);
}

final class StandardRpbRecordDecoder implements RpbRecordDecoder {
  const StandardRpbRecordDecoder();

  @override
  int sequence(ByteData data, int offset) =>
      data.getUint32(offset, Endian.little);

  @override
  DateTime recordDate(ByteData data, int offset, int gpsEpochYear) =>
      DateTime.utc(gpsEpochYear).add(
        Duration(days: data.getUint16(offset + 4, Endian.little)),
      );
}

final class RpbRecordProfile {
  const RpbRecordProfile({
    required this.identifier,
    required this.schemaVersion,
    required this.recordSize,
    required this.name,
    required this.supported,
    required this.baseHeaderSize,
    required this.binaryFormatVersion,
    required this.decoder,
    this.extensionProfile,
  });

  /// The firmware's on-wire `record_schema_version`, used as the profile key.
  final int identifier;
  final int schemaVersion;
  final int recordSize;
  final String name;
  final bool supported;
  final int baseHeaderSize;
  final int binaryFormatVersion;
  final int? extensionProfile;
  final RpbRecordDecoder decoder;

  String get displayName => '$name — $recordSize-byte records';
}

abstract final class RpbProfileRegistry {
  static const _decoder = StandardRpbRecordDecoder();

  static const legacy = RpbRecordProfile(
    identifier: 1,
    schemaVersion: 1,
    recordSize: 41,
    name: 'Legacy',
    supported: true,
    baseHeaderSize: 64,
    binaryFormatVersion: 1,
    decoder: _decoder,
  );

  static const fullDiagnostic = RpbRecordProfile(
    identifier: 2,
    schemaVersion: 2,
    recordSize: 63,
    name: 'Full diagnostic',
    supported: true,
    baseHeaderSize: 96,
    binaryFormatVersion: 2,
    extensionProfile: 3,
    decoder: _decoder,
  );

  static const profiles = <RpbRecordProfile>[legacy, fullDiagnostic];

  static RpbRecordProfile? lookup(int identifier, int schemaVersion) {
    for (final profile in profiles) {
      if (profile.identifier == identifier &&
          profile.schemaVersion == schemaVersion) {
        return profile;
      }
    }
    return null;
  }
}
