import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foundry_companion/config/relay_config.dart';
import 'package:foundry_companion/main.dart';

/// `flutter_secure_storage` has no official test-mode mock (unlike
/// `shared_preferences`), so fake its platform channel directly — an empty
/// store is all `RelayConfig` needs to boot into "unconfigured".
void _mockSecureStorage() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return false;
        default:
          return null;
      }
    },
  );
}

void main() {
  testWidgets('App boots to the config screen when unconfigured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    _mockSecureStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RelayConfig()..load(),
        child: const FoundryCompanionApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foundry Companion — Setup'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Relay URL'), findsOneWidget);
  });
}
