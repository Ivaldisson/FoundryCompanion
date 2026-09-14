import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/relay_config.dart';
import '../services/relay_client.dart';
import '../widgets/dynamic_json_view.dart';
import 'chat_screen.dart';

class ActorSheetScreen extends StatefulWidget {
  final String uuid;
  final String name;

  const ActorSheetScreen({super.key, required this.uuid, required this.name});

  @override
  State<ActorSheetScreen> createState() => _ActorSheetScreenState();
}

class _ActorSheetScreenState extends State<ActorSheetScreen> {
  late final RelayClient _client;
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _client = RelayClient(context.read<RelayConfig>());
    _load();
  }

  void _load() {
    setState(() {
      _future = _client.getEntity(widget.uuid);
    });
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _openRollDialog(String path, num value) async {
    final formulaController = TextEditingController(text: '1d20 + $value');
    final flavorController = TextEditingController(text: path);

    final formula = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Roll — $path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Aangetikte waarde: $value', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: formulaController,
              decoration: const InputDecoration(labelText: 'Formule', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: flavorController,
              decoration: const InputDecoration(labelText: 'Flavor tekst', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleer')),
          FilledButton.icon(
            icon: const Icon(Icons.casino),
            onPressed: () => Navigator.pop(context, formulaController.text),
            label: const Text('Roll'),
          ),
        ],
      ),
    );

    if (formula == null || formula.trim().isEmpty || !mounted) return;

    try {
      final roll = await _client.postRoll(formula: formula.trim(), flavor: flavorController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${roll.formula} = ${roll.total}'
              '${roll.isCritical ? "  CRIT!" : ""}${roll.isFumble ? "  FUMBLE!" : ""}'),
          action: SnackBarAction(
            label: 'Chat',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
        ),
      );
    } on RelayException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: 'Chatlog',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is RelayException
                  ? (snapshot.error as RelayException).message
                  : '${snapshot.error}';
              return ListView(
                children: [
                  const SizedBox(height: 60),
                  Icon(Icons.error_outline, size: 40, color: Colors.red[300]),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(message, textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            final actor = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Tik op een getal om er een roll van te maken. '
                    'Dit is de volledige, onbewerkte actor-JSON — geen system-specifieke velden.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
                DynamicJsonView(
                  value: actor,
                  path: '',
                  label: widget.name,
                  onTapNumber: _openRollDialog,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
