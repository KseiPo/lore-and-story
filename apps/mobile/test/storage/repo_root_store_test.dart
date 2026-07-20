import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read returns null before any root is stored', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await RepoRootStore().read(), isNull);
  });

  test('write then read round-trips the chosen root (remembered across launches)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = RepoRootStore();
    await store.write('/storage/emulated/0/story-repo');

    // A fresh instance simulates a later launch reading the same prefs.
    expect(await RepoRootStore().read(), '/storage/emulated/0/story-repo');
  });

  test('clear forgets the stored root', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RepoRootStore();
    await store.write('/storage/emulated/0/story-repo');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
