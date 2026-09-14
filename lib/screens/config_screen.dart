import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/relay_config.dart';
import '../models/relay_models.dart';
import '../services/relay_client.dart';
import 'actor_picker_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;

  bool _testing = false;
  String? _error;
  List<FoundryClientInfo> _clients = [];

  @override
  void initState() {
    super.initState();
    final config = context.read<RelayConfig>();
    _urlController = TextEditingController(text: config.baseUrl);
    _keyController = TextEditingController(text: config.apiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _error = null;
      _clients = [];
    });

    final config = context.read<RelayConfig>();
    await config.saveConnection(baseUrl: _urlController.text, apiKey: _keyController.text);
    final client = RelayClient(config);
    try {
      final clients = await client.getClients();
      setState(() => _clients = clients);
      if (clients.isEmpty) {
        setState(() => _error = 'Verbonden, maar geen Foundry-werelden gekoppeld aan deze API-key.');
      }
    } on RelayException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Onverwachte fout: $e');
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _chooseClient(FoundryClientInfo c) async {
    final config = context.read<RelayConfig>();
    await config.selectClient(clientId: c.clientId, label: c.worldTitle);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ActorPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Foundry Companion — Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Verbind met je zelf-gehoste foundryvtt-rest-api-relay. '
            'URL en API-key blijven alleen lokaal op dit toestel opgeslagen.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Relay-URL',
              hintText: 'http://192.168.178.19:3010',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'API-key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Test verbinding & haal werelden op'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_clients.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Kies een wereld:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final c in _clients)
              Card(
                child: ListTile(
                  leading: Icon(
                    c.isOnline ? Icons.circle : Icons.circle_outlined,
                    color: c.isOnline ? Colors.green : Colors.grey,
                    size: 14,
                  ),
                  title: Text(c.worldTitle),
                  subtitle: Text('${c.systemTitle}  ·  clientId: ${c.clientId}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseClient(c),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
