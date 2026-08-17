import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../storage/storage.dart';
import 'home_page.dart';
import 'theme.dart';
import 'theme_mode_controller.dart';

/// Builds a [RepoStorage] anchored at [rootPath]. Injected from the composition
/// root (`main.dart`) so the app never names a concrete adapter (AD-9 / AD-12).
typedef RepoStorageFactory = RepoStorage Function(String rootPath);

/// Root widget. Receives its collaborators by injection — it constructs none of
/// them itself; `main.dart` is the composition root.
class LoreStoryApp extends StatelessWidget {
  final RepoRootStore rootStore;
  final StoragePermission permission;
  final RepoStorageFactory storageFactory;

  /// Story 4.1 — where the AI provider API key is stored.
  final KeyStore keyStore;

  /// Story 4.3 — the AI provider client, threaded from here down to every
  /// screen that can reach a Translate action.
  final AiClient aiClient;

  /// Story 5.2 — the app-wide live theme signal, plus its persistence,
  /// behind one controlled surface (Review fix: no raw, externally-writable
  /// [ValueNotifier] field here). Threaded down to [HomePage] (and, from
  /// there, to `SettingsPage`) so the toggle can call [ThemeModeController.set]
  /// — one shared instance, injected once from `main.dart`, never constructed
  /// here.
  final ThemeModeController themeModeController;

  const LoreStoryApp({
    super.key,
    required this.rootStore,
    required this.permission,
    required this.storageFactory,
    required this.keyStore,
    required this.aiClient,
    required this.themeModeController,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeController.listenable,
      // `HomePage` doesn't depend on the resolved `mode` — only on the
      // stable `themeModeController` reference — so it's passed as `child:`
      // (Review fix) rather than constructed fresh inside `builder`, so a
      // theme toggle doesn't force it (and any already-pushed route beneath
      // it) to rebuild along with `MaterialApp` itself.
      child: HomePage(
        rootStore: rootStore,
        permission: permission,
        storageFactory: storageFactory,
        keyStore: keyStore,
        aiClient: aiClient,
        themeModeController: themeModeController,
      ),
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'Lore & Story',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: child,
        );
      },
    );
  }
}
