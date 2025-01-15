enum BLEConnectionStatus {
  initial,
  connecting,
  connected,
  failed,
}

class BLEConnectionState {
  final BLEConnectionStatus status;
  final String ssid;
  final bool isProcessing;
  final String localIp;

  BLEConnectionState({
    this.status = BLEConnectionStatus.initial,
    this.ssid = '',
    this.isProcessing = false,
    this.localIp = '',
  });

  BLEConnectionState copyWith({
    BLEConnectionStatus? status,
    String? ssid,
    bool? isProcessing,
    String? localIp,
  }) {
    return BLEConnectionState(
      status: status ?? this.status,
      ssid: ssid ?? this.ssid,
      isProcessing: isProcessing ?? this.isProcessing,
      localIp: localIp ?? this.localIp,
    );
  }
}
