/// Pure browse-model helpers for the `lore/` slice: grouping the flat entity
/// list into top-level categories for the Categories → Entities browse
/// (Story 2.2, FR4/FR5).
///
/// Pure Dart — no Flutter, no `dart:io` (AD-9). The browse UI (in `app/`)
/// renders what these return and holds no grouping logic of its own, so the
/// grouping stays unit-testable in isolation.
library;

import 'lore_model.dart';

/// One top-level category: a folder directly under `loreDir` (or the synthetic
/// `general` bucket for cards sitting at the lore root), with the entities that
/// belong to it.
class LoreCategory {
  /// The top-level folder name — `entry.category.split('/').first`. Also the
  /// synthetic `general` for root-level cards.
  final String key;

  /// Human-facing label. Currently identical to [key] (folder names are already
  /// readable); kept as a separate field so a later prettify/localize step has
  /// a seam without changing call sites.
  final String label;

  /// Entities in this category, including any nested in sub-categories (folded
  /// up to their top-level parent) so every entity stays reachable in the
  /// two-level browse. Deterministically ordered by [categoriesOf].
  final List<LoreEntry> entries;

  const LoreCategory({
    required this.key,
    required this.label,
    required this.entries,
  });
}

/// Groups [entries] into ordered top-level categories (FR4).
///
/// - Category key = `entry.category.split('/').first`, so a nested
///   sub-category (`characters/secondary`) folds under its top-level parent
///   (`characters`). This keeps deep entities reachable in the two-level browse
///   without a deep folder tree (Story 2.2 scope) — nothing is stranded. A blank
///   first segment (a category that is empty or leading-slash — the loader never
///   emits one, but this stays robust if it ever did) falls back to `general`.
/// - The loader's synthetic `general` category (a card directly in `loreDir`)
///   becomes its own top-level group; it is never dropped.
/// - Deterministic, display-facing order: categories by key (case-insensitive,
///   tie-broken by the raw key so two case-only-distinct folders have a stable
///   order); entities within a category by title (case-insensitive), tie-broken
///   by id so two same-titled cards have a stable order. Walk order is an
///   internal detail, not a UI contract.
List<LoreCategory> categoriesOf(List<LoreEntry> entries) {
  final byKey = <String, List<LoreEntry>>{};
  for (final e in entries) {
    final firstSeg = e.category.split('/').first;
    final key = firstSeg.isEmpty ? 'general' : firstSeg;
    (byKey[key] ??= <LoreEntry>[]).add(e);
  }

  int byTitleThenId(LoreEntry a, LoreEntry b) {
    final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return t != 0 ? t : a.id.compareTo(b.id);
  }

  final keys = byKey.keys.toList()
    ..sort((a, b) {
      final c = a.toLowerCase().compareTo(b.toLowerCase());
      return c != 0 ? c : a.compareTo(b);
    });

  return [
    for (final key in keys)
      LoreCategory(
        key: key,
        label: key,
        entries: List.unmodifiable(byKey[key]!..sort(byTitleThenId)),
      ),
  ];
}
