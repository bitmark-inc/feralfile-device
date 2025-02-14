import 'package:feralfile/utils/varint_parser.dart';

class ChunkInfo {
  final int index;
  final int total;
  final String ackReplyId;
  final List<int> command;

  ChunkInfo({
    required this.index,
    required this.total,
    required this.ackReplyId,
    required this.command,
  });

  factory ChunkInfo.fromData(List<int> data) {
    final (chunkStrings, chunkCommand) =
        VarintParser.parseToStringArray(data, 0, maxStrings: 3);
    return ChunkInfo(
      index: int.parse(chunkStrings[0]),
      total: int.parse(chunkStrings[1]),
      ackReplyId: chunkStrings[2],
      command: chunkCommand,
    );
  }

  bool isValid() {
    return index >= 0 && total > 0 && index < total;
  }
}
