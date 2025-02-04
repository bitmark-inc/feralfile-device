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
  final String deviceId;

  BLEConnectionState({
    this.status = BLEConnectionStatus.initial,
    this.ssid = '',
    this.isProcessing = false,
    this.localIp = '',
    this.deviceId = '',
  });

  BLEConnectionState copyWith({
    BLEConnectionStatus? status,
    String? ssid,
    bool? isProcessing,
    String? localIp,
    String? deviceId,
  }) {
    return BLEConnectionState(
      status: status ?? this.status,
      ssid: ssid ?? this.ssid,
      isProcessing: isProcessing ?? this.isProcessing,
      localIp: localIp ?? this.localIp,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
