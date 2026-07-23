import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lore_and_story/lore/lore.dart';

/// Dart port of `test/fixtures/lore-model/normalize.js` — the projection the
/// golden files pin. Both implementations must reproduce it exactly to compare
/// against the same `expected.json` (AD-2).
///
/// Two transforms, both load-bearing:
/// - `file` (the only absolute path in the reference model) is dropped. The
///   Dart model never carries it, so there is nothing to strip here.
/// - `text` becomes `textSha` — the first 16 hex chars of the UTF-8 sha256.
///   This is what pins decoding and line endings exactly: a port that
///   mis-decodes Cyrillic or normalizes newlines fails here rather than
///   silently corrupting the author's files.
///
/// Lives in `test/` because it exists only to compare against the goldens;
/// `crypto` is a dev-only dependency for the same reason.
String textSha(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 16);

Map<String, Object?> _normLangs(Map<String, LoreLang> langs) {
  final keys = langs.keys.toList()..sort();
  return {
    for (final k in keys)
      k: <String, Object?>{
        'file': langs[k]!.file,
        'relDir': langs[k]!.relDir,
        'title': langs[k]!.title,
        'textSha': textSha(langs[k]!.text),
      },
  };
}

Map<String, Object?> _normNode(LoreNode node) => <String, Object?>{
      'name': node.name,
      'title': node.title,
      'overview': node.overview == null
          ? null
          : <String, Object?>{
              'id': node.overview!.id,
              'relDir': node.overview!.relDir,
              'textSha': textSha(node.overview!.text),
            },
      'items': node.items
          .map((i) => <String, Object?>{
                'id': i.id,
                'title': i.title,
                'group': i.group,
                'passage': i.passage,
                'langs': _normLangs(i.langs),
              })
          .toList(),
      'children': node.children.map(_normNode).toList(),
    };

Map<String, Object?> _normEntry(LoreEntry e) => <String, Object?>{
      'id': e.id,
      'title': e.title,
      'aliases': e.aliases,
      'category': e.category,
      'relDir': e.relDir,
      'textSha': textSha(e.text),
      'tree': e.tree == null ? null : _normNode(e.tree!),
      'children': e.children
          .map((c) => <String, Object?>{
                'id': c.id,
                'title': c.title,
                'group': c.group,
                'textSha': textSha(c.text),
              })
          .toList(),
    };

/// Normalizes loader output into the golden-file shape, entries sorted by `id`.
///
/// The reference sorts with `localeCompare`; Dart's `compareTo` is UTF-16
/// code-unit order. They agree for every current fixture id (lowercase ASCII
/// plus `/ . -`). If a future fixture introduces mixed case or unusual
/// punctuation and ordering mismatches, look here first.
Map<String, Object?> normalize(List<LoreEntry> entries) {
  final normalized = entries.map(_normEntry).toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  return <String, Object?>{'entries': normalized};
}
