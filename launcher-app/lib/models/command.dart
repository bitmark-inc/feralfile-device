enum Command {
  checkStatus,
  castListArtwork,
  cancelCasting,
  appendArtworkToCastingList,
  pauseCasting,
  resumeCasting,
  nextArtwork,
  previousArtwork,
  updateDuration,
  castExhibition,
  connect,
  disconnect,
  setCursorOffset,
  getCursorOffset,
  sendKeyboardEvent,
  rotate,
  updateArtFraming,
  tapGesture,
  dragGesture,
  castDaily;

  static Command fromString(String command) {
    switch (command) {
      case 'checkStatus':
        return Command.checkStatus;
      case 'castListArtwork':
        return Command.castListArtwork;
      case 'castDaily':
        return Command.castDaily;
      case 'cancelCasting':
        return Command.cancelCasting;
      case 'appendArtworkToCastingList':
        return Command.appendArtworkToCastingList;
      case 'pauseCasting':
        return Command.pauseCasting;
      case 'resumeCasting':
        return Command.resumeCasting;
      case 'nextArtwork':
        return Command.nextArtwork;
      case 'previousArtwork':
        return Command.previousArtwork;
      case 'updateDuration':
        return Command.updateDuration;
      case 'castExhibition':
        return Command.castExhibition;
      case 'connect':
        return Command.connect;
      case 'disconnect':
        return Command.disconnect;
      case 'setCursorOffset':
        return Command.setCursorOffset;
      case 'getCursorOffset':
        return Command.getCursorOffset;
      case 'sendKeyboardEvent':
        return Command.sendKeyboardEvent;
      case 'rotate':
        return Command.rotate;
      case 'updateArtFraming':
        return Command.updateArtFraming;
      case 'tapGesture':
        return Command.tapGesture;
      case 'dragGesture':
        return Command.dragGesture;
      default:
        throw ArgumentError('Unknown command: $command');
    }
  }
}
