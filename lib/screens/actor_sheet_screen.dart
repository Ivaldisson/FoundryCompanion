import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/relay_config.dart';
import '../models/relay_models.dart';
import '../services/relay_client.dart';
import '../sheet_templates/sheet_template.dart';
import '../widgets/dynamic_json_view.dart';
import 'chat_screen.dart';

class _SheetData {
  final Map<String, dynamic> actor;
  final List<ActiveEffectInfo> effects;
  final String? effectsError;

  _SheetData({required this.actor, required this.effects, required this.effectsError});
}

class ActorSheetScreen extends StatefulWidget {
  final String uuid;
  final String name;

  const ActorSheetScreen({super.key, required this.uuid, required this.name});

  @override
  State<ActorSheetScreen> createState() => _ActorSheetScreenState();
}

class _ActorSheetScreenState extends State<ActorSheetScreen> {
  late final RelayClient _client;
  Future<_SheetData>? _future;

  @override
  void initState() {
    super.initState();
    _client = RelayClient(context.read<RelayConfig>());
    _load();
  }

  void _load() {
    setState(() {
      _future = _loadAll();
    });
  }

  Future<_SheetData> _loadAll() async {
    final actor = await _client.getEntity(widget.uuid);
    // Conditions are a nice-to-have on top of the core sheet — don't let a
    // missing effects:read scope on the API key take down the whole screen.
    List<ActiveEffectInfo> effects = [];
    String? effectsError;
    try {
      effects = await _client.getActiveEffects(widget.uuid);
    } on RelayException catch (e) {
      effectsError = e.message;
    }
    return _SheetData(actor: actor, effects: effects, effectsError: effectsError);
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  /// Generic roll dialog: pre-filled with [defaultFormula]/[defaultFlavor]
  /// under [title]. Used both for a tapped numeric leaf (title/formula
  /// derived from its raw value) and for a sheet template's computed rolls
  /// (e.g. `1d20 + <ability mod>`) — the dialog itself doesn't care where
  /// the default came from.
  Future<void> _openRollDialogFor({
    required String title,
    required String defaultFormula,
    required String defaultFlavor,
  }) async {
    final formulaController = TextEditingController(text: defaultFormula);
    final flavorController = TextEditingController(text: defaultFlavor);

    final formula = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      final roll = await _client.postRoll(
        formula: formula.trim(),
        flavor: flavorController.text.trim(),
        speaker: widget.uuid,
      );
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
      _showError(e.message);
    }
  }

  /// `DynamicJsonView.onTapNumber` — the generic tree only knows a leaf's
  /// raw path and value, so it gets the plainest possible roll: the value
  /// itself as a flat `1d20 + value` bonus.
  Future<void> _openRollForLeaf(String path, num value) => _openRollDialogFor(
        title: 'Roll — $path',
        defaultFormula: '1d20 + $value',
        defaultFlavor: path,
      );

  /// Long-press on a numeric leaf: quick -1/+1, or a custom amount, via the
  /// relay's dedicated `/increase`/`/decrease` endpoints — same JSON [path]
  /// the roll dialog uses, so this works for any numeric field on any
  /// system (HP, spell slots, item quantity, currency, ...) identically.
  Future<void> _openAdjustDialog(String path, num value) async {
    final amountController = TextEditingController(text: '1');

    final delta = await showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aanpassen — $path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Huidige waarde: $value', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context, -1),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(labelText: 'Bedrag', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context, 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleer')),
          FilledButton(
            onPressed: () {
              final custom = num.tryParse(amountController.text.trim().replaceAll(',', '.'));
              Navigator.pop(context, custom);
            },
            child: const Text('Toepassen'),
          ),
        ],
      ),
    );

    if (delta == null || delta == 0 || !mounted) return;
    await _applyAdjust(path, delta);
  }

  /// Applies [delta] to [path] with no dialog — for a sheet template's
  /// dedicated -/+ buttons (e.g. HP), where a quick ±1 is the common case
  /// and a confirmation step would just be friction. Shares the same
  /// underlying call as the dialog-driven `_openAdjustDialog` above.
  Future<void> _quickAdjust(String path, num delta) => _applyAdjust(path, delta);

  Future<void> _applyAdjust(String path, num delta) async {
    try {
      await _client.adjustAttribute(widget.uuid, path, delta);
      _load();
    } on RelayException catch (e) {
      _showError(e.message);
    }
  }

  /// Tap on a string/bool leaf: bools toggle straight away, strings open a
  /// small edit dialog. Both go through `PUT /update` with the same JSON
  /// [path] — no per-field knowledge needed.
  Future<void> _onEditLeaf(String path, dynamic currentValue) async {
    if (currentValue is bool) {
      try {
        await _client.updateField(widget.uuid, path, !currentValue);
        _load();
      } on RelayException catch (e) {
        _showError(e.message);
      }
      return;
    }

    final controller = TextEditingController(text: currentValue?.toString() ?? '');
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bewerken — $path'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleer')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    if (newText == null || !mounted) return;

    try {
      await _client.updateField(widget.uuid, path, newText);
      _load();
    } on RelayException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _openAddConditionDialog() async {
    List<EffectDefinition> options;
    try {
      options = await _client.getAvailableEffects();
    } on RelayException catch (e) {
      _showError(e.message);
      return;
    }
    if (!mounted) return;

    final chosen = await showDialog<EffectDefinition>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conditie toevoegen'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: options.isEmpty
              ? const Center(child: Text('Geen condities beschikbaar voor dit systeem.'))
              : ListView.builder(
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final o = options[i];
                    return ListTile(
                      leading: o.icon != null ? const Icon(Icons.shield_outlined) : null,
                      title: Text(o.name),
                      onTap: () => Navigator.pop(context, o),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleer')),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    try {
      await _client.addEffect(widget.uuid, chosen.id);
      _load();
    } on RelayException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _removeCondition(ActiveEffectInfo effect) async {
    try {
      await _client.removeEffect(widget.uuid, effect.id);
      _load();
    } on RelayException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
        child: FutureBuilder<_SheetData>(
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
            final data = snapshot.data!;
            final rawDataView = DynamicJsonView(
              value: data.actor,
              path: '',
              label: widget.name,
              onTapNumber: _openRollForLeaf,
              onLongPressNumber: _openAdjustDialog,
              onEditLeaf: _onEditLeaf,
            );
            final template = SheetTemplateRegistry.forSystem(context.read<RelayConfig>().systemId);

            return Column(
              children: [
                _ConditionsRow(
                  effects: data.effects,
                  error: data.effectsError,
                  onAdd: _openAddConditionDialog,
                  onRemove: _removeCondition,
                ),
                Expanded(
                  child: template != null
                      ? template.build(
                          context,
                          SheetTemplateContext(
                            uuid: widget.uuid,
                            actor: data.actor,
                            onRoll: _openRollDialogFor,
                            onAdjust: _openAdjustDialog,
                            onQuickAdjust: _quickAdjust,
                            onEditLeaf: _onEditLeaf,
                            rawDataView: rawDataView,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Text(
                                'Tik op een getal voor een roll, houd ingedrukt om aan te passen. '
                                'Tik op tekst/aan-uit om te bewerken. Volledige, onbewerkte actor-JSON — '
                                'geen system-specifieke velden.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                            ),
                            rawDataView,
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConditionsRow extends StatelessWidget {
  final List<ActiveEffectInfo> effects;
  final String? error;
  final VoidCallback onAdd;
  final void Function(ActiveEffectInfo) onRemove;

  const _ConditionsRow({
    required this.effects,
    required this.error,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Condities', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final effect in effects)
                  Chip(
                    label: Text(effect.name),
                    onDeleted: () => onRemove(effect),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Toevoegen'),
                  onPressed: onAdd,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
