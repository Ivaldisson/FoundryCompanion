import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foundry_companion/config/relay_config.dart';
import 'package:foundry_companion/main.dart';

void main() {
  testWidgets('App boots to the config screen when unconfigured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RelayConfig()..load(),
        child: const FoundryCompanionApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foundry Companion — Setup'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Relay-URL'), findsOneWidget);
  });
}
