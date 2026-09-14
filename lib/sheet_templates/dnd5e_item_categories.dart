/// Splits an actor's `items[]` (which Foundry uses for gear, spells, class
/// features, feats, race, and background alike — they're all `Item`
/// documents, just different `type` values) into the groups a traditional
/// dnd5e sheet shows separately: Inventory, Spells, Features.
///
/// Unknown/future item types are never dropped — they fall into an "Other"
/// bucket within whichever section is closest (Inventory), same "never
/// silently hide data" principle as the raw-data fallback elsewhere in this
/// app.
library;

const _spellTypes = {'spell'};
const _featureTypes = {'feat', 'class', 'subclass', 'race', 'background'};

/// Display order + label for inventory categories. Any `item.type` not
/// listed here still shows, grouped under "Other", at the end.
const inventoryTypeOrder = ['weapon', 'equipment', 'consumable', 'ammo', 'tool', 'container', 'backpack', 'loot'];
const inventoryTypeLabels = {
  'weapon': 'Weapons',
  'equipment': 'Equipment',
  'consumable': 'Consumables',
  'ammo': 'Ammunition',
  'tool': 'Tools',
  'container': 'Containers',
  'backpack': 'Containers',
  'loot': 'Loot',
};

/// Display order + label for feature categories.
const featureTypeOrder = ['race', 'background', 'class', 'subclass', 'feat'];
const featureTypeLabels = {
  'race': 'Race',
  'background': 'Background',
  'class': 'Class Features',
  'subclass': 'Subclass Features',
  'feat': 'Feats',
};

const spellLevelLabels = {
  0: 'Cantrips',
  1: '1st Level',
  2: '2nd Level',
  3: '3rd Level',
  4: '4th Level',
  5: '5th Level',
  6: '6th Level',
  7: '7th Level',
  8: '8th Level',
  9: '9th Level',
};

class CategorizedItems {
  /// Keyed by raw `item.type` (or `'other'` for unrecognized types) —
  /// present here means it's actual gear, not a spell or feature.
  final Map<String, List<Map<String, dynamic>>> inventoryByType;

  /// Keyed by `system.level` (0 = cantrip).
  final Map<int, List<Map<String, dynamic>>> spellsByLevel;

  /// Keyed by raw `item.type` (or `'other'`).
  final Map<String, List<Map<String, dynamic>>> featuresByType;

  const CategorizedItems({
    required this.inventoryByType,
    required this.spellsByLevel,
    required this.featuresByType,
  });

  int get inventoryCount => inventoryByType.values.fold(0, (sum, list) => sum + list.length);
  int get spellCount => spellsByLevel.values.fold(0, (sum, list) => sum + list.length);
  int get featureCount => featuresByType.values.fold(0, (sum, list) => sum + list.length);
}

CategorizedItems categorizeItems(List items) {
  final inventory = <String, List<Map<String, dynamic>>>{};
  final spells = <int, List<Map<String, dynamic>>>{};
  final features = <String, List<Map<String, dynamic>>>{};

  for (final raw in items) {
    if (raw is! Map) continue;
    final item = raw.cast<String, dynamic>();
    final type = item['type'] as String? ?? '';
    final system = (item['system'] as Map?)?.cast<String, dynamic>() ?? const {};

    if (_spellTypes.contains(type)) {
      final level = (system['level'] as num?)?.toInt() ?? 0;
      spells.putIfAbsent(level, () => []).add(item);
    } else if (_featureTypes.contains(type)) {
      final key = featureTypeLabels.containsKey(type) ? type : 'other';
      features.putIfAbsent(key, () => []).add(item);
    } else {
      final key = inventoryTypeLabels.containsKey(type) ? type : 'other';
      inventory.putIfAbsent(key, () => []).add(item);
    }
  }

  return CategorizedItems(inventoryByType: inventory, spellsByLevel: spells, featuresByType: features);
}
