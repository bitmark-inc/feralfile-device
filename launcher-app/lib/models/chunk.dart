import 'package:feralfile/services/logger.dart';
import 'package:feralfile/utils/varint_parser.dart';

class ChunkInfo {
  final int index;
  final int total;
  final String ackReplyId;
  final List<int> data;

  ChunkInfo({
    required this.index,
    required this.total,
    required this.ackReplyId,
    required this.data,
  });

  factory ChunkInfo.fromData(List<int> data) {
    final (chunkStrings, chunkData) =
        VarintParser.parseToStringArray(data, 0, maxStrings: 3);
    logger.info('Chunk strings: $chunkStrings');
    logger.info('Chunk data: $chunkData');
    return ChunkInfo(
      index: int.parse(chunkStrings[0]),
      total: int.parse(chunkStrings[1]),
      ackReplyId: chunkStrings[2],
      data: chunkData,
    );
  }

  bool isValid() {
    return index >= 0 && total > 0 && index < total;
  }
}
