enum BLEConnectionStatus {
  initial,
  connecting,
  connected,
  acceptingNewConnection,
  failed,
}

class BLEConnectionState {
  final BLEConnectionStatus status;
  final String ssid;
  final bool isProcessing;
  final String localIp;
  final String deviceId;
  final String version;

  BLEConnectionState({
    this.status = BLEConnectionStatus.initial,
    this.ssid = '',
    this.isProcessing = false,
    this.localIp = '',
    this.deviceId = '',
    this.version = '',
  });

  BLEConnectionState copyWith({
    BLEConnectionStatus? status,
    String? ssid,
    bool? isProcessing,
    String? localIp,
    String? deviceId,
    String? version,
  }) {
    return BLEConnectionState(
      status: status ?? this.status,
      ssid: ssid ?? this.ssid,
      isProcessing: isProcessing ?? this.isProcessing,
      localIp: localIp ?? this.localIp,
      deviceId: deviceId ?? this.deviceId,
      version: version ?? this.version,
    );
  }
}
