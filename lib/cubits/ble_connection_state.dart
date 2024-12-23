class BLEConnectionState {
  final bool isProcessing;
  final String statusMessage;
  final String displayName;

  BLEConnectionState({
    this.isProcessing = false,
    this.statusMessage = 'Waiting for Wi-Fi credentials via Bluetooth...',
    this.displayName = 'LG-423',
  });

  BLEConnectionState copyWith({
    bool? isProcessing,
    String? statusMessage,
    String? displayName,
  }) {
    return BLEConnectionState(
      isProcessing: isProcessing ?? this.isProcessing,
      statusMessage: statusMessage ?? this.statusMessage,
      displayName: displayName ?? this.displayName,
    );
  }
}
