import 'package:flutter/material.dart';

import 'dnd5e_formulas.dart';
import 'sheet_template.dart';

const _abilityLabels = {
  'str': 'STR',
  'dex': 'DEX',
  'con': 'CON',
  'int': 'INT',
  'wis': 'WIS',
  'cha': 'CHA',
};

const _skillLabels = {
  'acr': 'Acrobatics',
  'ani': 'Animal Handling',
  'arc': 'Arcana',
  'ath': 'Athletics',
  'dec': 'Deception',
  'his': 'History',
  'ins': 'Insight',
  'itm': 'Intimidation',
  'inv': 'Investigation',
  'med': 'Medicine',
  'nat': 'Nature',
  'prc': 'Perception',
  'prf': 'Performance',
  'per': 'Persuasion',
  'rel': 'Religion',
  'slt': 'Sleight of Hand',
  'ste': 'Stealth',
  'sur': 'Survival',
};

/// Reference implementation of [SheetTemplate] — see that file's doc
/// comment and `TODO.md` for how to add one for another system.
///
/// Only handles `type == "character"` actors; NPCs/vehicles in a dnd5e
/// world still get the generic tree (no bogus half-populated "character
/// sheet" for a monster stat block whose fields don't line up).
class Dnd5eSheetTemplate implements SheetTemplate {
  const Dnd5eSheetTemplate();

  @override
  bool matches(String? systemId) => systemId == 'dnd5e';

  @override
  Widget build(BuildContext context, SheetTemplateContext ctx) {
    // If this actor's data doesn't fit the shape the template expects,
    // fall back to the generic tree rather than showing a broken sheet —
    // same "always usable, never just wrong" principle as the rest of the
    // app's error handling.
    try {
      return _buildReal(context, ctx);
    } catch (_) {
      return ctx.rawDataView;
    }
  }

  Widget _buildReal(BuildContext context, SheetTemplateContext ctx) {
    if (ctx.actor['type'] != 'character') {
      return ctx.rawDataView;
    }

    final system = ((ctx.actor['system'] as Map?)?.cast<String, dynamic>()) ?? {};
    final abilities = ((system['abilities'] as Map?)?.cast<String, dynamic>()) ?? {};
    final attributes = ((system['attributes'] as Map?)?.cast<String, dynamic>()) ?? {};
    final skills = ((system['skills'] as Map?)?.cast<String, dynamic>()) ?? {};
    final currency = ((system['currency'] as Map?)?.cast<String, dynamic>()) ?? {};
    final items = (ctx.actor['items'] as List?) ?? [];
    final details = ((system['details'] as Map?)?.cast<String, dynamic>()) ?? {};

    final level = _totalLevel(details, items);
    final prof = proficiencyBonus(level);
    final dexScore = ((abilities['dex'] as Map?)?['value'] as num?)?.toInt() ?? 10;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Header(
          name: ctx.actor['name'] as String? ?? '',
          level: level,
          classLine: _classLine(items),
          onEditName: () => ctx.onEditLeaf('name', ctx.actor['name']),
        ),
        const SizedBox(height: 12),
        // IntrinsicHeight gives the Row a bounded height to stretch into —
        // plain CrossAxisAlignment.stretch on a Row throws at layout time
        // when the Row's own height is unbounded (as any direct ListView
        // child's is), which silently blanks the whole list with no visible
        // error on some renderers/devices. Confirmed by bisection on-device.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _HpCard(attributes: attributes, onAdjust: ctx.onAdjust, onQuickAdjust: ctx.onQuickAdjust),
              ),
              const SizedBox(width: 8),
              Expanded(child: _AcCard(attributes: attributes, dexScore: dexScore)),
              const SizedBox(width: 8),
              Expanded(child: _StatCard(label: 'Prof', value: '+$prof')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Ability Scores'),
        _AbilitiesGrid(abilities: abilities, onRoll: ctx.onRoll, onAdjust: ctx.onAdjust),
        const SizedBox(height: 16),
        _SectionLabel('Saving Throws'),
        _SavesList(abilities: abilities, prof: prof, onRoll: ctx.onRoll),
        const SizedBox(height: 16),
        _SectionLabel('Skills'),
        _SkillsList(abilities: abilities, skills: skills, prof: prof, onRoll: ctx.onRoll),
        const SizedBox(height: 16),
        _SectionLabel('Currency'),
        _CurrencyRow(currency: currency, onAdjust: ctx.onAdjust),
        const SizedBox(height: 16),
        _SectionLabel('Items (${items.length})'),
        _ItemsList(items: items),
        const SizedBox(height: 16),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: const Text('Ruwe data', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Alle velden, inclusief wat hierboven niet getoond wordt',
                style: TextStyle(fontSize: 11)),
            children: [ctx.rawDataView],
          ),
        ),
      ],
    );
  }

  int _totalLevel(Map<String, dynamic> details, List items) {
    final stored = details['level'];
    if (stored is num && stored > 0) return stored.toInt();
    var sum = 0;
    for (final item in items) {
      if (item is! Map || item['type'] != 'class') continue;
      final levels = ((item['system'] as Map?)?['levels'] as num?)?.toInt() ?? 0;
      sum += levels;
    }
    return sum > 0 ? sum : 1;
  }

  String? _classLine(List items) {
    final classNames = <String>[];
    for (final item in items) {
      if (item is! Map || item['type'] != 'class') continue;
      final name = item['name'] as String?;
      final levels = ((item['system'] as Map?)?['levels'] as num?)?.toInt();
      if (name == null) continue;
      classNames.add(levels != null ? '$name $levels' : name);
    }
    return classNames.isEmpty ? null : classNames.join(' / ');
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final int level;
  final String? classLine;
  final VoidCallback onEditName;

  const _Header({required this.name, required this.level, required this.classLine, required this.onEditName});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEditName,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  classLine != null ? '$classLine — Level $level' : 'Level $level',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _HpCard extends StatelessWidget {
  final Map<String, dynamic> attributes;
  final void Function(String path, num value) onAdjust;
  final void Function(String path, num delta) onQuickAdjust;

  const _HpCard({required this.attributes, required this.onAdjust, required this.onQuickAdjust});

  static const _path = 'system.attributes.hp.value';

  static Widget _iconButton({required IconData icon, required VoidCallback onPressed}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      iconSize: 18,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hp = ((attributes['hp'] as Map?)?.cast<String, dynamic>()) ?? {};
    final value = (hp['value'] as num?) ?? 0;
    final max = (hp['max'] as num?) ?? 0;
    final temp = (hp['temp'] as num?) ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hit Points', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconButton(icon: Icons.remove_circle_outline, onPressed: () => onQuickAdjust(_path, -1)),
                Flexible(
                  child: InkWell(
                    onTap: () => onAdjust(_path, value),
                    child: FittedBox(
                      child: Text('${value.toInt()} / ${max.toInt()}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                _iconButton(icon: Icons.add_circle_outline, onPressed: () => onQuickAdjust(_path, 1)),
              ],
            ),
            if (temp > 0) Text('+$temp temp', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _AcCard extends StatelessWidget {
  final Map<String, dynamic> attributes;
  final int dexScore;

  const _AcCard({required this.attributes, required this.dexScore});

  @override
  Widget build(BuildContext context) {
    final ac = ((attributes['ac'] as Map?)?.cast<String, dynamic>()) ?? {};
    final calc = ac['calc'] as String?;
    final flat = (ac['flat'] as num?)?.toInt();
    final computed = defaultArmorClass(calc: calc, dexScore: dexScore);
    final display = computed?.toString() ?? flat?.toString() ?? '—';
    return _StatCard(
      label: computed == null ? 'AC (zie ruwe data)' : 'Armor Class',
      value: display,
    );
  }
}

class _AbilitiesGrid extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final void Function({required String title, required String defaultFormula, required String defaultFlavor}) onRoll;
  final void Function(String path, num value) onAdjust;

  const _AbilitiesGrid({required this.abilities, required this.onRoll, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in _abilityLabels.keys)
          if (abilities[key] is Map)
            Builder(builder: (context) {
              final ability = (abilities[key] as Map).cast<String, dynamic>();
              final score = (ability['value'] as num?)?.toInt() ?? 10;
              final mod = abilityModifier(score);
              return InkWell(
                onTap: () => onRoll(
                  title: '${_abilityLabels[key]} check',
                  defaultFormula: '1d20 + $mod',
                  defaultFlavor: '${_abilityLabels[key]} check',
                ),
                onLongPress: () => onAdjust('system.abilities.$key.value', score),
                child: Container(
                  width: 76,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_abilityLabels[key]!,
                          style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
                      Text(mod >= 0 ? '+$mod' : '$mod',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                      Text('$score', style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
              );
            }),
      ],
    );
  }
}

class _SavesList extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final int prof;
  final void Function({required String title, required String defaultFormula, required String defaultFlavor}) onRoll;

  const _SavesList({required this.abilities, required this.prof, required this.onRoll});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final key in _abilityLabels.keys)
          if (abilities[key] is Map)
            Builder(builder: (context) {
              final ability = (abilities[key] as Map).cast<String, dynamic>();
              final score = (ability['value'] as num?)?.toInt() ?? 10;
              final proficient = (ability['proficient'] as num?) ?? 0;
              final bonus = scaledBonus(abilityScore: score, proficiencyBonusValue: prof, multiplier: proficient);
              return _BonusRow(
                label: '${_abilityLabels[key]} Save',
                bonus: bonus,
                proficient: proficient > 0,
                onTap: () => onRoll(
                  title: '${_abilityLabels[key]} save',
                  defaultFormula: '1d20 + $bonus',
                  defaultFlavor: '${_abilityLabels[key]} saving throw',
                ),
              );
            }),
      ],
    );
  }
}

class _SkillsList extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final Map<String, dynamic> skills;
  final int prof;
  final void Function({required String title, required String defaultFormula, required String defaultFlavor}) onRoll;

  const _SkillsList({required this.abilities, required this.skills, required this.prof, required this.onRoll});

  @override
  Widget build(BuildContext context) {
    final entries = _skillLabels.entries.where((e) => skills[e.key] is Map).toList();
    return Column(
      children: [
        for (final entry in entries)
          Builder(builder: (context) {
            final skill = (skills[entry.key] as Map).cast<String, dynamic>();
            final abilityKey = skill['ability'] as String? ?? 'str';
            final abilityScore = ((abilities[abilityKey] as Map?)?['value'] as num?)?.toInt() ?? 10;
            final multiplier = (skill['value'] as num?) ?? 0;
            final bonus = scaledBonus(abilityScore: abilityScore, proficiencyBonusValue: prof, multiplier: multiplier);
            return _BonusRow(
              label: entry.value,
              bonus: bonus,
              proficient: multiplier > 0,
              onTap: () => onRoll(
                title: entry.value,
                defaultFormula: '1d20 + $bonus',
                defaultFlavor: entry.value,
              ),
            );
          }),
      ],
    );
  }
}

class _BonusRow extends StatelessWidget {
  final String label;
  final int bonus;
  final bool proficient;
  final VoidCallback onTap;

  const _BonusRow({required this.label, required this.bonus, required this.proficient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: proficient ? scheme.primary : Colors.grey[400]),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(bonus >= 0 ? '+$bonus' : '$bonus',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.casino_outlined, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  final Map<String, dynamic> currency;
  final void Function(String path, num value) onAdjust;

  const _CurrencyRow({required this.currency, required this.onAdjust});

  static const _labels = {'pp': 'PP', 'gp': 'GP', 'ep': 'EP', 'sp': 'SP', 'cp': 'CP'};

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in _labels.keys)
          if (currency[key] is num)
            InkWell(
              onTap: () => onAdjust('system.currency.$key', currency[key] as num),
              child: Chip(label: Text('${_labels[key]} ${currency[key]}')),
            ),
      ],
    );
  }
}

class _ItemsList extends StatelessWidget {
  final List items;

  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Geen items.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
    }
    return Column(
      children: [
        for (final item in items)
          if (item is Map)
            _ItemRow(item: item.cast<String, dynamic>()),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '(zonder naam)';
    final itemSystem = ((item['system'] as Map?)?.cast<String, dynamic>()) ?? {};
    final quantity = itemSystem['quantity'] as num?;
    final equipped = itemSystem['equipped'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          if (equipped == true) const Icon(Icons.check_circle_outline, size: 15, color: Colors.grey),
          if (quantity != null) ...[
            const SizedBox(width: 6),
            Text('×${quantity.toInt()}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}
