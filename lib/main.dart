import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/relay_config.dart';
import 'screens/actor_picker_screen.dart';
import 'screens/config_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => RelayConfig()..load(),
      child: const FoundryCompanionApp(),
    ),
  );
}

class FoundryCompanionApp extends StatelessWidget {
  const FoundryCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foundry Companion',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _Gate(),
    );
  }
}

/// Routes to setup or straight into the actor list, depending on whether a
/// relay connection + world was already configured on this device.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<RelayConfig>();
    if (!config.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return config.isComplete ? const ActorPickerScreen() : const ConfigScreen();
  }
}
