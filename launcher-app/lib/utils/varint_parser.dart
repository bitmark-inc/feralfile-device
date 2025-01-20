import 'dart:convert';
import 'package:feralfile/services/logger.dart';

class VarintParser {
  static List<int> _encodeVarint(int value) {
    List<int> bytes = [];

    while (value >= 0x80) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);

    return bytes;
  }

  static List<String> parseToStringArray(List<int> bytes, int offset) {
    // Log incoming bytes
    final hexString =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    logger.info('Parsing bytes: $hexString');

    List<String> strings = [];

    try {
      while (offset < bytes.length) {
        // Read string length
        var (strLength, newOffset) = _readVarint(bytes, offset);
        logger.info('String length: $strLength, new offset: $newOffset');
        offset = newOffset;

        // Read string
        final str = ascii.decode(bytes.sublist(offset, offset + strLength));
        logger.info('Parsed string: "$str"');
        strings.add(str);

        offset += strLength;
      }
    } catch (e) {
      logger.info('Finished parsing strings: ${e.toString()}');
    }

    return strings;
  }

  static List<int> encodeStringArray(List<String> strings) {
    List<int> result = [];

    for (var str in strings) {
      // Convert string to UTF-8 bytes
      List<int> strBytes = utf8.encode(str);

      // Encode length as varint
      result.addAll(_encodeVarint(strBytes.length));

      // Add string bytes
      result.addAll(strBytes);
    }

    return result;
  }
}
