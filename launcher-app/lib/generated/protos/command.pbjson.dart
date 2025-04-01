///
//  Generated code. Do not modify.
//  source: protos/command.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use commandDataDescriptor instead')
const CommandData$json = const {
  '1': 'CommandData',
  '2': const [
    const {'1': 'command', '3': 1, '4': 1, '5': 9, '10': 'command'},
    const {'1': 'data', '3': 2, '4': 1, '5': 9, '10': 'data'},
    const {'1': 'reply_id', '3': 3, '4': 1, '5': 9, '10': 'replyId'},
    const {'1': 'user_info', '3': 4, '4': 1, '5': 11, '6': '.feralfile.UserInfo', '10': 'userInfo'},
  ],
};

/// Descriptor for `CommandData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandDataDescriptor = $convert.base64Decode('CgtDb21tYW5kRGF0YRIYCgdjb21tYW5kGAEgASgJUgdjb21tYW5kEhIKBGRhdGEYAiABKAlSBGRhdGESGQoIcmVwbHlfaWQYAyABKAlSB3JlcGx5SWQSMAoJdXNlcl9pbmZvGAQgASgLMhMuZmVyYWxmaWxlLlVzZXJJbmZvUgh1c2VySW5mbw==');
@$core.Deprecated('Use userInfoDescriptor instead')
const UserInfo$json = const {
  '1': 'UserInfo',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `UserInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userInfoDescriptor = $convert.base64Decode('CghVc2VySW5mbxIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZQ==');
@$core.Deprecated('Use commandResponseDescriptor instead')
const CommandResponse$json = const {
  '1': 'CommandResponse',
  '2': const [
    const {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    const {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    const {'1': 'data', '3': 3, '4': 1, '5': 9, '10': 'data'},
    const {'1': 'error', '3': 4, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `CommandResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandResponseDescriptor = $convert.base64Decode('Cg9Db21tYW5kUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIYCgdtZXNzYWdlGAIgASgJUgdtZXNzYWdlEhIKBGRhdGEYAyABKAlSBGRhdGESFAoFZXJyb3IYBCABKAlSBWVycm9y');
