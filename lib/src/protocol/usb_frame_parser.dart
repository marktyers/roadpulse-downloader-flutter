import 'dart:typed_data';

final class UsbFrameException implements Exception {
  const UsbFrameException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Incrementally decodes the logger's unsolicited ASCII-hex export.
final class UsbFrameParser {
  static final _beginPrefix = Uint8List.fromList('RPB_HEX_BEGIN '.codeUnits);
  static final _endMarker = Uint8List.fromList('\nRPB_HEX_END'.codeUnits);
  static const _maximumHeaderBytes = 8192;
  static const _maximumTrailerBytes = 256;

  final _header = <int>[];
  final _payload = BytesBuilder(copy: false);
  final _trailer = <int>[];
  _Phase _phase = _Phase.header;
  int? _highNibble;
  bool _atPayloadLineStart = false;
  int? expectedPayloadBytes;
  int receivedPayloadBytes = 0;

  Uint8List? append(List<int> bytes) {
    for (final byte in bytes) {
      switch (_phase) {
        case _Phase.header:
          _consumeHeader(byte);
          break;
        case _Phase.payload:
          _consumePayload(byte);
          break;
        case _Phase.trailer:
          if (_consumeTrailer(byte)) return _payload.toBytes();
          break;
        case _Phase.complete:
          return _payload.toBytes();
      }
    }
    return _phase == _Phase.complete ? _payload.toBytes() : null;
  }

  void _consumeHeader(int byte) {
    _header.add(byte);
    if (byte != 0x0a) {
      if (_header.length > _maximumHeaderBytes) {
        _header.removeRange(0, _header.length - _maximumHeaderBytes);
      }
      return;
    }
    final prefix = _indexOf(_header, _beginPrefix);
    if (prefix < 0) return;
    final lengthStart = prefix + _beginPrefix.length;
    final lineEnd = _header.indexOf(0x0a, lengthStart);
    if (lineEnd < 0) return;
    final text =
        String.fromCharCodes(_header.sublist(lengthStart, lineEnd)).trim();
    final expected = int.tryParse(text);
    if (expected == null || expected < 0) {
      throw const UsbFrameException(
          'The logger returned an invalid export length.');
    }
    expectedPayloadBytes = expected;
    _header.clear();
    _phase = expected == 0 ? _Phase.trailer : _Phase.payload;
  }

  void _consumePayload(int byte) {
    if (byte == 10) {
      _atPayloadLineStart = true;
      return;
    }
    if (byte == 9 || byte == 13 || byte == 32) return;
    if (_atPayloadLineStart && byte == 82) {
      _trailer.add(10);
      _trailer.add(byte);
      _phase = _Phase.trailer;
      return;
    }
    _atPayloadLineStart = false;
    final nibble = _hex(byte);
    if (nibble == null) {
      throw const UsbFrameException(
          'The logger returned invalid hexadecimal data.');
    }
    if (_highNibble case final high?) {
      _payload.addByte((high << 4) | nibble);
      _highNibble = null;
      receivedPayloadBytes++;
      if (receivedPayloadBytes == expectedPayloadBytes) _phase = _Phase.trailer;
    } else {
      _highNibble = nibble;
    }
  }

  bool _consumeTrailer(int byte) {
    if (_highNibble != null) {
      throw const UsbFrameException(
          'The logger returned invalid hexadecimal data.');
    }
    _trailer.add(byte);
    if (_indexOf(_trailer, _endMarker) >= 0) {
      if (receivedPayloadBytes != expectedPayloadBytes) {
        throw UsbFrameException('Export length mismatch: expected '
            '${expectedPayloadBytes ?? 0}, received $receivedPayloadBytes.');
      }
      _phase = _Phase.complete;
      return true;
    }
    if (_indexOf(_trailer, 'RPB_USB_EXPORT_FAILED'.codeUnits) >= 0) {
      throw const UsbFrameException(
          'RoadPulse Logger could not read its retained records.');
    }
    if (_trailer.length > _maximumTrailerBytes) {
      throw UsbFrameException('Export length mismatch: expected '
          '${expectedPayloadBytes ?? 0}, received $receivedPayloadBytes.');
    }
    return false;
  }

  static int? _hex(int byte) {
    if (byte >= 48 && byte <= 57) return byte - 48;
    if (byte >= 65 && byte <= 70) return byte - 55;
    if (byte >= 97 && byte <= 102) return byte - 87;
    return null;
  }

  static int _indexOf(List<int> source, List<int> pattern) {
    for (var i = 0; i <= source.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

enum _Phase { header, payload, trailer, complete }
