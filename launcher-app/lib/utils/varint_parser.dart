import 'dart:typed_data';
import 'dart:convert';
import 'package:feralfile/services/logger.dart';

class VarintParser {
  static (String, String, int) parseDoubleString(Uint8List bytes, int offset) {
    // Log incoming bytes
    final hexString =
        bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ');
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

  static (int value, int newOffset) _readVarint(Uint8List bytes, int offset) {
    // Final decoded value
    var value = 0;
    // Keeps track of which position we're processing (0, 7, 14, etc.)
    var shift = 0;

    while (true) {
      final byte = bytes[offset++];

      // 0x7F is 0111 1111 in binary. Using & with 0x7F masks out the MSB (most significant bit),
      // giving us just the 7 data bits. The MSB is used as a continuation flag.
      //
      // Example: byte = 1010 1100
      //          0x7F = 0111 1111
      //          &    = 0010 1100 (gets just the data bits)

      // We shift the 7 data bits left by 'shift' positions and combine them with
      // the existing value using OR (|). This builds our number 7 bits at a time.
      // First iteration: shift = 0  (bits go in positions 0-6)
      // Second iteration: shift = 7 (bits go in positions 7-13)
      // Third iteration:  shift = 14 (bits go in positions 14-20)
      // And so on...
      value |= (byte & 0x7F) << shift;

      // The MSB (0x80 = 1000 0000) indicates if there are more bytes to come.
      // If MSB is 0, this is the last byte of the varint.
      if ((byte & 0x80) == 0) break;

      // Move to the next 7 bits position
      shift += 7;
    }

    return (value, offset);
  }
}
