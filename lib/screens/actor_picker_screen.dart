import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/relay_config.dart';
import '../models/relay_models.dart';
import '../services/relay_client.dart';
import 'actor_sheet_screen.dart';
import 'config_screen.dart';

class ActorPickerScreen extends StatefulWidget {
  const ActorPickerScreen({super.key});

  @override
  State<ActorPickerScreen> createState() => _ActorPickerScreenState();
}

class _ActorPickerScreenState extends State<ActorPickerScreen> {
  late final RelayClient _client;
  Future<List<SearchResult>>? _future;

  @override
  void initState() {
    super.initState();
    _client = RelayClient(context.read<RelayConfig>());
    _load();
  }

  void _load() {
    setState(() {
      _future = _client.searchActors();
    });
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<RelayConfig>();
    return Scaffold(
      appBar: AppBar(
        title: Text(config.clientLabel ?? 'Actors'),
        actions: [
          IconButton(
            tooltip: 'Change connection',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConfigScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: FutureBuilder<List<SearchResult>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message =
                  snapshot.error is RelayException ? (snapshot.error as RelayException).message : '${snapshot.error}';
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
            final actors = snapshot.data ?? [];
            if (actors.isEmpty) {
              return const Center(child: Text('No actors found in this world.'));
            }
            return ListView.separated(
              itemCount: actors.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = actors[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(a.name),
                  subtitle: Text(a.subType ?? a.documentType),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ActorSheetScreen(uuid: a.uuid, name: a.name)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
