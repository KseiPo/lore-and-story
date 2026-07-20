import 'package:flutter/material.dart';

import '../storage/storage.dart';
import 'home_page.dart';

/// Builds a [RepoStorage] anchored at [rootPath]. Injected from the composition
/// root (`main.dart`) so the app never names a concrete adapter (AD-9 / AD-12).
typedef RepoStorageFactory = RepoStorage Function(String rootPath);

/// Root widget. Receives its collaborators by injection — it constructs none of
/// them itself; `main.dart` is the composition root.
class LoreStoryApp extends StatelessWidget {
  final RepoRootStore rootStore;
  final StoragePermission permission;
  final RepoStorageFactory storageFactory;

  const LoreStoryApp({
    super.key,
    required this.rootStore,
    required this.permission,
    required this.storageFactory,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lore & Story',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomePage(
        rootStore: rootStore,
        permission: permission,
        storageFactory: storageFactory,
      ),
    );
  }
}
