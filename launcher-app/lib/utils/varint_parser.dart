import 'dart:typed_data';
import 'dart:convert';
import 'package:feralfile/services/logger.dart';

class VarintParser {
  static (String, String, int) parseDoubleString(Uint8List bytes, int offset) {
    // Create a defensive copy of the bytes
    final bytesCopy = Uint8List.fromList(bytes);

    // Log incoming bytes
    final hexString =
        bytesCopy.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    logger.info('Parsing bytes: $hexString');

    // Read first string length
    var (firstLength, newOffset) = _readVarint(bytesCopy, offset);
    logger.info('First length: $firstLength, new offset: $newOffset');
    offset = newOffset;

    // Read first string
    final firstString =
        ascii.decode(bytesCopy.sublist(offset, offset + firstLength));
    logger.info('First string: "$firstString"');
    offset += firstLength;

    // Read second string length
    var (secondLength, secondOffset) = _readVarint(bytesCopy, offset);
    logger.info('Second length: $secondLength, new offset: $secondOffset');
    offset = secondOffset;

    // Read second string
    final secondString =
        ascii.decode(bytesCopy.sublist(offset, offset + secondLength));
    logger.info('Second string: "$secondString"');
    offset += secondLength;

    return (firstString, secondString, offset);
  }

  static (int value, int newOffset) _readVarint(Uint8List bytes, int offset) {
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
}
