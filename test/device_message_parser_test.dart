import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_pro/src/device_message_parser.dart';

void main() {
  test('parses state payload', () {
    const payload = '{"source":"MQTT","online":true,"state":{"light":true,"fan":false},"telemetry":{"wifi_rssi":-40}}';
    final result = parseDeviceMessage(payload);

    expect(result.isMalformed, isFalse);
    expect(result.state?['light'], isTrue);
    expect(result.state?['fan'], isFalse);
    expect(result.telemetry?['wifi_rssi'], -40);
  });

  test('detects unauthorized payload', () {
    const payload = '{"status":"UNAUTHORIZED","message":"Invalid PIN"}';
    final result = parseDeviceMessage(payload);

    expect(result.isUnauthorized, isTrue);
    expect(result.message, 'Invalid PIN');
  });

  test('handles malformed json safely', () {
    final result = parseDeviceMessage('{bad json');
    expect(result.isMalformed, isTrue);
  });
}
