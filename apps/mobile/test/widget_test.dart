import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/storage/storage.dart';

import 'fakes.dart';

void main() {
  testWidgets('shows grant-access state when permission is not granted',
      (tester) async {
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(),
      permission: FakeStoragePermission(granted: false),
      storageFactory: (root) => FakeRepoStorage(root),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Grant access'), findsOneWidget);
    expect(find.text('Choose repo folder'), findsNothing);
  });

  testWidgets('shows choose-folder state when granted but no root stored',
      (tester) async {
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => FakeRepoStorage(root),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Choose repo folder'), findsOneWidget);
  });

  testWidgets('shows the ready view (root + entries) when granted with a stored root',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        RepoEntry(name: 'lore-story.json', path: 'lore-story.json', isDirectory: false),
      ],
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('/storage/emulated/0/repo'), findsOneWidget);
    expect(find.text('characters'), findsOneWidget);
    expect(find.text('lore-story.json'), findsOneWidget);
  });
}
