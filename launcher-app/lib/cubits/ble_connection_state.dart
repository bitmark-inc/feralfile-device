enum BLEConnectionStatus {
  initial,
  connecting,
  connected,
}

class BLEConnectionState {
  final BLEConnectionStatus status;
  final String ssid;
  final bool isProcessing;

  BLEConnectionState({
    this.status = BLEConnectionStatus.initial,
    this.ssid = '',
    this.isProcessing = false,
  });

  BLEConnectionState copyWith({
    BLEConnectionStatus? status,
    String? ssid,
    bool? isProcessing,
  }) {
    return BLEConnectionState(
      status: status ?? this.status,
      ssid: ssid ?? this.ssid,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}
