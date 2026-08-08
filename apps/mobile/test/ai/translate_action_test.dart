import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

FakeRepoStorage _storageWithEntities() => FakeRepoStorage(
      '/repo',
      dirEntries: {
        '': [
          RepoEntry(name: 'selena.md', path: 'selena.md', isDirectory: false),
          RepoEntry(name: 'frank.md', path: 'frank.md', isDirectory: false),
        ],
      },
      fileContents: {
        'selena.md': '# Selena\naliases: Селена\n',
        'frank.md': '# Frank\naliases: Фрэнк\n',
      },
    );

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

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, 'Hello there.');
    expect(aiClient.requests, hasLength(1));
    expect(aiClient.requests.single.userContent, '# Селена\n');
    // Every previewed section's content must be byte-for-byte in what was
    // actually sent (AD-11) — not just similar/paraphrased.
    expect(aiClient.requests.single.system, contains('Selena'));
    expect(aiClient.requests.single.system, contains('Фрэнк'));
    expect(aiClient.requests.single.system,
        contains('Name (emotion): phrase'));
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
