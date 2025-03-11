//
//  Generated code. Do not modify.
//  source: protos/system_metrics.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use systemMetricsDescriptor instead')
const SystemMetrics$json = {
  '1': 'SystemMetrics',
  '2': [
    {'1': 'cpu_usage', '3': 1, '4': 1, '5': 1, '10': 'cpuUsage'},
    {'1': 'gpu_usage', '3': 2, '4': 1, '5': 1, '10': 'gpuUsage'},
    {'1': 'memory_usage', '3': 3, '4': 1, '5': 1, '10': 'memoryUsage'},
    {'1': 'cpu_temperature', '3': 4, '4': 1, '5': 1, '10': 'cpuTemperature'},
    {'1': 'gpu_temperature', '3': 5, '4': 1, '5': 1, '10': 'gpuTemperature'},
    {'1': 'screen_width', '3': 6, '4': 1, '5': 5, '10': 'screenWidth'},
    {'1': 'screen_height', '3': 7, '4': 1, '5': 5, '10': 'screenHeight'},
    {'1': 'uptime_seconds', '3': 8, '4': 1, '5': 3, '10': 'uptimeSeconds'},
    {'1': 'timestamp', '3': 9, '4': 1, '5': 3, '10': 'timestamp'},
  ],
};

/// Descriptor for `SystemMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List systemMetricsDescriptor = $convert.base64Decode(
    'Cg1TeXN0ZW1NZXRyaWNzEhsKCWNwdV91c2FnZRgBIAEoAVIIY3B1VXNhZ2USGwoJZ3B1X3VzYW'
    'dlGAIgASgBUghncHVVc2FnZRIhCgxtZW1vcnlfdXNhZ2UYAyABKAFSC21lbW9yeVVzYWdlEicK'
    'D2NwdV90ZW1wZXJhdHVyZRgEIAEoAVIOY3B1VGVtcGVyYXR1cmUSJwoPZ3B1X3RlbXBlcmF0dX'
    'JlGAUgASgBUg5ncHVUZW1wZXJhdHVyZRIhCgxzY3JlZW5fd2lkdGgYBiABKAVSC3NjcmVlbldp'
    'ZHRoEiMKDXNjcmVlbl9oZWlnaHQYByABKAVSDHNjcmVlbkhlaWdodBIlCg51cHRpbWVfc2Vjb2'
    '5kcxgIIAEoA1INdXB0aW1lU2Vjb25kcxIcCgl0aW1lc3RhbXAYCSABKANSCXRpbWVzdGFtcA==');

