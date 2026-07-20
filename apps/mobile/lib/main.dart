import 'package:flutter/material.dart';

import 'app/app.dart';
import 'storage/all_files_repo_storage.dart';
import 'storage/storage.dart';

/// Composition root. This is the ONLY place that names the concrete
/// [AllFilesRepoStorage] adapter and wires it to the [RepoStorage] port the rest
/// of the app depends on (AD-9 / AD-12).
void main() {
  final rootStore = RepoRootStore();
  final permission = StoragePermission();
  RepoStorage buildStorage(String rootPath) => AllFilesRepoStorage(rootPath);

  runApp(
    LoreStoryApp(
      rootStore: rootStore,
      permission: permission,
      storageFactory: buildStorage,
    ),
  );
}
