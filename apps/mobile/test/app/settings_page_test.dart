import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/app/settings_page.dart';

import '../fakes.dart';

Future<void> _pump(WidgetTester tester, KeyStore keyStore) async {
  await tester.pumpWidget(MaterialApp(home: SettingsPage(keyStore: keyStore)));
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
    await tester.pumpWidget(MaterialApp(home: SettingsPage(keyStore: recovered)));
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
}
