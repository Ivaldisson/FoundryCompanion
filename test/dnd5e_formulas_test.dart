import 'package:flutter_test/flutter_test.dart';
import 'package:foundry_companion/sheet_templates/dnd5e_formulas.dart';

void main() {
  group('abilityModifier', () {
    test('standard score boundaries', () {
      expect(abilityModifier(10), 0);
      expect(abilityModifier(11), 0);
      expect(abilityModifier(8), -1);
      expect(abilityModifier(9), -1);
      expect(abilityModifier(12), 1);
      expect(abilityModifier(20), 5);
      expect(abilityModifier(1), -5);
    });
  });

  group('proficiencyBonus', () {
    test('level thresholds', () {
      expect(proficiencyBonus(1), 2);
      expect(proficiencyBonus(4), 2);
      expect(proficiencyBonus(5), 3);
      expect(proficiencyBonus(8), 3);
      expect(proficiencyBonus(9), 4);
      expect(proficiencyBonus(13), 5);
      expect(proficiencyBonus(17), 6);
      expect(proficiencyBonus(20), 6);
    });

    test('clamps out-of-range levels', () {
      expect(proficiencyBonus(0), 2);
      expect(proficiencyBonus(25), 6);
    });
  });

  group('scaledBonus', () {
    test('not proficient: just the ability modifier', () {
      expect(scaledBonus(abilityScore: 14, proficiencyBonusValue: 3, multiplier: 0), 2);
    });

    test('proficient: modifier plus full proficiency bonus', () {
      expect(scaledBonus(abilityScore: 14, proficiencyBonusValue: 3, multiplier: 1), 5);
    });

    test('expertise: modifier plus double proficiency bonus', () {
      expect(scaledBonus(abilityScore: 14, proficiencyBonusValue: 3, multiplier: 2), 8);
    });

    test('half-proficient: floors the fractional proficiency contribution', () {
      // 3 * 0.5 = 1.5 -> floor to 1
      expect(scaledBonus(abilityScore: 10, proficiencyBonusValue: 3, multiplier: 0.5), 1);
    });
  });

  group('defaultArmorClass', () {
    test('computes 10 + dex modifier for calc "default"', () {
      expect(defaultArmorClass(calc: 'default', dexScore: 14), 12);
      expect(defaultArmorClass(calc: 'default', dexScore: 8), 9);
    });

    test('returns null for any other calc mode', () {
      expect(defaultArmorClass(calc: 'unarmoredMonk', dexScore: 14), isNull);
      expect(defaultArmorClass(calc: null, dexScore: 14), isNull);
    });
  });
}
