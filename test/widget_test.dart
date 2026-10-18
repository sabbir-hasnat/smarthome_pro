import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthome_pro/main.dart';
import 'package:smarthome_pro/src/app_settings_controller.dart';

void main() {
  testWidgets('app shows localized root screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'en',
      'app_theme_mode': 'system',
      'saved_devices': '[]',
    });

    final settings = AppSettingsController();
    await settings.load();

    await tester.pumpWidget(SmartHomeProApp(settings: settings));
    await tester.pumpAndSettle();

    expect(find.text('My Devices'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  test('theme mode codec is stable', () {
    expect(
      AppSettingsController.decodeThemeMode('dark'),
      ThemeMode.dark,
    );
    expect(
      AppSettingsController.encodeThemeMode(ThemeMode.light),
      'light',
    );
  });
}
