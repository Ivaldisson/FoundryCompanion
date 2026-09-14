import 'package:flutter_test/flutter_test.dart';
import 'package:foundry_companion/sheet_templates/dnd5e_item_categories.dart';

Map<String, dynamic> _item(String name, String type, [Map<String, dynamic> system = const {}]) {
  return {'name': name, 'type': type, 'system': system};
}

void main() {
  group('categorizeItems', () {
    test('buckets gear, spells, and features separately', () {
      final items = [
        _item('Dagger', 'weapon'),
        _item('Fireball', 'spell', {'level': 3}),
        _item('Mage Armor', 'spell', {'level': 1}),
        _item('Ray of Frost', 'spell', {'level': 0}),
        _item('Alertness', 'feat'),
        _item('Human', 'race'),
      ];

      final result = categorizeItems(items);

      expect(result.inventoryByType['weapon']?.map((i) => i['name']), ['Dagger']);
      expect(result.spellsByLevel[3]?.single['name'], 'Fireball');
      expect(result.spellsByLevel[1]?.single['name'], 'Mage Armor');
      expect(result.spellsByLevel[0]?.single['name'], 'Ray of Frost');
      expect(result.featuresByType['feat']?.single['name'], 'Alertness');
      expect(result.featuresByType['race']?.single['name'], 'Human');
    });

    test('an unrecognized item type falls into "other" inventory, not lost', () {
      final items = [_item('Mystery Widget', 'someFutureType')];

      final result = categorizeItems(items);

      expect(result.inventoryByType['other']?.single['name'], 'Mystery Widget');
      expect(result.inventoryCount, 1);
    });

    test('spell with no explicit level defaults to cantrip (0)', () {
      final result = categorizeItems([_item('Prestidigitation', 'spell')]);

      expect(result.spellsByLevel[0]?.single['name'], 'Prestidigitation');
    });

    test('counts add up and empty input yields empty buckets', () {
      final result = categorizeItems([]);
      expect(result.inventoryCount, 0);
      expect(result.spellCount, 0);
      expect(result.featureCount, 0);
    });

    test('non-map entries in items are skipped rather than throwing', () {
      final result = categorizeItems([_item('Dagger', 'weapon'), 'not a map', 42, null]);
      expect(result.inventoryCount, 1);
    });
  });
}
