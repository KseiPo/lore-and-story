import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // flutter_secure_storage 11.0.0 ships the same mock-testing support as
    // shared_preferences's setMockInitialValues (verified by reading the
    // package source — Story 4.1's own "verify before asserting" note).
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('isConfigured is false before any key is stored', () async {
    expect(await const KeyStore().isConfigured(), isFalse);
  });

  test('read returns null before any key is stored', () async {
    expect(await const KeyStore().read(), isNull);
  });

  test('write then read round-trips the key', () async {
    const store = KeyStore();
    await store.write('sk-ant-test-key');
    expect(await store.read(), 'sk-ant-test-key');
  });

  test('write then isConfigured is true, without exposing the value', () async {
    const store = KeyStore();
    await store.write('sk-ant-test-key');
    expect(await store.isConfigured(), isTrue);
  });

  test('a fresh KeyStore instance sees a key written by another instance '
      '(persisted, not held in memory)', () async {
    await const KeyStore().write('sk-ant-test-key');
    expect(await const KeyStore().read(), 'sk-ant-test-key');
  });

  test('writing a new key replaces the old one (no merge/append)', () async {
    const store = KeyStore();
    await store.write('sk-ant-old-key');
    await store.write('sk-ant-new-key');
    expect(await store.read(), 'sk-ant-new-key');
  });

  test('clear forgets the stored key', () async {
    const store = KeyStore();
    await store.write('sk-ant-test-key');
    await store.clear();
    expect(await store.read(), isNull);
    expect(await store.isConfigured(), isFalse);
  });

  test('clear on an already-empty store is a no-op, never throws', () async {
    // (Review fix) `returnsNormally` only checks the closure doesn't throw
    // *synchronously* — clear() returns a Future, so an async failure would
    // have passed this unnoticed. `completes` actually awaits it.
    await expectLater(const KeyStore().clear(), completes);
  });

  test('(review fix) write rejects an empty key or one containing a '
      'control character (e.g. an embedded newline from a copy-paste '
      'artifact), which would otherwise later break the HTTP header the '
      'key is placed into', () async {
    const store = KeyStore();
    await expectLater(store.write(''), throwsArgumentError);
    await expectLater(store.write('sk-ant-with\nnewline'), throwsArgumentError);
    await expectLater(store.write('sk-ant-with\ttab'), throwsArgumentError);
    // A rejected write must not have touched storage.
    expect(await store.isConfigured(), isFalse);
  });
}
