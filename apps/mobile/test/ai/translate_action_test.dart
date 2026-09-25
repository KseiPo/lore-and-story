import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/lore/lore.dart' show kProjectConfigFile;
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

// Review fix: the two lore-entity seed maps below are the single source both
// `_storageWithEntities` and `_storageWithPromptOverride` build from, so they
// can never silently drift apart (previously hand-duplicated in each).
final Map<String, List<RepoEntry>> _kEntityDirEntries = {
  '': [
    RepoEntry(name: 'selena.md', path: 'selena.md', isDirectory: false),
    RepoEntry(name: 'frank.md', path: 'frank.md', isDirectory: false),
  ],
};
const Map<String, String> _kEntityFileContents = {
  'selena.md': '# Selena\naliases: Селена\n',
  'frank.md': '# Frank\naliases: Фрэнк\n',
};

FakeRepoStorage _storageWithEntities() => FakeRepoStorage(
      '/repo',
      dirEntries: _kEntityDirEntries,
      fileContents: _kEntityFileContents,
    );

/// Story 4.4/4.5: [_storageWithEntities]'s same entities plus an
/// `ai-prompts.md` override file built from whichever of
/// [instructions]/[instructionsEnToRu]/[conventions] is given (a null piece
/// is simply omitted from the file, not written as an empty heading). Passing
/// [enToRuHeadingSpelling] switches the EN→RU heading between the canonical
/// arrow form (default) and the ASCII `(en->ru)` alias.
FakeRepoStorage _storageWithPromptOverride({
  String? instructions,
  String? instructionsEnToRu,
  String? conventions,
  String enToRuHeadingSpelling = 'Translation Instructions (EN→RU)',
}) {
  final buffer = StringBuffer();
  if (instructions != null) {
    buffer.writeln('# Translation Instructions');
    buffer.writeln(instructions);
  }
  if (instructionsEnToRu != null) {
    buffer.writeln('# $enToRuHeadingSpelling');
    buffer.writeln(instructionsEnToRu);
  }
  if (conventions != null) {
    buffer.writeln('# Conventions');
    buffer.writeln(conventions);
  }
  return FakeRepoStorage(
    '/repo',
    // Review fix: ai-prompts.md is listed in dirEntries too, not just
    // fileContents — matching a real filesystem, where a readable file is
    // always present in its parent's listing (the previous fixture omitted
    // this, which is exactly why the lore-entity-pollution bug this review
    // found was never exercisable by these tests in the first place).
    dirEntries: {
      '': [
        ..._kEntityDirEntries['']!,
        RepoEntry(
            name: kAiPromptConfigFile,
            path: kAiPromptConfigFile,
            isDirectory: false),
      ],
    },
    fileContents: {
      ..._kEntityFileContents,
      kAiPromptConfigFile: buffer.toString(),
    },
  );
}

/// Story 4.7: [_storageWithEntities]'s same entities plus a `lore-story.json`
/// containing the given `ai` object JSON fragment (e.g. `'"model":"m"'`) —
/// a distinct mechanism from [_storageWithPromptOverride]'s `ai-prompts.md`
/// (a different file entirely).
FakeRepoStorage _storageWithServerConfig(String aiObjectJson) {
  return FakeRepoStorage(
    '/repo',
    dirEntries: {
      '': [
        ..._kEntityDirEntries['']!,
        RepoEntry(
            name: kProjectConfigFile,
            path: kProjectConfigFile,
            isDirectory: false),
      ],
    },
    fileContents: {
      ..._kEntityFileContents,
      kProjectConfigFile: '{"ai":{$aiObjectJson}}',
    },
  );
}

/// Pumps a minimal host with a button that runs [runTranslate] and records
/// the resolved value, so tests drive it via real widget interactions (tap
/// Confirm/Cancel on the resulting preview) rather than calling it directly
/// and never rendering anything.
///
/// [direction] defaults to RU→EN (Story 4.3's original, still the only
/// direction most of this file's tests care about) — every pre-Story-4.5 call
/// site keeps exercising that exact path unchanged (AC5, no regression).
/// [ruText] is kept as the parameter name (rather than renaming to match
/// production's `sourceText`) purely to avoid touching every existing call
/// site in this file for a cosmetic rename; it is passed through as
/// `runTranslate`'s `sourceText`.
Future<void> _pumpHost(
  WidgetTester tester, {
  required RepoStorage storage,
  required AiClient aiClient,
  required String ruText,
  required ValueChanged<String?> onResult,
  String loreDir = '',
  TranslationDirection direction = TranslationDirection.ruToEn,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          child: const Text('translate'),
          onPressed: () async {
            final result = await runTranslate(
              context,
              storage: storage,
              loreDir: loreDir,
              aiClient: aiClient,
              sourceText: ruText,
              direction: direction,
            );
            onResult(result);
          },
        ),
      ),
    ),
  ));
}

/// The rendered text of preview section [index] (`context-preview-section-N`,
/// per `context_preview.dart`) — reads the actual `SelectableText` on screen
/// rather than duplicating the private constants `translate_action.dart`
/// builds them from, so a test comparing "previewed" against "sent" is
/// comparing against what the author actually saw, not a guess at it.
String _sectionText(WidgetTester tester, int index) {
  final finder = find.descendant(
    of: find.byKey(Key('context-preview-section-$index')),
    matching: find.byType(SelectableText),
  );
  return tester.widget<SelectableText>(finder).data ?? '';
}

void main() {
  testWidgets(
      'shows the context preview with exactly the 5 expected sections, '
      'nothing sent yet (AC1)', (tester) async {
    final aiClient = FakeAiClient(response: 'Translated.');
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: '# Селена\n\nПривет.',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    expect(find.text('AI instructions'), findsOneWidget);
    expect(find.text('The file'), findsOneWidget);
    expect(find.text('# Селена\n\nПривет.'), findsOneWidget);
    expect(find.text('Glossary terms'), findsOneWidget);
    expect(find.text('Conventions'), findsOneWidget);
    // (Story 4.7, Review fix) The destination is part of "exactly what
    // leaves the device" (AD-11) — scroll to it (a fixed-offset drag isn't
    // reliable here since 5 sections' combined content varies in length;
    // dragUntilVisible repeats the drag until the target is on screen).
    await tester.dragUntilVisible(
        find.text('Server'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('https://api.anthropic.com/v1/messages'), findsOneWidget,
        reason: 'the default Anthropic endpoint, since no ai object override '
            'is configured in this test\'s storage');
    expect(aiClient.requests, isEmpty,
        reason: 'the preview must show before anything is sent (AD-11)');
  });

  testWidgets(
      'the glossary section lists every entity\'s aliases (AC1, FR21)',
      (tester) async {
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: FakeAiClient(response: 'x'),
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    final glossaryFinder = find.byWidgetPredicate((w) =>
        w is SelectableText &&
        (w.data ?? '').contains('Selena') &&
        (w.data ?? '').contains('Фрэнк'));
    expect(glossaryFinder, findsOneWidget);
  });

  testWidgets(
      'confirming calls sendMessage with the previewed content and returns '
      'the joined stream text (AC1, AC3)', (tester) async {
    final aiClient = FakeAiClient(response: 'Hello there.');
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: '# Селена\n',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    // (Review fix) Read exactly what was previewed BEFORE confirming, so the
    // comparison below is against what the author actually saw on screen —
    // not a guess or a `contains` substring check.
    final instructionsText = _sectionText(tester, 0);
    final glossaryText = _sectionText(tester, 2);
    final conventionsText = _sectionText(tester, 3);

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, 'Hello there.');
    expect(aiClient.requests, hasLength(1));
    expect(aiClient.requests.single.userContent, '# Селена\n');
    // (Review fix — AD-11) The sent `system` prompt must be EXACTLY the
    // concatenation of the previewed sections — byte-for-byte, not merely
    // "contains" — with no additional label/glue text the author never saw.
    expect(
      aiClient.requests.single.system,
      [instructionsText, glossaryText, conventionsText].join('\n\n'),
    );
  });

  testWidgets('cancelling the preview returns null without calling '
      'sendMessage (AC2)', (tester) async {
    final aiClient = FakeAiClient(response: 'Should never be used.');
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(aiClient.requests, isEmpty);
  });

  testWidgets('a glossary-load failure shows a SnackBar and returns null, '
      'never throws (AC6/AD-8)', (tester) async {
    final storage = FakeRepoStorage('/repo', throwOnListDir: true);
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: storage,
      aiClient: FakeAiClient(response: 'unused'),
      ruText: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('an AiClientException from sendMessage shows its message in a '
      'SnackBar and returns null, never throws (AC6/AD-8)', (tester) async {
    final aiClient = FakeAiClient(error: const AiAuthException('bad key'));
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('bad key'), findsOneWidget);
  });

  testWidgets(
      '(verify empirically, not assumed) an error emitted partway through '
      'the stream is still caught and reported, not left unresolved',
      (tester) async {
    final aiClient = _MidStreamFailureAiClient();
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      '(review fix) a project with no other lore entries shows an honest '
      'placeholder in the Glossary terms section instead of a blank one',
      (tester) async {
    await _pumpHost(
      tester,
      storage: FakeRepoStorage('/repo'), // no dirEntries — zero entities
      aiClient: FakeAiClient(response: 'x'),
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 2),
        '(no other lore entries found in this project)');
  });

  testWidgets(
      '(review fix) an empty/whitespace-only AI response is treated as a '
      'failure, not a successful empty translation (AC3/AD-8)',
      (tester) async {
    // Default FakeAiClient() with no `response` configured yields nothing —
    // exactly the shape a misbehaving stream produces.
    final aiClient = FakeAiClient();
    String? result = 'unset';
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('The AI returned an empty translation. Please try again.'),
        findsOneWidget);
  });

  testWidgets(
      '(review fix) requests a generous maxTokens for a full scene '
      'translation, not the port\'s tight 8192 default', (tester) async {
    final aiClient = FakeAiClient(response: 'ok');
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(aiClient.requests.single.maxTokens, greaterThan(8192));
  });

  testWidgets(
      '(review fix) the conventions tell the model to update the scene '
      'header\'s lang: field, not copy lang: ru verbatim', (tester) async {
    await _pumpHost(
      tester,
      storage: _storageWithEntities(),
      aiClient: FakeAiClient(response: 'x'),
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    final conventions = _sectionText(tester, 3);
    expect(conventions, contains('lang: ru'));
    expect(conventions, contains('lang: en'));
  });

  testWidgets(
      '(Story 4.4) an ai-prompts.md override replaces both pieces in the '
      'preview and in exactly what\'s sent, byte-for-byte (AC1, AC2)',
      (tester) async {
    final aiClient = FakeAiClient(response: 'ok');
    await _pumpHost(
      tester,
      storage: _storageWithPromptOverride(
        instructions: 'My custom instructions.',
        conventions: 'My custom conventions.',
      ),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    // (Review fix) Bound to the specific section index — proves the override
    // landed in the SECTION it's supposed to, not just somewhere on screen
    // (a regression that swapped instructions/conventions would previously
    // have passed this test unnoticed via a global `find.text`).
    expect(_sectionText(tester, 0), 'My custom instructions.');
    expect(_sectionText(tester, 3), 'My custom conventions.');

    final instructionsText = _sectionText(tester, 0);
    final glossaryText = _sectionText(tester, 2);
    final conventionsText = _sectionText(tester, 3);

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    // (Review fix — AD-11) Byte-for-byte, not `contains` — the same standard
    // Story 4.3's own review established for this exact property.
    expect(
      aiClient.requests.single.system,
      [instructionsText, glossaryText, conventionsText].join('\n\n'),
    );
  });

  testWidgets(
      '(Story 4.4) overriding only one piece leaves the other on its '
      'hardcoded default, in both what\'s shown and what\'s sent '
      '(AC4, partial override)', (tester) async {
    final aiClient = FakeAiClient(response: 'ok');
    await _pumpHost(
      tester,
      storage: _storageWithPromptOverride(conventions: 'My custom conventions.'),
      aiClient: aiClient,
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 3), 'My custom conventions.');
    // Instructions were never overridden — the hardcoded default still shows,
    // bound to the instructions section specifically.
    expect(_sectionText(tester, 0), contains('You are translating a Russian'));

    // (Review fix) The previous version of this test stopped here, verifying
    // only the "shows" half of AC4 — confirm and check what's actually sent.
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(aiClient.requests.single.system, contains('My custom conventions.'));
    expect(aiClient.requests.single.system,
        contains('You are translating a Russian'));
  });

  testWidgets(
      '(Story 4.4) a missing ai-prompts.md is exactly as safe as before this '
      'story (AC3, AC8 — no regression)', (tester) async {
    await _pumpHost(
      tester,
      storage: _storageWithEntities(), // no ai-prompts.md seeded
      aiClient: FakeAiClient(response: 'ok'),
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('You are translating a Russian'), findsOneWidget);
    expect(find.textContaining('Dialogue lines are'), findsOneWidget);
  });

  testWidgets(
      '(Story 4.4, AC6) ai-prompts.md is re-read on every translate — an '
      'edit between two calls is reflected on the second, not cached from '
      'the first', (tester) async {
    final storage = _storageWithPromptOverride(conventions: 'Version one.');
    final aiClient = FakeAiClient(response: 'ok');

    // First translate: sees "Version one.".
    await _pumpHost(
      tester,
      storage: storage,
      aiClient: aiClient,
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();
    expect(_sectionText(tester, 3), 'Version one.');
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();
    expect(aiClient.requests.single.system, contains('Version one.'));

    // Edit the file directly on the same storage instance, as a desktop
    // editor would between two translate requests.
    await storage.writeAtomic(
        kAiPromptConfigFile, '# Conventions\nVersion two.\n');

    // Second translate, same running app (fresh host so the button is usable
    // again — the underlying storage instance, and therefore the file, is
    // unchanged): must reflect the edit, not a value cached from the first.
    await _pumpHost(
      tester,
      storage: storage,
      aiClient: aiClient,
      ruText: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('translate'));
    await tester.pumpAndSettle();
    expect(_sectionText(tester, 3), 'Version two.');
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();
    expect(aiClient.requests.last.system, contains('Version two.'));
    expect(aiClient.requests.last.system, isNot(contains('Version one.')));
  });

  group('Story 4.5: EN→RU direction', () {
    testWidgets(
        'the context preview shows the EN→RU-worded instructions, not the '
        'RU→EN text — and the sent request reflects it byte-for-byte',
        (tester) async {
      final aiClient = FakeAiClient(response: 'ok');
      await _pumpHost(
        tester,
        storage: _storageWithEntities(),
        aiClient: aiClient,
        ruText: '# Scene\n\nHello.',
        direction: TranslationDirection.enToRu,
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      final instructionsText = _sectionText(tester, 0);
      expect(instructionsText, contains('translating an English'));
      expect(instructionsText, contains('into natural, readable Russian'));
      expect(instructionsText, isNot(contains('translating a Russian')));
      // "The file" section carries the EN source text — this direction
      // translates FROM English.
      expect(_sectionText(tester, 1), '# Scene\n\nHello.');

      final glossaryText = _sectionText(tester, 2);
      final conventionsText = _sectionText(tester, 3);
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(
        aiClient.requests.single.system,
        [instructionsText, glossaryText, conventionsText].join('\n\n'),
      );
    });

    testWidgets(
        'an ai-prompts.md override via # Translation Instructions (EN→RU) '
        'replaces the EN→RU instructions only — the RU→EN default is '
        'untouched', (tester) async {
      final aiClient = FakeAiClient(response: 'ok');
      await _pumpHost(
        tester,
        storage: _storageWithPromptOverride(
            instructionsEnToRu: 'My custom EN→RU instructions.'),
        aiClient: aiClient,
        ruText: 'text',
        direction: TranslationDirection.enToRu,
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(_sectionText(tester, 0), 'My custom EN→RU instructions.');

      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();
      expect(aiClient.requests.single.system,
          contains('My custom EN→RU instructions.'));
    });

    testWidgets(
        'the ASCII (en->ru) heading spelling overrides identically to the '
        'arrow form', (tester) async {
      final aiClient = FakeAiClient(response: 'ok');
      await _pumpHost(
        tester,
        storage: _storageWithPromptOverride(
          instructionsEnToRu: 'Via ASCII heading.',
          enToRuHeadingSpelling: 'Translation Instructions (en->ru)',
        ),
        aiClient: aiClient,
        ruText: 'text',
        direction: TranslationDirection.enToRu,
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(_sectionText(tester, 0), 'Via ASCII heading.');
    });

    testWidgets(
        'an ai-prompts.md with only the RU→EN heading leaves an EN→RU '
        'request on the hardcoded EN→RU default (independent partial '
        'override)', (tester) async {
      final aiClient = FakeAiClient(response: 'ok');
      await _pumpHost(
        tester,
        storage: _storageWithPromptOverride(
            instructions: 'My custom RU→EN instructions.'),
        aiClient: aiClient,
        ruText: 'text',
        direction: TranslationDirection.enToRu,
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(_sectionText(tester, 0), contains('translating an English'));
      expect(_sectionText(tester, 0),
          isNot(contains('My custom RU→EN instructions.')));
    });

    testWidgets(
        '(Review decision, 2026-08-08) hardcoded Conventions default is '
        'forked per direction, not shared — RU→EN keeps its original '
        'English-form/lang:-ru→en wording; EN→RU gets its own mirror',
        (tester) async {
      String? ruToEnConventions;
      String? enToRuConventions;

      await _pumpHost(
        tester,
        storage: _storageWithEntities(),
        aiClient: FakeAiClient(response: 'x'),
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      ruToEnConventions = _sectionText(tester, 3);
      await tester.tap(find.byKey(const Key('context-preview-cancel')));
      await tester.pumpAndSettle();

      await _pumpHost(
        tester,
        storage: _storageWithEntities(),
        aiClient: FakeAiClient(response: 'x'),
        ruText: 'text',
        direction: TranslationDirection.enToRu,
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      enToRuConventions = _sectionText(tester, 3);

      expect(ruToEnConventions, isNot(enToRuConventions));
      expect(ruToEnConventions, contains('use the English form'));
      expect(ruToEnConventions, contains('lang: ru` to `lang: en`'));
      expect(enToRuConventions, contains('use the Russian form'));
      expect(enToRuConventions, contains('lang: en` to `lang: ru`'));

      // Story 5.7 (KseiPo, 2026-09-24): the emotion is translated in both
      // directions, and the conditional keywords are converted into the
      // target language — each direction maps its own way.
      const emotionRule = 'translate the name, the emotion and the phrase';
      expect(ruToEnConventions, contains(emotionRule));
      expect(enToRuConventions, contains(emotionRule));
      expect(ruToEnConventions, contains('конец условия → end if'));
      expect(enToRuConventions, contains('end if → конец условия'));
      expect(enToRuConventions, contains('if → если'));
      expect(enToRuConventions, contains('else → иначе'));
      expect(ruToEnConventions, contains('если → if'));
      expect(ruToEnConventions, contains('иначе → else'));
      // The two EN→RU lines Story 5.7 changed, pinned exactly (the RU→EN
      // block is pinned in full by the test below).
      expect(
          enToRuConventions,
          contains('- Dialogue lines are `Name (emotion): phrase.` — the '
              'emotion is optional. Keep this exact shape; translate the '
              'name, the emotion and the phrase.'));
      expect(
          enToRuConventions,
          contains('- Em-dash conditional markers delimit authoring '
              'conditionals, not prose to render: English `— if <condition> '
              '— … — else — … — end if —` is Russian `— если <condition> — … '
              '— иначе — … — конец условия —`. Keep the em-dash marker shape; '
              'replace the keywords with the Russian ones (if → если, else → '
              'иначе, end if → конец условия) and translate the condition and '
              'branch text.'));
    });

    testWidgets(
        '(Story 5.7) the RU→EN conventions default is exactly the text '
        'KseiPo approved on 2026-09-24 — deliberately superseding the Story '
        '4.3/4.4 pin (translated emotions and conditional keywords)',
        (tester) async {
      await _pumpHost(
        tester,
        storage: _storageWithEntities(),
        aiClient: FakeAiClient(response: 'x'),
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(_sectionText(tester, 3), '''
- Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate the name, the emotion and the phrase.
- Inner monologue is `Мысль: …` in Russian and `Thought: …` in English — use the English form.
- Variable placeholders are readable square brackets, e.g. `[имя героя]` — translate the words inside the brackets, keep the bracket form, never emit `<<=\$var>>` or other code syntax.
- Player-choice / passage links: `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — translate the choice text (the label before the separator); never translate or alter the Passage Name (the target after the separator) — it is an identifier, not prose.
- Return links: `[[back<-Label]]` — translate the Label only; the backlink form itself never changes.
- Em-dash conditional markers delimit authoring conditionals, not prose to render: Russian `— если <condition> — … — иначе — … — конец условия —` is English `— if <condition> — … — else — … — end if —`. Keep the em-dash marker shape; replace the keywords with the English ones (если → if, иначе → else, конец условия → end if) and translate the condition and branch text.
- `[[Title]]` with no separator is a lore-entity wikilink (not a passage jump) — translate Title to that entity's English form from the glossary when the glossary lists one; otherwise leave it unchanged rather than guessing.
- A file may open with a `<!-- scene ⇄ passage: "Passage Name" · lang: ru -->` comment — keep the passage name unchanged, but update `lang: ru` to `lang: en` in the translated output; if no such comment exists, do not add one.''');
    });
  });

  group('AI server config (Story 4.7)', () {
    testWidgets(
        'a resolved lore-story.json ai object flows into the sent request\'s '
        'model/baseUrl', (tester) async {
      final aiClient = FakeAiClient(response: 'Translated.');
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"custom","model":"local-model",'
            '"baseUrl":"http://localhost:1234/v1"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.model, 'local-model');
      expect(aiClient.requests.single.baseUrl,
          Uri.parse('http://localhost:1234/v1'));
    });

    testWidgets(
        '(AC6) an absent lore-story.json leaves model/baseUrl null on the '
        'sent request — today\'s behavior unchanged', (tester) async {
      final aiClient = FakeAiClient(response: 'Translated.');
      await _pumpHost(
        tester,
        storage: _storageWithEntities(),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.model, isNull);
      expect(aiClient.requests.single.baseUrl, isNull);
    });

    testWidgets(
        'the preview\'s Server section shows the resolved custom origin '
        'when one is configured', (tester) async {
      final aiClient = FakeAiClient(response: 'Translated.');
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"custom","baseUrl":"http://localhost:1234/v1"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('http://localhost:1234/v1'),
          find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('http://localhost:1234/v1'), findsOneWidget);
    });

    testWidgets(
        '(Review fix) an unusable server config (custom with no baseUrl) '
        'shows an error and never opens the preview or sends anything',
        (tester) async {
      final aiClient = FakeAiClient(response: 'should never be sent');
      String? result = 'unset';
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig('"server":"custom"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(result, isNull);
      expect(aiClient.requests, isEmpty);
      expect(find.byKey(const Key('context-preview-confirm')), findsNothing,
          reason: 'nothing valid to preview — the error is surfaced before '
              'the preview would open');
      expect(find.textContaining('server'), findsOneWidget);
    });
  });

  group('AI protocol (Story 4.8)', () {
    testWidgets(
        'an explicit protocol: "openai" config reaches the sent request\'s '
        'protocol field', (tester) async {
      final aiClient = FakeAiClient(response: 'Translated.');
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"custom","protocol":"openai","model":"local-model",'
            '"baseUrl":"http://localhost:1234/v1"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.protocol, AiProtocol.openai);
    });

    testWidgets(
        '(AC2) server: "openrouter" with no protocol set also produces '
        'AiProtocol.openai on the sent request — the default', (tester) async {
      final aiClient = FakeAiClient(response: 'Translated.');
      await _pumpHost(
        tester,
        storage:
            _storageWithServerConfig('"server":"openrouter","model":"gpt-x"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.protocol, AiProtocol.openai);
    });

    testWidgets(
        'an inconsistent protocol/server combo (openai + anthropic) shows '
        'an error and never opens the preview or sends anything',
        (tester) async {
      final aiClient = FakeAiClient(response: 'should never be sent');
      String? result = 'unset';
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"anthropic","protocol":"openai"'),
        aiClient: aiClient,
        ruText: 'text',
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('translate'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(result, isNull);
      expect(aiClient.requests, isEmpty);
      expect(find.byKey(const Key('context-preview-confirm')), findsNothing);
      expect(find.textContaining('protocol'), findsOneWidget);
    });
  });
}

/// Emits one good chunk, then a stream error — the shape Story 4.1's own
/// review found a real Dart `Stream`/`async*` bug in (a `try`/`catch` around
/// `yield*` didn't reliably catch a delegated stream error). `runTranslate`
/// uses a plain `await for` inside `try`/`catch`, a different, safe shape —
/// this test proves that empirically rather than assuming it from reading
/// the code.
class _MidStreamFailureAiClient implements AiClient {
  @override
  Stream<String> sendMessage(AiRequest request) async* {
    yield 'partial ';
    throw const AiServerException('server blew up mid-stream');
  }
}
