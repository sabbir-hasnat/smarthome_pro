import 'dart:convert';

class DeviceMessageResult {
  const DeviceMessageResult({
    this.status,
    this.message,
    this.state,
    this.info,
    this.telemetry,
    this.source,
    this.online,
    this.isUnauthorized = false,
    this.isMalformed = false,
  });

  final String? status;
  final String? message;
  final Map<String, dynamic>? state;
  final Map<String, dynamic>? info;
  final Map<String, dynamic>? telemetry;
  final String? source;
  final bool? online;
  final bool isUnauthorized;
  final bool isMalformed;
}

DeviceMessageResult parseDeviceMessage(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return const DeviceMessageResult(isMalformed: true);
    }

    final status = decoded['status'] as String?;
    final message = decoded['message'] as String?;
    final unauthorized = status == 'UNAUTHORIZED';

    Map<String, dynamic>? readMap(String key) {
      final value = decoded[key];
      return value is Map<String, dynamic> ? value : null;
    }

    return DeviceMessageResult(
      status: status,
      message: message,
      state: readMap('state'),
      info: readMap('info'),
      telemetry: readMap('telemetry'),
      source: decoded['source'] as String?,
      online: decoded['online'] is bool ? decoded['online'] as bool : null,
      isUnauthorized: unauthorized,
    );
  } catch (_) {
    return const DeviceMessageResult(isMalformed: true);
  }
}
