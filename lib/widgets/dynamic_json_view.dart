import 'package:flutter/material.dart';

/// Renders an arbitrary `Map<String, dynamic>` (as returned by Foundry for
/// any actor, in any game system) as a widget tree, purely from each value's
/// runtime type. No field names are special-cased — that's the whole point
/// of this PoC: it must work identically for a D&D 5e actor, a Pathfinder
/// actor, or anything else Foundry can store.
///
/// Every numeric leaf is tappable — [onTapNumber] is called with its JSON
/// path (e.g. `system.abilities.str.value`) and value, so the caller can
/// turn any stat into a roll without this widget knowing what a "stat" is.
class DynamicJsonView extends StatelessWidget {
  final dynamic value;
  final String path;
  final String label;
  final void Function(String path, num value) onTapNumber;
  final int depth;

  const DynamicJsonView({
    super.key,
    required this.value,
    required this.path,
    required this.label,
    required this.onTapNumber,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final map = (value as Map).cast<String, dynamic>();
      if (map.isEmpty) return _LeafTile(label: label, valueText: '{}');
      return _MapNode(
        label: label,
        path: path,
        entries: map,
        onTapNumber: onTapNumber,
        depth: depth,
      );
    }
    if (value is List) {
      final list = value as List;
      if (list.isEmpty) return _LeafTile(label: label, valueText: '[]');
      return _ListNode(
        label: label,
        path: path,
        items: list,
        onTapNumber: onTapNumber,
        depth: depth,
      );
    }
    if (value is num) {
      return _NumberTile(
        label: label,
        value: value as num,
        onTap: () => onTapNumber(path, value as num),
      );
    }
    if (value is bool) {
      return _LeafTile(label: label, valueText: value.toString(), icon: Icons.toggle_on_outlined);
    }
    if (value == null) {
      return _LeafTile(label: label, valueText: '—', muted: true);
    }
    // String (or anything else JSON can hold).
    final text = value.toString();
    return _LeafTile(label: label, valueText: text.isEmpty ? '""' : text);
  }
}

class _MapNode extends StatelessWidget {
  final String label;
  final String path;
  final Map<String, dynamic> entries;
  final void Function(String path, num value) onTapNumber;
  final int depth;

  const _MapNode({
    required this.label,
    required this.path,
    required this.entries,
    required this.onTapNumber,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(path),
          initiallyExpanded: depth < 1,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(left: 8),
          title: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: depth == 0 ? 15 : 13.5),
          ),
          subtitle: Text('${entries.length} velden', style: const TextStyle(fontSize: 11)),
          children: entries.entries
              .map((e) => DynamicJsonView(
                    value: e.value,
                    path: path.isEmpty ? e.key : '$path.${e.key}',
                    label: e.key,
                    onTapNumber: onTapNumber,
                    depth: depth + 1,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _ListNode extends StatelessWidget {
  final String label;
  final String path;
  final List items;
  final void Function(String path, num value) onTapNumber;
  final int depth;

  const _ListNode({
    required this.label,
    required this.path,
    required this.items,
    required this.onTapNumber,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(path),
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(left: 8),
          title: Text(label,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: depth == 0 ? 15 : 13.5)),
          subtitle: Text('${items.length} items', style: const TextStyle(fontSize: 11)),
          children: [
            for (var i = 0; i < items.length; i++)
              DynamicJsonView(
                value: items[i],
                path: '$path[$i]',
                label: _itemLabel(items[i], i),
                onTapNumber: onTapNumber,
                depth: depth + 1,
              ),
          ],
        ),
      ),
    );
  }

  String _itemLabel(dynamic item, int index) {
    if (item is Map && item['name'] is String) return '[$index] ${item['name']}';
    return '[$index]';
  }
}

class _NumberTile extends StatelessWidget {
  final String label;
  final num value;
  final VoidCallback onTap;

  const _NumberTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.casino_outlined, size: 15, color: scheme.onPrimaryContainer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeafTile extends StatelessWidget {
  final String label;
  final String valueText;
  final bool muted;
  final IconData? icon;

  const _LeafTile({required this.label, required this.valueText, this.muted = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          if (icon != null) Icon(icon, size: 15, color: Colors.grey),
          Expanded(
            flex: 3,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: muted ? Colors.grey : null,
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
