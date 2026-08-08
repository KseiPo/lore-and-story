import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
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

/// Story 4.4: [_storageWithEntities]'s same entities plus an `ai-prompts.md`
/// override file built from whichever of [instructions]/[conventions] is
/// given (a null piece is simply omitted from the file, not written as an
/// empty heading).
FakeRepoStorage _storageWithPromptOverride({
  String? instructions,
  String? conventions,
}) {
  final buffer = StringBuffer();
  if (instructions != null) {
    buffer.writeln('# Translation Instructions');
    buffer.writeln(instructions);
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

/// Pumps a minimal host with a button that runs [runTranslate] and records
/// the resolved value, so tests drive it via real widget interactions (tap
/// Confirm/Cancel on the resulting preview) rather than calling it directly
/// and never rendering anything.
Future<void> _pumpHost(
  WidgetTester tester, {
  required RepoStorage storage,
  required AiClient aiClient,
  required String ruText,
  required ValueChanged<String?> onResult,
  String loreDir = '',
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
              ruText: ruText,
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
      'shows the context preview with exactly the 4 expected sections, '
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
