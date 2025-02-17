import 'dart:convert';

import 'package:feralfile/services/logger.dart';

class VarintParser {
  static (String, String, int) parseDoubleString(List<int> bytes, int offset) {
    // Log incoming bytes
    final hexString =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    logger.info('Parsing bytes: $hexString');

    // Read first string length
    var (firstLength, newOffset) = _readVarint(bytes, offset);
    logger.info('First length: $firstLength, new offset: $newOffset');
    offset = newOffset;

    // Read first string
    final firstString =
        ascii.decode(bytes.sublist(offset, offset + firstLength));
    logger.info('First string: "$firstString"');
    offset += firstLength;

    // Read second string length
    var (secondLength, secondOffset) = _readVarint(bytes, offset);
    logger.info('Second length: $secondLength, new offset: $secondOffset');
    offset = secondOffset;

    // Read second string
    final secondString =
        ascii.decode(bytes.sublist(offset, offset + secondLength));
    logger.info('Second string: "$secondString"');
    offset += secondLength;

    return (firstString, secondString, offset);
  }

  static (int value, int newOffset) _readVarint(List<int> bytes, int offset) {
    var value = 0;
    var shift = 0;

    while (true) {
      final byte = bytes[offset];
      value |= (byte & 0x7F) << shift;

      logger.info(
          'Reading varint byte: 0x${byte.toRadixString(16).padLeft(2, '0')}, '
          'masked: 0x${(byte & 0x7F).toRadixString(16).padLeft(2, '0')}, '
          'shift: $shift, '
          'value: $value');

      offset++;

      if ((byte & 0x80) == 0) break;
      shift += 7;
    }

    return (value, offset);
  }

  static List<int> encodeDoubleString(String str1, String str2) {
    List<int> result = [];

    // Convert strings to UTF-8 bytes
    List<int> str1Bytes = utf8.encode(str1);
    List<int> str2Bytes = utf8.encode(str2);

    // Encode length of first string as varint
    List<int> str1Length = _encodeVarint(str1Bytes.length);
    result.addAll(str1Length);

    // Add first string bytes
    result.addAll(str1Bytes);

    // Encode length of second string as varint
    List<int> str2Length = _encodeVarint(str2Bytes.length);
    result.addAll(str2Length);

    // Add second string bytes
    result.addAll(str2Bytes);

    return result;
  }

  static List<int> _encodeVarint(int value) {
    List<int> bytes = [];

    while (value >= 0x80) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);

    return bytes;
  }

  static (List<String>, List<int>) parseToStringArray(
      List<int> bytes, int offset,
      {int? maxStrings}) {
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

        if (maxStrings != null && strings.length >= maxStrings) {
          break;
        }

        // Read string
        final str = ascii.decode(bytes.sublist(offset, offset + strLength));
        logger.info('Parsed string: "$str"');
        strings.add(str);

        offset += strLength;
      }

      List<int> remainingBytes = bytes.sublist(offset);
      return (strings, remainingBytes);
    } catch (e) {
      logger.info('Error parsing strings: ${e.toString()}');
      return (strings, []);
    }
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
