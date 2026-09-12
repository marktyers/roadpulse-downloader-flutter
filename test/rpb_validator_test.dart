import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/src/protocol/rpb_validator.dart';

import 'support/fakes.dart';

void main() {
  group('RpbValidator', () {
    test('validates an empty snapshot and formats its device ID', () {
      final info = RpbValidator.validate(validRpb());
      expect(info.deviceId, 'RP-8FCBA4');
      expect(info.recordCount, 0);
      expect(info.earliestRecordDate, isNull);
      expect(info.latestRecordDate, isNull);
    });
    test('finds the earliest and latest record dates in any record order', () {
      final info = RpbValidator.validate(validRpb(
        sequences: [41, 42, 43],
        recordDates: [
          DateTime.utc(2026, 8, 18),
          DateTime.utc(2026, 6, 23),
          DateTime.utc(2026, 7, 10),
        ],
      ));
      expect(info.earliestRecordDate, DateTime.utc(2026, 6, 23));
      expect(info.latestRecordDate, DateTime.utc(2026, 8, 18));
    });
    test('validates records and manifest sequence bounds', () {
      expect(
          RpbValidator.validate(validRpb(sequences: [41, 42, 43])).recordCount,
          3);
    });
    test('keeps device IDs wider than six hexadecimal digits', () {
      expect(RpbValidator.validate(validRpb(deviceId: 0x12345678)).deviceId,
          'RP-12345678');
    });
    test('rejects every truncated size below the minimum', () {
      for (var size = 0; size < 80; size++) {
        expect(() => RpbValidator.validate(Uint8List(size)),
            throwsA(isA<RpbValidationException>()),
            reason: 'size $size');
      }
    });
    for (final mutation in <String, void Function(Uint8List)>{
      'magic': (d) => d[0] ^= 1,
      'header size': (d) => d[6] = 63,
      'record size': (d) => d[10] = 40,
      'layout marker': (d) => d[47] = 0,
      'header CRC': (d) => d[20] ^= 1,
    }.entries) {
      test('rejects invalid ${mutation.key}', () {
        final data = validRpb();
        mutation.value(data);
        expect(() => RpbValidator.validate(data),
            throwsA(isA<RpbValidationException>()));
      });
    }
    test('rejects an incorrect exact length', () {
      final data = validRpb(sequences: [1]);
      final short = Uint8List.fromList(data.sublist(0, data.length - 1));
      expect(() => RpbValidator.validate(short),
          throwsA(predicate((e) => '$e'.contains('expected 121'))));
    });
    test('rejects a corrupt manifest CRC', () {
      final data = validRpb()..[68] ^= 1;
      expect(() => RpbValidator.validate(data),
          throwsA(predicate((e) => '$e'.contains('manifest checksum'))));
    });
    test('rejects mismatched first and last sequences', () {
      final first = validRpb(sequences: [10, 11]);
      ByteData.sublistView(first).setUint32(80, 9, Endian.little);
      expect(() => RpbValidator.validate(first),
          throwsA(predicate((e) => '$e'.contains('sequence bounds'))));
      final last = validRpb(sequences: [10, 11]);
      ByteData.sublistView(last).setUint32(121, 12, Endian.little);
      expect(() => RpbValidator.validate(last),
          throwsA(predicate((e) => '$e'.contains('sequence bounds'))));
    });
  });
}
