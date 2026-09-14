import 'package:flutter/material.dart';

import 'dnd5e_sheet_template.dart';

/// Everything a [SheetTemplate] needs to render, without owning any
/// networking itself — `ActorSheetScreen` still holds the `RelayClient` and
/// all dialogs; templates just call back into it. Keeping templates
/// network-free makes them easy to add for a new system: implement
/// [SheetTemplate.build] against this context and register it.
class SheetTemplateContext {
  final String uuid;
  final Map<String, dynamic> actor;

  /// Opens the roll dialog pre-filled with [defaultFormula]/[defaultFlavor]
  /// under [title] — the same dialog `DynamicJsonView`'s numeric leaves use,
  /// just with a template-computed formula (e.g. `1d20 + <ability mod>`)
  /// instead of a raw leaf value.
  final void Function({required String title, required String defaultFormula, required String defaultFlavor}) onRoll;

  /// Opens the existing +/- adjust dialog for the field at [path]. Writes
  /// to the actor unless [targetUuid] is given — pass an embedded item's own
  /// UUID (`'$uuid.Item.<itemId>'`) to scope the write to that item instead
  /// (confirmed live: the actor's UUID can't dot-path into `items[]` since
  /// it's an embedded collection, but the item's own UUID resolves directly).
  final void Function(String path, num value, {String? targetUuid}) onAdjust;

  /// Applies [delta] to the field at [path] immediately, no dialog — for
  /// dedicated -/+ buttons (e.g. HP) where a quick ±1 is the common case.
  /// Tapping the value itself should still go through [onAdjust] for custom
  /// amounts. Same [targetUuid] item-scoping as [onAdjust].
  final void Function(String path, num delta, {String? targetUuid}) onQuickAdjust;

  /// Opens the existing edit dialog (string) / toggles it (bool) for the
  /// field at [path]. Same [targetUuid] item-scoping as [onAdjust].
  final void Function(String path, dynamic currentValue, {String? targetUuid}) onEditLeaf;

  /// The full generic, system-agnostic tree — every template embeds this
  /// somewhere (typically collapsed, as "raw data") so nothing a template
  /// doesn't specifically surface is ever inaccessible.
  final Widget rawDataView;

  SheetTemplateContext({
    required this.uuid,
    required this.actor,
    required this.onRoll,
    required this.onAdjust,
    required this.onQuickAdjust,
    required this.onEditLeaf,
    required this.rawDataView,
  });
}

/// A purpose-built, traditional-looking sheet layout for one game system.
/// Optional by design: [ActorSheetScreen] falls back to the generic
/// `DynamicJsonView` tree whenever no template matches, so an unrecognized
/// system still gets a fully working (if less pretty) sheet.
abstract class SheetTemplate {
  bool matches(String? systemId);
  Widget build(BuildContext context, SheetTemplateContext ctx);
}

class SheetTemplateRegistry {
  SheetTemplateRegistry._();

  /// Add a template here to support another system — implement
  /// [SheetTemplate] (see `dnd5e_sheet_template.dart` for the reference)
  /// and list it below. See `TODO.md` for the roadmap.
  static final List<SheetTemplate> _templates = [const Dnd5eSheetTemplate()];

  static SheetTemplate? forSystem(String? systemId) {
    for (final template in _templates) {
      if (template.matches(systemId)) return template;
    }
    return null;
  }
}
