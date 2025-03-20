import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../environment.dart';
import 'logger.dart';
import 'bluetooth_service.dart';

class MetricEvent {
  final String eventName;
  final String deviceId;
  final List<String>? stringData;
  final List<double>? doubleData;

  MetricEvent({
    required this.eventName,
    required this.deviceId,
    this.stringData,
    this.doubleData,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'event_name': eventName,
      'device_id': deviceId,
    };

    // Only include data fields if they have values
    if (stringData != null) {
      json['stringData'] = stringData;
    }
    if (doubleData != null) {
      json['doubleData'] = doubleData;
    }

    return json;
  }
}

class MetricService {
  static final MetricService _instance = MetricService._internal();
  final List<MetricEvent> _eventCache = [];
  Timer? _flushTimer;
  static const _flushInterval = Duration(minutes: 1);
  final BluetoothService _bluetoothService = BluetoothService();

  factory MetricService() => _instance;

  MetricService._internal() {
    if (Environment.metricsURL.isEmpty || Environment.metricsApiKey.isEmpty) {
      logger.warning(
          'Metrics configuration is missing. Events will not be sent.');
    }
    _startFlushTimer();
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void sendEvent(
    String eventName, {
    String? deviceId,
    List<String>? stringData,
    List<double>? doubleData,
  }) {
    // Convert empty lists to null
    final strings = stringData?.isEmpty == true ? null : stringData;
    final doubles = doubleData?.isEmpty == true ? null : doubleData;

    final event = MetricEvent(
      eventName: eventName,
      deviceId: deviceId ?? _bluetoothService.getDeviceId(),
      stringData: strings,
      doubleData: doubles,
    );

    _eventCache.add(event);
    logger.info('Event cached: $eventName (Cache size: ${_eventCache.length})');
  }

  Future<void> flush() async {
    if (_eventCache.isEmpty) {
      return;
    }

    if (Environment.metricsURL.isEmpty || Environment.metricsApiKey.isEmpty) {
      logger.warning('Skipping metric flush: Missing configuration');
      return;
    }

    try {
      final events = List<MetricEvent>.from(_eventCache);
      _eventCache.clear();

      final response = await http.post(
        Uri.parse(Environment.metricsURL),
        headers: {
          'x-api-key': Environment.metricsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(events.map((e) => e.toJson()).toList()),
      );

      if (response.statusCode != 200) {
        // If send fails, add events back to cache
        _eventCache.insertAll(0, events);
        throw Exception('Failed to send metrics: ${response.statusCode}');
      }

      logger.info('Successfully flushed ${events.length} events');
    } catch (e) {
      // logger.warning('Error flushing metrics: $e');
    }
  }

  void trackError(String errorMessage) {
    sendEvent(
      'app_error',
      stringData: [errorMessage],
      doubleData: [1.0],
    );
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _eventCache.clear();
  }
}
