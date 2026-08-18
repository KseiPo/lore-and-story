import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/app/settings_page.dart';
import 'package:lore_and_story/app/theme_mode_controller.dart';
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
  ThemeModeController? themeModeController,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: SettingsPage(
      keyStore: keyStore,
      aiClient: aiClient ?? FakeAiClient(),
      storage: storage,
      themeModeController:
          themeModeController ?? ThemeModeController(FakeThemeModeStore()),
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
        themeModeController: ThemeModeController(FakeThemeModeStore()),
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

  group('Test connection (Story 4.7, gating widened Story 4.8/AC3)', () {
    testWidgets(
        '(Story 4.8) the button also appears in the notConfigured stage — '
        'a local OpenAI-compatible server typically needs no key at all',
        (tester) async {
      await _pump(tester, FakeKeyStore());
      expect(find.byKey(const Key('settings-test-connection-button')),
          findsOneWidget);
      // Still alongside the key field/Save button, not replacing them.
      expect(find.byKey(const Key('settings-key-field')), findsOneWidget);
      expect(find.byKey(const Key('settings-save-button')), findsOneWidget);
    });

    testWidgets(
        '(Story 4.8) tapping it in the notConfigured stage with no key ever '
        'saved shows the success SnackBar (the key-less local-server case)',
        (tester) async {
      final aiClient = FakeAiClient(response: 'OK');
      await _pump(tester, FakeKeyStore(), aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Connection successful'), findsOneWidget);
    });

    testWidgets(
        '(Story 4.8) Save is disabled while a test is in flight in the '
        'notConfigured stage', (tester) async {
      final aiClient = _ControllableAiClient();
      await _pump(tester, FakeKeyStore(), aiClient: aiClient);

      await tester.tap(find.byKey(const Key('settings-test-connection-button')));
      await tester.pump();

      final saveButton =
          tester.widget<FilledButton>(find.byKey(const Key('settings-save-button')));
      expect(saveButton.onPressed, isNull);

      aiClient.complete('OK');
      await tester.pumpAndSettle();
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
      expect(find.textContaining('Connection successful.'), findsOneWidget);
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
      expect(find.textContaining('Server said: bad key'), findsOneWidget);
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

      // Story 5.3: this failure happens after config resolution succeeds
      // (it's thrown during the actual request, not while resolving
      // server/protocol), so it also gains the "tried ..." suffix (AC1) —
      // textContaining rather than exact match, same as the other
      // AiClientException-path assertions this story touches.
      expect(find.textContaining('No API key configured.'), findsOneWidget);
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
      // Story 5.3 (AC3): resolveOrigin/resolveEffectiveProtocol never
      // succeeded here, so nothing was resolved to append — the message
      // must stay exactly as it was pre-Story-5.3, no "Tried: ..." suffix.
      expect(find.textContaining('Tried:'), findsNothing);
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
      expect(find.textContaining('Connection successful.'), findsOneWidget);
      expect(find.textContaining(kDefaultAnthropicEndpoint), findsOneWidget);
      expect(aiClient.requests.single.model, isNull);
      expect(aiClient.requests.single.baseUrl, isNull);
      // Story 5.3 (AC1): the model segment is gracefully omitted when no
      // model override is set — no dangling ", null" / trailing comma
      // artifact from the Anthropic-default case's null model.
      expect(find.textContaining(', null'), findsNothing);
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
      // Story 5.3 (AC1): the outcome message states the exact resolved
      // endpoint, protocol, and model — so a sync-lagged lore-story.json
      // shows itself immediately instead of silently testing a stale value.
      expect(find.textContaining('http://localhost:1234/v1'), findsOneWidget);
      // No explicit "protocol" in this config, and `server: "custom"` alone
      // defaults to anthropic (resolveEffectiveProtocol's own documented
      // default) — not openai.
      expect(find.textContaining('anthropic'), findsOneWidget);
      expect(find.textContaining('local-model'), findsOneWidget);
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

  group('Theme toggle (Story 5.2)', () {
    testWidgets('starts as the dark-mode icon when currently light (tap to go dark)',
        (tester) async {
      await _pump(tester, FakeKeyStore(),
          themeModeController: ThemeModeController(FakeThemeModeStore(),
              initial: ThemeMode.light));

      expect(find.byKey(const Key('theme-toggle-button')), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
    });

    testWidgets('starts as the light-mode icon when currently dark (tap to go light)',
        (tester) async {
      await _pump(tester, FakeKeyStore(),
          themeModeController: ThemeModeController(FakeThemeModeStore(),
              initial: ThemeMode.dark));

      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
    });

    testWidgets(
        'tapping the toggle flips the controller and persists the new mode '
        '(AC2, AC3)', (tester) async {
      final store = FakeThemeModeStore();
      final controller = ThemeModeController(store, initial: ThemeMode.light);
      await _pump(tester, FakeKeyStore(), themeModeController: controller);

      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();

      expect(controller.value, ThemeMode.dark);
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      expect(await store.read(), ThemeMode.dark);
    });

    testWidgets('tapping it again flips back to light', (tester) async {
      final store = FakeThemeModeStore(initial: ThemeMode.dark);
      final controller = ThemeModeController(store, initial: ThemeMode.dark);
      await _pump(tester, FakeKeyStore(), themeModeController: controller);

      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();

      expect(controller.value, ThemeMode.light);
      expect(await store.read(), ThemeMode.light);
    });

    testWidgets(
        'a persistence failure never blocks the visual toggle (AC6/AD-8)',
        (tester) async {
      final controller =
          ThemeModeController(_FailingThemeModeStore(), initial: ThemeMode.light);
      await _pump(tester, FakeKeyStore(), themeModeController: controller);

      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();

      // The write failed, but the toggle itself still applied and the app
      // never crashed.
      expect(tester.takeException(), isNull);
      expect(controller.value, ThemeMode.dark);
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    });

    testWidgets(
        "a still-in-flight loadStored() call never reverts a user's own "
        'toggle (Review fix — end-to-end coverage of the ThemeModeController '
        'race guard, from an actual widget tap)', (tester) async {
      final store = _SlowReadThemeModeStore();
      final controller = ThemeModeController(store, initial: ThemeMode.light);
      await _pump(tester, FakeKeyStore(), themeModeController: controller);

      // Simulate `main.dart`'s fire-and-forget load still being in flight
      // when the user opens Settings and taps the toggle.
      final loadFuture = controller.loadStored();

      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();
      expect(controller.value, ThemeMode.dark);

      // The pending load resolves with a stale value read before the tap —
      // it must not override the toggle that already happened.
      store.release(ThemeMode.light);
      await loadFuture;

      expect(controller.value, ThemeMode.dark);
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    });
  });
}

/// A [ThemeModeStore] whose [read] doesn't resolve until [release] is
/// called — lets a test hold a "load in flight" state deliberately, to
/// exercise the race between a still-pending load and a user's own toggle.
class _SlowReadThemeModeStore extends ThemeModeStore {
  final _gate = Completer<ThemeMode?>();

  void release(ThemeMode? value) => _gate.complete(value);

  @override
  Future<ThemeMode?> read() => _gate.future;
}

/// A [ThemeModeStore] whose [write] always throws — for exercising the AD-8
/// never-crash path (Story 5.2, AC6): a persistence failure must never block
/// the immediate visual toggle.
class _FailingThemeModeStore extends ThemeModeStore {
  @override
  Future<void> write(ThemeMode mode) async {
    throw Exception('boom (fake persistence failure)');
  }
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
