import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/app/settings_page.dart';
import 'package:lore_and_story/lore/lore.dart' show kProjectConfigFile;
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

/// [aiClient]/[storage] default to a plain [FakeAiClient]/`null` — every
/// pre-Story-4.7 call site is unaffected. Story 4.7's own Test Connection
/// tests pass their own to control what the AI "returns" and what
/// `lore-story.json` resolves to.
Future<void> _pump(
  WidgetTester tester,
  KeyStore keyStore, {
  AiClient? aiClient,
  RepoStorage? storage,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: SettingsPage(
      keyStore: keyStore,
      aiClient: aiClient ?? FakeAiClient(),
      storage: storage,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the entry field when no key is configured', (tester) async {
    await _pump(tester, FakeKeyStore());

    expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
    expect(find.byKey(const Key('settings-save-button')), findsOneWidget);
    expect(find.byKey(const Key('settings-configured-label')), findsNothing);
  });

  testWidgets('entering a key and saving shows the configured state '
      '(AC1/AC2/AC3)', (tester) async {
    await _pump(tester, FakeKeyStore());

    await tester.enterText(
        find.byKey(const Key('settings-key-field')), 'sk-ant-test-key');
    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-configured-label')), findsOneWidget);
    expect(find.byKey(const Key('settings-key-field')), findsNothing);
  });

  testWidgets('a previously-saved key is never re-displayed in the field on '
      'reopen (AC2) — only the masked "configured" indicator shows',
      (tester) async {
    final keyStore = FakeKeyStore(initial: 'sk-ant-already-saved');

    await _pump(tester, keyStore);

    expect(find.byKey(const Key('settings-configured-label')), findsOneWidget);
    expect(find.text('sk-ant-already-saved'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Clear returns to the not-configured state (AC3)', (tester) async {
    final keyStore = FakeKeyStore(initial: 'sk-ant-already-saved');
    await _pump(tester, keyStore);

    await tester.tap(find.byKey(const Key('settings-clear-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
    expect(await keyStore.isConfigured(), isFalse);
  });

  testWidgets('(review fix — AC3) Replace switches to the entry field '
      'WITHOUT deleting the currently-stored key first, so a cancelled or '
      'failed replace never leaves the app unconfigured', (tester) async {
    final keyStore = FakeKeyStore(initial: 'sk-ant-old-key');
    await _pump(tester, keyStore);

    await tester.tap(find.byKey(const Key('settings-replace-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
    // The old key is still there — Replace didn't clear it.
    expect(await keyStore.read(), 'sk-ant-old-key');

    await tester.enterText(
        find.byKey(const Key('settings-key-field')), 'sk-ant-new-key');
    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(await keyStore.read(), 'sk-ant-new-key');
    expect(find.byKey(const Key('settings-configured-label')), findsOneWidget);
  });

  testWidgets('saving a new key over an existing one replaces it, not merges '
      '(AC3)', (tester) async {
    final keyStore = FakeKeyStore(initial: 'sk-ant-old-key');
    await _pump(tester, keyStore);

    await tester.tap(find.byKey(const Key('settings-replace-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('settings-key-field')), 'sk-ant-new-key');
    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(await keyStore.read(), 'sk-ant-new-key');
  });

  testWidgets('a KeyStore failure on load shows a visible error state, '
      'never throws past the widget (AC4)', (tester) async {
    await _pump(tester, FakeKeyStore(failing: true));

    expect(tester.takeException(), isNull);
    expect(find.textContaining("Couldn't access secure storage"), findsOneWidget);
  });

  testWidgets('(review fix — AC4) the error state has a Retry action that '
      'reattempts the load', (tester) async {
    final keyStore = FakeKeyStore(failing: true);
    await _pump(tester, keyStore);
    expect(find.byKey(const Key('settings-retry-button')), findsOneWidget);

    // The underlying storage becomes reachable again before retrying.
    final recovered = FakeKeyStore(initial: 'sk-ant-test-key');
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        keyStore: recovered,
        aiClient: FakeAiClient(),
        storage: null,
      ),
    ));
    await tester.tap(find.byKey(const Key('settings-retry-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-configured-label')), findsOneWidget);
  });

  testWidgets('a KeyStore failure on save shows a snackbar, never throws '
      'past the widget (AC4)', (tester) async {
    // isConfigured() must succeed to reach the entry field, but write()
    // fails — a realistic split (e.g. storage becomes unavailable between
    // load and save).
    final keyStore = FakeKeyStore(failWrites: true);
    await _pump(tester, keyStore);

    await tester.enterText(
        find.byKey(const Key('settings-key-field')), 'sk-ant-test-key');
    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save'), findsOneWidget);
    // Stays on the entry field — the failed save didn't fake success.
    expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
  });

  testWidgets('(review fix) tapping Save with an empty field shows feedback '
      'instead of silently doing nothing', (tester) async {
    await _pump(tester, FakeKeyStore());

    await tester.tap(find.byKey(const Key('settings-save-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a key first'), findsOneWidget);
    // Still on the entry field, nothing was saved.
    expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
  });

  group('Test connection (Story 4.7)', () {
    testWidgets('the button does not appear in the notConfigured stage',
        (tester) async {
      await _pump(tester, FakeKeyStore());
      expect(find.byKey(const Key('settings-test-connection-button')),
          findsNothing);
    });

    testWidgets('the button does not appear in the error stage', (tester) async {
      await _pump(tester, FakeKeyStore(failing: true));
      expect(find.byKey(const Key('settings-test-connection-button')),
          findsNothing);
    });

    testWidgets('the button appears in the configured stage', (tester) async {
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'));
      expect(find.byKey(const Key('settings-test-connection-button')),
          findsOneWidget);
    });

    testWidgets('tapping it with a successful response shows a success '
        'SnackBar (AC4)', (tester) async {
      final aiClient = FakeAiClient(response: 'OK');
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Connection successful.'), findsOneWidget);
      expect(aiClient.requests, hasLength(1));
    });

    testWidgets(
        '(Review fix) a failing connection with a provider-sourced message '
        'is prefixed to make its remote origin unambiguous (AC4)',
        (tester) async {
      final aiClient = FakeAiClient(error: const AiAuthException('bad key'));
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Auth/InvalidRequest/RateLimit/Server messages can originate from a
      // remote response body (`_extractErrorMessage`) — a custom endpoint
      // could put attacker-chosen text there, so it must never render
      // indistinguishably from the app's own copy.
      expect(find.text('Server said: bad key'), findsOneWidget);
      expect(find.text('bad key'), findsNothing,
          reason: 'the raw, unprefixed message must not also be shown');
    });

    testWidgets(
        '(Review fix) a locally-diagnosed failure (no key configured) is '
        'shown without the remote-origin prefix', (tester) async {
      final aiClient =
          FakeAiClient(error: const AiNotConfiguredException('No API key configured.'));
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(find.text('No API key configured.'), findsOneWidget);
      expect(find.textContaining('Server said:'), findsNothing);
    });

    testWidgets(
        '(Review fix) a 200 response that streams no actual text is '
        'reported as a distinct failure, not "Connection successful."',
        (tester) async {
      // A response with no content — FakeAiClient() default (response and
      // error both null) yields nothing, mirroring a 200 from a proxy or a
      // wrong-protocol server.
      final aiClient = FakeAiClient();
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Connection successful.'), findsNothing);
      expect(
          find.textContaining('returned no text'), findsOneWidget);
    });

    testWidgets(
        '(Review fix) an unusable server config (custom with no baseUrl) '
        'is reported via the same typed-exception path, never silently '
        'sent to Anthropic', (tester) async {
      final aiClient = FakeAiClient(response: 'should never be sent');
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{"ai":{"server":"custom"}}',
      });
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient, storage: storage);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(aiClient.requests, isEmpty);
      expect(find.textContaining('server'), findsOneWidget);
    });

    testWidgets(
        '(Review fix) Replace/Clear are disabled while a test is in flight',
        (tester) async {
      final aiClient = _ControllableAiClient();
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pump();

      final replaceButton = tester
          .widget<FilledButton>(find.byKey(const Key('settings-replace-button')));
      final clearButton = tester
          .widget<OutlinedButton>(find.byKey(const Key('settings-clear-button')));
      expect(replaceButton.onPressed, isNull);
      expect(clearButton.onPressed, isNull);

      aiClient.complete('OK');
      await tester.pumpAndSettle();
    });

    testWidgets('with storage: null, it still completes using '
        'AiServerConfig.empty, never throws', (tester) async {
      final aiClient = FakeAiClient(response: 'OK');
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient, storage: null);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Connection successful.'), findsOneWidget);
      expect(aiClient.requests.single.model, isNull);
      expect(aiClient.requests.single.baseUrl, isNull);
    });

    testWidgets('a resolved lore-story.json ai object flows into the test '
        'request\'s model/baseUrl', (tester) async {
      final aiClient = FakeAiClient(response: 'OK');
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile:
            '{"ai":{"server":"custom","model":"local-model",'
                '"baseUrl":"http://localhost:1234/v1"}}',
      });
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          aiClient: aiClient, storage: storage);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.model, 'local-model');
      expect(aiClient.requests.single.baseUrl,
          Uri.parse('http://localhost:1234/v1'));
    });
  });

  group('Malformed lore-story.json warning (Story 4.7, Review fix)', () {
    testWidgets(
        'a genuinely malformed lore-story.json shows a warning banner — '
        'never a display of the resolved config (AC5)', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{ broken',
      });
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          storage: storage);

      expect(find.byKey(const Key('settings-ai-config-warning')), findsOneWidget);
      // AC5: no server/protocol/model VALUE anywhere on screen.
      expect(find.textContaining('anthropic'), findsNothing);
      expect(find.textContaining('custom'), findsNothing);
    });

    testWidgets(
        'an absent lore-story.json shows no warning — the ordinary, '
        'unconfigured case', (tester) async {
      final storage = FakeRepoStorage('/repo');
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          storage: storage);

      expect(find.byKey(const Key('settings-ai-config-warning')), findsNothing);
    });

    testWidgets(
        'a well-formed lore-story.json with no ai object shows no warning',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{"loreDir":"lore"}',
      });
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          storage: storage);

      expect(find.byKey(const Key('settings-ai-config-warning')), findsNothing);
    });

    testWidgets('storage: null shows no warning (nothing to check)',
        (tester) async {
      await _pump(tester, FakeKeyStore(initial: 'sk-ant-already-saved'),
          storage: null);

      expect(find.byKey(const Key('settings-ai-config-warning')), findsNothing);
    });

    testWidgets('the warning also appears in the notConfigured stage',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{ broken',
      });
      await _pump(tester, FakeKeyStore(), storage: storage);

      expect(find.byKey(const Key('settings-ai-config-warning')), findsOneWidget);
    });
  });
}

/// An [AiClient] whose `sendMessage` stream stays open until [complete] is
/// called — lets a test hold a connection test "in flight" deliberately,
/// unlike [FakeAiClient] which always resolves immediately. Mirrors
/// `paired_editor_page_test.dart`'s own `_ControllableAiClient`.
class _ControllableAiClient implements AiClient {
  final _controller = StreamController<String>();

  @override
  Stream<String> sendMessage(AiRequest request) => _controller.stream;

  void complete(String text) {
    _controller
      ..add(text)
      ..close();
  }
}
