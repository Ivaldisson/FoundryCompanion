/// Standard D&D 5e tabletop math — public game rules, not Foundry or the
/// dnd5e system package's internal implementation. Used because the relay
/// never exposes computed/derived values (see README.md): the raw actor
/// document only has stored scores, not modifiers, bonuses, or AC.
///
/// Deliberately conservative: `bonuses.check`/`.save`/`.skill` formula
/// strings on the actor (arbitrary Foundry roll formulas, e.g. "+1d4") are
/// ignored rather than evaluated — evaluating arbitrary dice formulas
/// client-side is its own can of worms, and a slightly-low bonus is a much
/// safer failure mode than silently running untrusted formula text.
library;

/// `floor((score - 10) / 2)`.
int abilityModifier(num score) => ((score - 10) / 2).floor();

/// `2 + floor((level - 1) / 4)`, valid for levels 1–20.
int proficiencyBonus(int level) {
  final clamped = level.clamp(1, 20);
  return 2 + ((clamped - 1) / 4).floor();
}

/// Ability check / saving throw / skill bonus: ability modifier plus
/// proficiency bonus scaled by [multiplier] — the raw value stored at
/// `system.skills.<key>.value` or `system.abilities.<key>.save.value`-style
/// fields (0 = not proficient, 0.5 = half-proficient, 1 = proficient,
/// 2 = expertise). Foundry stores this as a `num` (can be fractional), so
/// the result is floored like the game rules do.
int scaledBonus({required int abilityScore, required int proficiencyBonusValue, required num multiplier}) {
  return abilityModifier(abilityScore) + (proficiencyBonusValue * multiplier).floor();
}

/// AC for the common `calc: "default"` case only: `10 + dex modifier`.
/// Ignores equipped armor/shield bonuses (v1 scope cut — see TODO.md) and
/// returns null for anything else, so callers can fall back to showing the
/// actor's raw `flat` AC value or an explicit "—" instead of guessing.
int? defaultArmorClass({required String? calc, required int dexScore}) {
  if (calc != 'default') return null;
  return 10 + abilityModifier(dexScore);
}
