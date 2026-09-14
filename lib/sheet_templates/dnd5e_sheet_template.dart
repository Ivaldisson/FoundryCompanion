import 'package:flutter/material.dart';

import 'dnd5e_formulas.dart';
import 'dnd5e_item_categories.dart';
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

typedef _RollFn = void Function({required String title, required String defaultFormula, required String defaultFlavor});
typedef _AdjustFn = void Function(String path, num value, {String? targetUuid});
typedef _EditLeafFn = void Function(String path, dynamic currentValue, {String? targetUuid});

/// Height of the always-visible HP/AC/Prof stat row pinned above the
/// [TabBar], as part of the [SliverAppBar]'s `bottom` — full size, same as
/// it always was; only the name/class line and ability grid collapse away.
/// Measured on-device rather than computed from font metrics (which
/// undershot badly the first time this header was built — `Card`'s
/// default margin and real line heights run bigger than estimated).
const _statRowHeight = 104.0;

/// Height of the part of the header that collapses away entirely on
/// scroll: just the name/class line and the ability score grid — HP/AC/
/// Prof live in the always-visible [_statRowHeight] row below and never
/// collapse. Also measured on-device.
const _collapsibleHeaderHeight = 222.0;

/// Total expanded height of the [SliverAppBar]: the collapsible part plus
/// the always-visible stat row and [TabBar] (the `bottom`), which stay
/// reserved even at full collapse.
const _headerExpandedHeight = _collapsibleHeaderHeight + _statRowHeight + kTextTabBarHeight;

String _formatAc(Map<String, dynamic> ac, int dexScore) {
  final calc = ac['calc'] as String?;
  final flat = (ac['flat'] as num?)?.toInt();
  final computed = defaultArmorClass(calc: calc, dexScore: dexScore);
  return computed?.toString() ?? flat?.toString() ?? '—';
}

/// Reference implementation of [SheetTemplate] — see that file's doc
/// comment and `TODO.md` for how to add one for another system.
///
/// Layout modeled on Tidy 5e Sheets (`kgar/foundry-vtt-tidy-5e-sheets`) as a
/// reference: a persistent header/HP/AC/ability-score summary, with the
/// bulk of the sheet organized into tabs mirroring that module's structure
/// (and the stock dnd5e sheet it's built on) — Skills & Saves, Inventory,
/// Spells, Features, plus Raw Data as this app's own always-available
/// fallback. Tidy5e's desktop-specific features (grid view, drag-and-drop,
/// search) aren't replicated — what's borrowed is the organization, not a
/// pixel clone.
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
    final categorized = categorizeItems(items);

    return DefaultTabController(
      length: 5,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              forceElevated: innerBoxIsScrolled,
              pinned: true,
              floating: true,
              expandedHeight: _headerExpandedHeight,
              // Only the name/class line and ability grid collapse away —
              // HP/AC/Prof live in the always-visible compact row in
              // `bottom` below, not duplicated up here.
              flexibleSpace: FlexibleSpaceBar(
                background: SingleChildScrollView(
                  // Never actually scrolls (the outer NestedScrollView owns
                  // scrolling) — just lets the background lay out at its
                  // natural height without a RenderFlex overflow error if
                  // _collapsibleHeaderHeight is ever a bit too tight.
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      children: [
                        _Header(
                          name: ctx.actor['name'] as String? ?? '',
                          level: level,
                          classLine: _classLine(items),
                          onEditName: () => ctx.onEditLeaf('name', ctx.actor['name']),
                        ),
                        const SizedBox(height: 12),
                        _AbilitiesGrid(abilities: abilities, onRoll: ctx.onRoll, onAdjust: ctx.onAdjust),
                      ],
                    ),
                  ),
                ),
              ),
              // A persistent, always-pinned strip below the collapsible
              // header: the HP/AC/Prof boxes at full size (never shrunk —
              // only the name/class line and ability grid above collapse
              // away), then the TabBar. (An earlier version shrank these
              // boxes down here, and an even earlier one replaced them with
              // a plain text summary via FlexibleSpaceBar's `title` — that
              // crossfade reservation didn't hold up under NestedScrollView
              // in practice, so this is a plain always-visible row.)
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(_statRowHeight + kTextTabBarHeight),
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _statRowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: _StatRow(
                            attributes: attributes,
                            dexScore: dexScore,
                            prof: prof,
                            onAdjust: ctx.onAdjust,
                            onQuickAdjust: ctx.onQuickAdjust,
                          ),
                        ),
                      ),
                      const TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          Tab(text: 'Skills & Saves'),
                          Tab(text: 'Inventory'),
                          Tab(text: 'Spells'),
                          Tab(text: 'Features'),
                          Tab(text: 'Raw Data'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _SkillsSavesTab(abilities: abilities, skills: skills, prof: prof, onRoll: ctx.onRoll),
            _InventoryTab(
              actorUuid: ctx.uuid,
              currency: currency,
              categorized: categorized,
              onAdjust: ctx.onAdjust,
              onEditLeaf: ctx.onEditLeaf,
            ),
            _SpellsTab(
              actorUuid: ctx.uuid,
              categorized: categorized,
              system: system,
              onEditLeaf: ctx.onEditLeaf,
            ),
            _FeaturesTab(categorized: categorized),
            _TabBody(tabId: 'raw', children: [ctx.rawDataView]),
          ],
        ),
      ),
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

/// The HP/AC/Prof row — a small widget purely so it's built once (used
/// only in the always-visible strip above the [TabBar] now — the name/class
/// line and ability grid are the only things that collapse on scroll).
class _StatRow extends StatelessWidget {
  final Map<String, dynamic> attributes;
  final int dexScore;
  final int prof;
  final _AdjustFn onAdjust;
  final _AdjustFn onQuickAdjust;

  const _StatRow({
    required this.attributes,
    required this.dexScore,
    required this.prof,
    required this.onAdjust,
    required this.onQuickAdjust,
  });

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight gives the Row a bounded height to stretch into —
    // plain CrossAxisAlignment.stretch on a Row throws at layout time when
    // the Row's own height is unbounded. Confirmed by bisection on-device.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: _HpCard(attributes: attributes, onAdjust: onAdjust, onQuickAdjust: onQuickAdjust),
          ),
          const SizedBox(width: 8),
          Expanded(child: _AcCard(attributes: attributes, dexScore: dexScore)),
          const SizedBox(width: 8),
          Expanded(child: _StatCard(label: 'Prof', value: '+$prof')),
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
  final _AdjustFn onAdjust;
  final _AdjustFn onQuickAdjust;

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
    final computed = defaultArmorClass(calc: ac['calc'] as String?, dexScore: dexScore);
    return _StatCard(
      label: computed == null ? 'AC (see raw data)' : 'Armor Class',
      value: _formatAc(ac, dexScore),
    );
  }
}

/// Two even rows of up to three cards each (str/dex/con, int/wis/cha for a
/// full ability set), rather than a left-leaning [Wrap] that split 6 fixed-
/// width cards into an uneven 4-then-2 layout.
class _AbilitiesGrid extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final _RollFn onRoll;
  final _AdjustFn onAdjust;

  const _AbilitiesGrid({required this.abilities, required this.onRoll, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final presentKeys = _abilityLabels.keys.where((k) => abilities[k] is Map).toList();
    final rows = <List<String>>[
      for (var i = 0; i < presentKeys.length; i += 3)
        presentKeys.sublist(i, i + 3 > presentKeys.length ? presentKeys.length : i + 3),
    ];

    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < rows[r].length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _AbilityCard(
                    abilityKey: rows[r][i],
                    abilities: abilities,
                    onRoll: onRoll,
                    onAdjust: onAdjust,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _AbilityCard extends StatelessWidget {
  final String abilityKey;
  final Map<String, dynamic> abilities;
  final _RollFn onRoll;
  final _AdjustFn onAdjust;

  const _AbilityCard({
    required this.abilityKey,
    required this.abilities,
    required this.onRoll,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ability = (abilities[abilityKey] as Map).cast<String, dynamic>();
    final score = (ability['value'] as num?)?.toInt() ?? 10;
    final mod = abilityModifier(score);
    final label = _abilityLabels[abilityKey]!;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onRoll(
        title: '$label check',
        defaultFormula: '1d20 + $mod',
        defaultFlavor: '$label check',
      ),
      onLongPress: () => onAdjust('system.abilities.$abilityKey.value', score),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
            Text(mod >= 0 ? '+$mod' : '$mod',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
            Text('$score', style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

/// Sliver-based stand-in for a plain `ListView` as a [TabBarView] child
/// inside [NestedScrollView] — each tab needs its own [CustomScrollView]
/// (with a distinct [PageStorageKey] so tabs don't fight over scroll
/// position) plus a [SliverOverlapInjector] matching the header's
/// [SliverOverlapAbsorber], or the collapsing header above doesn't lay out
/// correctly against per-tab scrolling. See the Flutter cookbook's
/// "NestedScrollView with TabBar" sample, which this mirrors.
class _TabBody extends StatelessWidget {
  final String tabId;
  final List<Widget> children;

  const _TabBody({required this.tabId, required this.children});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: PageStorageKey<String>(tabId),
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ],
    );
  }
}

class _SkillsSavesTab extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final Map<String, dynamic> skills;
  final int prof;
  final _RollFn onRoll;

  const _SkillsSavesTab({required this.abilities, required this.skills, required this.prof, required this.onRoll});

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      tabId: 'skills',
      children: [
        _SectionLabel('Saving Throws'),
        _SavesList(abilities: abilities, prof: prof, onRoll: onRoll),
        const SizedBox(height: 16),
        _SectionLabel('Skills'),
        _SkillsList(abilities: abilities, skills: skills, prof: prof, onRoll: onRoll),
      ],
    );
  }
}

class _SavesList extends StatelessWidget {
  final Map<String, dynamic> abilities;
  final int prof;
  final _RollFn onRoll;

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
  final _RollFn onRoll;

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
  final _AdjustFn onAdjust;

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

/// Currency at the top (Tidy5e keeps it inventory-adjacent), then actual
/// gear grouped by type — class features/spells/race/background never show
/// up here, they're all Foundry `Item` documents too but get split out by
/// `categorizeItems` into their own tabs.
class _InventoryTab extends StatelessWidget {
  final String actorUuid;
  final Map<String, dynamic> currency;
  final CategorizedItems categorized;
  final _AdjustFn onAdjust;
  final _EditLeafFn onEditLeaf;

  const _InventoryTab({
    required this.actorUuid,
    required this.currency,
    required this.categorized,
    required this.onAdjust,
    required this.onEditLeaf,
  });

  @override
  Widget build(BuildContext context) {
    final orderedKeys = [
      ...inventoryTypeOrder.where((k) => categorized.inventoryByType.containsKey(k)),
      if (categorized.inventoryByType.containsKey('other')) 'other',
    ];

    return _TabBody(
      tabId: 'inventory',
      children: [
        _SectionLabel('Currency'),
        _CurrencyRow(currency: currency, onAdjust: onAdjust),
        const SizedBox(height: 16),
        if (categorized.inventoryCount == 0)
          const Text('No items.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
        else
          for (final key in orderedKeys) ...[
            _SectionLabel(inventoryTypeLabels[key] ?? 'Other'),
            for (final item in categorized.inventoryByType[key]!)
              _InventoryItemRow(actorUuid: actorUuid, item: item, onAdjust: onAdjust, onEditLeaf: onEditLeaf),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _InventoryItemRow extends StatelessWidget {
  final String actorUuid;
  final Map<String, dynamic> item;
  final _AdjustFn onAdjust;
  final _EditLeafFn onEditLeaf;

  const _InventoryItemRow({
    required this.actorUuid,
    required this.item,
    required this.onAdjust,
    required this.onEditLeaf,
  });

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '(unnamed)';
    final itemId = item['_id'] as String?;
    final itemUuid = itemId == null ? null : '$actorUuid.Item.$itemId';
    final system = ((item['system'] as Map?)?.cast<String, dynamic>()) ?? {};
    final quantity = system['quantity'] as num?;
    final equipped = system['equipped'];
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          if (equipped is bool)
            InkWell(
              onTap: itemUuid == null
                  ? null
                  : () => onEditLeaf('system.equipped', equipped, targetUuid: itemUuid),
              child: Icon(
                equipped ? Icons.check_circle : Icons.check_circle_outline,
                size: 16,
                color: equipped ? scheme.primary : Colors.grey,
              ),
            ),
          if (quantity != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: itemUuid == null ? null : () => onAdjust('system.quantity', quantity, targetUuid: itemUuid),
              child: Text('×${quantity.toInt()}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpellsTab extends StatelessWidget {
  final String actorUuid;
  final CategorizedItems categorized;
  final Map<String, dynamic> system;
  final _EditLeafFn onEditLeaf;

  const _SpellsTab({
    required this.actorUuid,
    required this.categorized,
    required this.system,
    required this.onEditLeaf,
  });

  @override
  Widget build(BuildContext context) {
    final levels = categorized.spellsByLevel.keys.toList()..sort();
    final spellsSystem = ((system['spells'] as Map?)?.cast<String, dynamic>()) ?? {};

    return _TabBody(
      tabId: 'spells',
      children: [
        if (categorized.spellCount == 0)
          const Text('No spells.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
        else
          for (final level in levels) ...[
            _SectionLabel(_levelHeading(level, spellsSystem)),
            for (final item in categorized.spellsByLevel[level]!)
              _SpellRow(actorUuid: actorUuid, item: item, onEditLeaf: onEditLeaf),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  String _levelHeading(int level, Map<String, dynamic> spellsSystem) {
    final label = spellLevelLabels[level] ?? 'Level $level';
    if (level == 0) return label;
    final slotValue = (spellsSystem['spell$level'] as Map?)?['value'];
    return slotValue is num ? '$label ($slotValue slots)' : label;
  }
}

class _SpellRow extends StatelessWidget {
  final String actorUuid;
  final Map<String, dynamic> item;
  final _EditLeafFn onEditLeaf;

  const _SpellRow({required this.actorUuid, required this.item, required this.onEditLeaf});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '(unnamed)';
    final itemId = item['_id'] as String?;
    final itemUuid = itemId == null ? null : '$actorUuid.Item.$itemId';
    final preparation = ((item['system'] as Map?)?['preparation']);
    final prepared = preparation is Map ? preparation['prepared'] : null;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          if (prepared is bool)
            InkWell(
              onTap: itemUuid == null
                  ? null
                  : () => onEditLeaf('system.preparation.prepared', prepared, targetUuid: itemUuid),
              child: Icon(
                prepared ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: prepared ? scheme.primary : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }
}

/// Class features, feats, race, and background — display-only. There's no
/// generically meaningful "adjust" for a feature the way there is for HP or
/// item quantity, so these just link the reader to "Raw Data" for anything
/// deeper.
class _FeaturesTab extends StatelessWidget {
  final CategorizedItems categorized;

  const _FeaturesTab({required this.categorized});

  @override
  Widget build(BuildContext context) {
    final orderedKeys = [
      ...featureTypeOrder.where((k) => categorized.featuresByType.containsKey(k)),
      if (categorized.featuresByType.containsKey('other')) 'other',
    ];

    return _TabBody(
      tabId: 'features',
      children: [
        if (categorized.featureCount == 0)
          const Text('No features.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
        else
          for (final key in orderedKeys) ...[
            _SectionLabel(featureTypeLabels[key] ?? 'Other'),
            for (final item in categorized.featuresByType[key]!)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(item['name'] as String? ?? '(unnamed)', style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}
