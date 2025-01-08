import 'dart:typed_data';
import 'dart:convert';

class VarintParser {
  static (String, String, int) parseDoubleString(Uint8List bytes, int offset) {
    // Read first string length
    var (firstLength, newOffset) = _readVarint(bytes, offset);
    offset = newOffset;

    // Read first string
    final firstString =
        ascii.decode(bytes.sublist(offset, offset + firstLength));
    offset += firstLength;

    // Read second string length
    var (secondLength, secondOffset) = _readVarint(bytes, offset);
    offset = secondOffset;

    // Read second string
    final secondString =
        ascii.decode(bytes.sublist(offset, offset + secondLength));
    offset += secondLength;

    return (firstString, secondString, offset);
  }

  static (int value, int newOffset) _readVarint(Uint8List bytes, int offset) {
    var value = 0;
    var shift = 0;

    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }

    return (value, offset);
  }
}
