import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/app/theme_mode_controller.dart';

import '../fakes.dart';

/// End-to-end, full-[LoreStoryApp] coverage for Story 5.2's live, app-wide
/// theme signal — diverges enough from `settings_page_test.dart`'s isolated
/// `_pump` harness (which pumps a bare `SettingsPage`, not the whole app) to
/// warrant its own file.
Future<void> _pumpApp(
  WidgetTester tester, {
  required ThemeModeController themeModeController,
}) async {
  await tester.pumpWidget(LoreStoryApp(
    rootStore: FakeRepoRootStore(),
    permission: FakeStoragePermission(granted: false),
    storageFactory: (root) => FakeRepoStorage(root),
    keyStore: FakeKeyStore(),
    aiClient: FakeAiClient(),
    themeModeController: themeModeController,
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('App-wide theme (Story 5.2)', () {
    testWidgets('launches in light theme when the injected controller starts '
        'light (AC6 default)', (tester) async {
      await _pumpApp(tester,
          themeModeController: ThemeModeController(FakeThemeModeStore(),
              initial: ThemeMode.light));

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(Theme.of(tester.element(find.text('Grant access'))).brightness,
          Brightness.light);
    });

    testWidgets('launches in dark theme when the injected controller starts '
        'dark (AC3: the resolved-from-storage case)', (tester) async {
      await _pumpApp(tester,
          themeModeController: ThemeModeController(FakeThemeModeStore(),
              initial: ThemeMode.dark));

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.text('Grant access'))).brightness,
          Brightness.dark);
    });

    testWidgets(
        'flipping the controller after launch repaints the whole app live, '
        'with no restart required (AC2)', (tester) async {
      final controller = ThemeModeController(FakeThemeModeStore(),
          initial: ThemeMode.light);
      await _pumpApp(tester, themeModeController: controller);
      expect(Theme.of(tester.element(find.text('Grant access'))).brightness,
          Brightness.light);

      await controller.set(ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(Theme.of(tester.element(find.text('Grant access'))).brightness,
          Brightness.dark);
    });
  });
}
