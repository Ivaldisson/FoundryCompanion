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

  // Deliberately not a plain FutureBuilder-driven `Future<_SheetData>?`:
  // every edit (roll aside) calls `_load()` to refetch, and with a fresh
  // Future each time, FutureBuilder briefly hits ConnectionState.waiting —
  // which would replace the whole body with a spinner, tearing down and
  // recreating the dnd5e template's DefaultTabController and silently
  // resetting the user back to the first tab after every single edit.
  // Confirmed live: exactly this happened once the sheet grew tabs. Instead,
  // keep showing the last good `_data` while a reload is in flight — same
  // widget subtree, same TabController, tab selection survives.
  _SheetData? _data;
  String? _loadError;
  bool _initialLoad = true;

  @override
  void initState() {
    super.initState();
    _client = RelayClient(context.read<RelayConfig>());
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _loadAll();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadError = null;
        _initialLoad = false;
      });
    } on RelayException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _initialLoad = false;
      });
    }
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
  /// the default came from. Rolls are always attributed to the actor being
  /// viewed (not item-scoped — an item doesn't "speak" a roll).
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
              decoration: const InputDecoration(labelText: 'Formula', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: flavorController,
              decoration: const InputDecoration(labelText: 'Flavor text', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
  ///
  /// [targetUuid] defaults to the actor being viewed; a sheet template can
  /// override it to scope the write to an embedded item instead (e.g.
  /// `'${actorUuid}.Item.${itemId}'`) — confirmed live that `/update` (and,
  /// by the same mechanism, `/increase`/`/decrease`) resolves an item's own
  /// UUID and edits that document directly, since `items` is an embedded
  /// collection the actor's own UUID can't dot-path into.
  Future<void> _openAdjustDialog(String path, num value, {String? targetUuid}) async {
    final amountController = TextEditingController(text: '1');

    final delta = await showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust — $path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current value: $value', style: const TextStyle(color: Colors.grey)),
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
                    decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final custom = num.tryParse(amountController.text.trim().replaceAll(',', '.'));
              Navigator.pop(context, custom);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (delta == null || delta == 0 || !mounted) return;
    await _applyAdjust(path, delta, targetUuid: targetUuid);
  }

  /// Applies [delta] to [path] with no dialog — for a sheet template's
  /// dedicated -/+ buttons (e.g. HP), where a quick ±1 is the common case
  /// and a confirmation step would just be friction. Shares the same
  /// underlying call as the dialog-driven `_openAdjustDialog` above.
  Future<void> _quickAdjust(String path, num delta, {String? targetUuid}) =>
      _applyAdjust(path, delta, targetUuid: targetUuid);

  Future<void> _applyAdjust(String path, num delta, {String? targetUuid}) async {
    try {
      await _client.adjustAttribute(targetUuid ?? widget.uuid, path, delta);
      _load();
    } on RelayException catch (e) {
      _showError(e.message);
    }
  }

  /// Tap on a string/bool leaf: bools toggle straight away, strings open a
  /// small edit dialog. Both go through `PUT /update` with the same JSON
  /// [path] — no per-field knowledge needed. [targetUuid] defaults to the
  /// actor; see `_openAdjustDialog`'s doc comment for the item-scoped case.
  Future<void> _onEditLeaf(String path, dynamic currentValue, {String? targetUuid}) async {
    final uuid = targetUuid ?? widget.uuid;
    if (currentValue is bool) {
      try {
        await _client.updateField(uuid, path, !currentValue);
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
        title: Text('Edit — $path'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || !mounted) return;

    try {
      await _client.updateField(uuid, path, newText);
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
        title: const Text('Add condition'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: options.isEmpty
              ? const Center(child: Text('No conditions available for this system.'))
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
            tooltip: 'Chat log',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_initialLoad) {
        return const Center(child: CircularProgressIndicator());
      }
      final message = _loadError ?? 'Unknown error.';
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
        if (_loadError != null)
          Container(
            width: double.infinity,
            color: Colors.orange.withValues(alpha: 0.15),
            padding: const EdgeInsets.all(8),
            child: Text(
              'Could not refresh: $_loadError',
              style: const TextStyle(color: Colors.deepOrange),
            ),
          ),
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
                        'Tap a number to roll, long-press to adjust. '
                        'Tap text/on-off to edit. Full, unprocessed actor JSON — '
                        'no system-specific fields.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                    rawDataView,
                  ],
                ),
        ),
      ],
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
          Text('Conditions', style: Theme.of(context).textTheme.labelLarge),
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
                  label: const Text('Add'),
                  onPressed: onAdd,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
