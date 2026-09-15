import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/src/protocol/usb_frame_parser.dart';

void main() {
  group('UsbFrameParser', () {
    test('accepts a frame split across chunks with noise and mixed case', () {
      final parser = UsbFrameParser();
      expect(parser.append('noise\nRPB_HEX_BEGIN 3\n0A'.codeUnits), isNull);
      expect(parser.expectedPayloadBytes, 3);
      expect(parser.receivedPayloadBytes, 1);
      expect(parser.append('0b 0C\nRPB_HEX_END\n'.codeUnits),
          Uint8List.fromList([0x0a, 0x0b, 0x0c]));
    });

    test('accepts CR, LF, tabs, and spaces between hex digits', () {
      final parser = UsbFrameParser();
      expect(
          parser
              .append('RPB_HEX_BEGIN 3\n0A\t 0b\r\n0C\nRPB_HEX_END'.codeUnits),
          Uint8List.fromList([10, 11, 12]));
    });

    test('accepts an empty payload', () {
      expect(
          UsbFrameParser().append('RPB_HEX_BEGIN 0\n\nRPB_HEX_END'.codeUnits),
          isEmpty);
    });

    test('retains only a bounded pre-header window', () {
      final parser = UsbFrameParser();
      final noise = List.filled(9000, 'x').join();
      expect(
          parser.append('$noise\nRPB_HEX_BEGIN 1\nAA\nRPB_HEX_END'.codeUnits),
          Uint8List.fromList([0xaa]));
    });

    test('rejects invalid and negative declared lengths', () {
      expect(() => UsbFrameParser().append('RPB_HEX_BEGIN nope\n'.codeUnits),
          throwsA(isA<UsbFrameException>()));
      expect(() => UsbFrameParser().append('RPB_HEX_BEGIN -1\n'.codeUnits),
          throwsA(isA<UsbFrameException>()));
    });

    test('rejects non-hex data and an odd final nibble', () {
      expect(() => UsbFrameParser().append('RPB_HEX_BEGIN 1\nGG'.codeUnits),
          throwsA(isA<UsbFrameException>()));
      expect(
          () => UsbFrameParser()
              .append('RPB_HEX_BEGIN 1\nA\nRPB_HEX_END'.codeUnits),
          throwsA(isA<UsbFrameException>()));
    });

    test('rejects a missing trailer after its bounded window', () {
      final noise = List.filled(257, 'x').join();
      expect(
          () => UsbFrameParser().append('RPB_HEX_BEGIN 1\n00$noise'.codeUnits),
          throwsA(predicate((e) => '$e'.contains('length mismatch'))));
    });

    test('rejects a short payload', () {
      final parser = UsbFrameParser();
      expect(() => parser.append('RPB_HEX_BEGIN 2\n00\nRPB_HEX_END'.codeUnits),
          throwsA(predicate((error) => '$error'.contains('length mismatch'))));
    });

    test('reports an explicit logger export failure', () {
      final parser = UsbFrameParser();
      expect(
          () => parser.append(
              'RPB_HEX_BEGIN 2\n00\nRPB_USB_EXPORT_FAILED stream'.codeUnits),
          throwsA(predicate((error) =>
              '$error'.contains('could not read its retained records'))));
    });

    test('decodes a large frame incrementally', () {
      const size = 262144;
      final source = Uint8List.fromList(List.generate(size, (i) => i & 0xff));
      const digits = '0123456789ABCDEF';
      final frame = StringBuffer('RPB_HEX_BEGIN $size\n');
      for (final byte in source) {
        frame
          ..write(digits[byte >> 4])
          ..write(digits[byte & 15]);
      }
      frame.write('\nRPB_HEX_END\n');
      final encoded = frame.toString().codeUnits;
      final parser = UsbFrameParser();
      Uint8List? decoded;
      for (var start = 0; start < encoded.length; start += 4096) {
        decoded = parser.append(encoded.sublist(
                start,
                start + 4096 < encoded.length
                    ? start + 4096
                    : encoded.length)) ??
            decoded;
      }
      expect(decoded, source);
    });
  });
}
