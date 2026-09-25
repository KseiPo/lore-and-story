import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/lore/lore.dart' show kProjectConfigFile;
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

/// Story 4.6: a repo whose `ai-prompts.md` optionally overrides `# Grammar
/// Instructions`. A null [instructions] omits the heading entirely (not
/// written as an empty section) — mirrors
/// `translate_action_test.dart`'s own `_storageWithPromptOverride` shape.
FakeRepoStorage _storageWithPromptOverride({String? instructions}) {
  final buffer = StringBuffer();
  if (instructions != null) {
    buffer.writeln('# Grammar Instructions');
    buffer.writeln(instructions);
  }
  return FakeRepoStorage(
    '/repo',
    dirEntries: {
      '': [
        RepoEntry(
            name: kAiPromptConfigFile,
            path: kAiPromptConfigFile,
            isDirectory: false),
      ],
    },
    fileContents: {kAiPromptConfigFile: buffer.toString()},
  );
}

/// A repo with no `ai-prompts.md` at all — every request uses the hardcoded
/// default instructions.
FakeRepoStorage _storageNoOverride() => FakeRepoStorage('/repo');

/// Story 4.7: a repo whose `lore-story.json` contains the given `ai` object
/// JSON fragment (e.g. `'"model":"m"'`) — a distinct mechanism from
/// [_storageWithPromptOverride]'s `ai-prompts.md` (a different file
/// entirely).
FakeRepoStorage _storageWithServerConfig(String aiObjectJson) {
  return FakeRepoStorage(
    '/repo',
    dirEntries: {
      '': [
        RepoEntry(
            name: kProjectConfigFile,
            path: kProjectConfigFile,
            isDirectory: false),
      ],
    },
    fileContents: {kProjectConfigFile: '{"ai":{$aiObjectJson}}'},
  );
}

/// Pumps a minimal host with a button that runs [runGrammarReview] and
/// records the resolved value, mirroring `translate_action_test.dart`'s own
/// `_pumpHost` shape.
Future<void> _pumpHost(
  WidgetTester tester, {
  required RepoStorage storage,
  required AiClient aiClient,
  required String text,
  required ValueChanged<List<GrammarFinding>?> onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          child: const Text('review'),
          onPressed: () async {
            final result = await runGrammarReview(
              context,
              storage: storage,
              aiClient: aiClient,
              text: text,
            );
            onResult(result);
          },
        ),
      ),
    ),
  ));
}

/// The rendered text of preview section [index], mirroring
/// `translate_action_test.dart`'s own `_sectionText`.
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
      'nothing sent yet (AC1/AC4)', (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'Some prose.',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(find.text('AI instructions'), findsOneWidget);
    // The instructions text is long enough that the later sections sit
    // below the fold in the bottom sheet's lazily-built ListView — scroll it
    // into view rather than assuming they're already built. dragUntilVisible
    // repeats the drag rather than a fixed offset, since total content
    // length varies across sections.
    await tester.dragUntilVisible(
        find.text('Server'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Response format'), findsOneWidget);
    expect(find.text('The file'), findsOneWidget);
    expect(find.text('Some prose.'), findsOneWidget);
    // (Story 4.7, Review fix) The destination is part of "exactly what
    // leaves the device" (AD-11), now that lore-story.json can redirect it.
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('https://api.anthropic.com/v1/messages'), findsOneWidget);
    expect(aiClient.requests, isEmpty,
        reason: 'the preview must show before anything is sent (AD-11)');
  });

  testWidgets(
      'well-formed JSON parses into findings covering all three severities, '
      'plus an unrecognized-severity fallback to moderate (AC1)',
      (tester) async {
    const json = '''
[
  {"line": 3, "issue": "Typo", "suggestion": "Fix it", "severity": "minor"},
  {"line": 5, "issue": "Awkward phrasing", "suggestion": "Rephrase", "severity": "moderate"},
  {"line": 9, "issue": "Wrong tense", "suggestion": "Use past tense", "severity": "major"},
  {"line": 1, "issue": "Unknown severity", "suggestion": "n/a", "severity": "critical"}
]''';
    final aiClient = FakeAiClient(response: json);
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(4));
    expect(result![0], const GrammarFinding(
        line: 3, issue: 'Typo', suggestion: 'Fix it', severity: GrammarSeverity.minor));
    expect(result![1].severity, GrammarSeverity.moderate);
    expect(result![2].severity, GrammarSeverity.major);
    expect(result![3].severity, GrammarSeverity.moderate,
        reason: 'an unrecognized severity string degrades to moderate, '
            'not a dropped finding');
  });

  testWidgets(
      'a response wrapped in a markdown code fence still parses (Task 2.4)',
      (tester) async {
    final aiClient = FakeAiClient(
        response: '```json\n'
            '[{"line": 1, "issue": "x", "suggestion": "y", "severity": "minor"}]\n'
            '```');
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.issue, 'x');
  });

  testWidgets('an empty array is a real "no issues" result, not null (AC6)',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    List<GrammarFinding>? result = const [
      GrammarFinding(
          line: 1, issue: 'placeholder', suggestion: '', severity: GrammarSeverity.minor),
    ];
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, isEmpty);
  });

  testWidgets(
      'top-level malformed JSON shows an error and returns null, never '
      'throws (AC7/AD-8)', (tester) async {
    final aiClient = FakeAiClient(response: 'not json at all {{{');
    List<GrammarFinding>? result = const [];
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
      'a genuinely malformed (non-map) entry among well-formed ones '
      'degrades gracefully — the well-formed entries still render (AC7)',
      (tester) async {
    const json = '''
[
  {"line": 1, "issue": "Good one", "suggestion": "Fix", "severity": "minor"},
  "not even a map",
  {"line": 4, "issue": "Another good one", "suggestion": "Fix too", "severity": "major"}
]''';
    final aiClient = FakeAiClient(response: json);
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.map((f) => f.issue), ['Good one', 'Another good one']);
  });

  testWidgets(
      '(Review fix) a finding missing "suggestion" degrades to an empty '
      'string rather than being dropped', (tester) async {
    final aiClient = FakeAiClient(
        response: '[{"line": 2, "issue": "Missing suggestion"}]');
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.issue, 'Missing suggestion');
    expect(result!.single.suggestion, '');
  });

  testWidgets(
      '(Review fix) a decoded array whose every entry fails validation is '
      'reported as a parse failure, not a false "no issues"', (tester) async {
    final aiClient = FakeAiClient(response: '[{"foo": 1}, {"bar": 2}]');
    List<GrammarFinding>? result = const [];
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('(Review fix) a JSON double line number (e.g. 3.0) still parses',
      (tester) async {
    final aiClient = FakeAiClient(
        response: '[{"line": 3.0, "issue": "x", "suggestion": "y", '
            '"severity": "minor"}]');
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.line, 3);
  });

  testWidgets(
      '(Review fix) a single-line fence with leading prose before it still '
      'parses', (tester) async {
    final aiClient = FakeAiClient(
        response: 'Here are the findings:\n'
            '```json [{"line": 1, "issue": "x", "suggestion": "y", '
            '"severity": "minor"}] ```');
    List<GrammarFinding>? result;
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.issue, 'x');
  });

  testWidgets(
      'ai-prompts.md # Grammar Instructions overrides both the preview and '
      'the sent request (AC5/AD-11)', (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage:
          _storageWithPromptOverride(instructions: 'Custom grammar instructions.'),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), 'Custom grammar instructions.');

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(aiClient.requests, hasLength(1));
    expect(aiClient.requests.single.system,
        startsWith('Custom grammar instructions.'),
        reason: 'the response-format contract is appended after the '
            'override, not replaced by it (Review Decision 1)');
    expect(aiClient.requests.single.userContent, 'text');
  });

  testWidgets(
      '(Review Decision 1) a custom Grammar Instructions override cannot '
      'replace the JSON response-format contract the parser depends on',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageWithPromptOverride(
          instructions: 'Focus only on comma splices.'),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), 'Focus only on comma splices.');
    expect(_sectionText(tester, 1), contains('strict JSON array'));

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(aiClient.requests, hasLength(1));
    expect(aiClient.requests.single.system,
        contains('Focus only on comma splices.'));
    expect(aiClient.requests.single.system, contains('strict JSON array'));
  });

  testWidgets('a missing ai-prompts.md falls back to the hardcoded default (AC5)',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), contains('grammar, spelling'));
  });

  testWidgets(
      '(Review fix) the default instructions preserve the inner-monologue '
      'convention, matching project-context.md\'s own documented usage',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), contains('Inner monologue'));
  });

  testWidgets(
      '(Story 5.7) the default instructions list both the Russian and the '
      'English conditional markers as intentional markup', (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), contains('конец условия'));
    expect(_sectionText(tester, 0), contains('end if'));
  });

  testWidgets(
      'an empty-body Grammar Instructions section falls back to the '
      'hardcoded default, not an override with empty text (AC5)',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    await _pumpHost(
      tester,
      storage: _storageWithPromptOverride(instructions: '   '),
      aiClient: aiClient,
      text: 'text',
      onResult: (_) {},
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    expect(_sectionText(tester, 0), contains('grammar, spelling'));
  });

  testWidgets(
      'an AiClientException from sendMessage shows its message in a '
      'SnackBar and returns null, never throws (AC7/AD-8)', (tester) async {
    final aiClient = FakeAiClient(error: const AiAuthException('bad key'));
    List<GrammarFinding>? result = const [];
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('bad key'), findsOneWidget);
  });

  testWidgets(
      'cancelling the preview returns null without calling sendMessage (AC1)',
      (tester) async {
    final aiClient = FakeAiClient(response: '[]');
    List<GrammarFinding>? result = const [];
    await _pumpHost(
      tester,
      storage: _storageNoOverride(),
      aiClient: aiClient,
      text: 'text',
      onResult: (r) => result = r,
    );
    await tester.tap(find.text('review'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(aiClient.requests, isEmpty);
  });

  group('AI server config (Story 4.7)', () {
    testWidgets(
        'a resolved lore-story.json ai object flows into the sent request\'s '
        'model/baseUrl', (tester) async {
      final aiClient = FakeAiClient(response: '[]');
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"custom","model":"local-model",'
            '"baseUrl":"http://localhost:1234/v1"'),
        aiClient: aiClient,
        text: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('review'));
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
      final aiClient = FakeAiClient(response: '[]');
      await _pumpHost(
        tester,
        storage: _storageNoOverride(),
        aiClient: aiClient,
        text: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.model, isNull);
      expect(aiClient.requests.single.baseUrl, isNull);
    });

    testWidgets(
        '(Review fix) an unusable server config (custom with no baseUrl) '
        'shows an error and never opens the preview or sends anything',
        (tester) async {
      final aiClient = FakeAiClient(response: 'should never be sent');
      List<GrammarFinding>? result = const [];
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig('"server":"custom"'),
        aiClient: aiClient,
        text: 'text',
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('review'));
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
      final aiClient = FakeAiClient(response: '[]');
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"custom","protocol":"openai","model":"local-model",'
            '"baseUrl":"http://localhost:1234/v1"'),
        aiClient: aiClient,
        text: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.protocol, AiProtocol.openai);
    });

    testWidgets(
        '(AC2) server: "openrouter" with no protocol set also produces '
        'AiProtocol.openai on the sent request — the default', (tester) async {
      final aiClient = FakeAiClient(response: '[]');
      await _pumpHost(
        tester,
        storage:
            _storageWithServerConfig('"server":"openrouter","model":"gpt-x"'),
        aiClient: aiClient,
        text: 'text',
        onResult: (_) {},
      );
      await tester.tap(find.text('review'));
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
      List<GrammarFinding>? result = const [];
      await _pumpHost(
        tester,
        storage: _storageWithServerConfig(
            '"server":"anthropic","protocol":"openai"'),
        aiClient: aiClient,
        text: 'text',
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(result, isNull);
      expect(aiClient.requests, isEmpty);
      expect(find.byKey(const Key('context-preview-confirm')), findsNothing);
      expect(find.textContaining('protocol'), findsOneWidget);
    });
  });
}
