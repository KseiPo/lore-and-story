import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai/ai.dart';
import 'ai/messages_api_client.dart';
import 'app/app.dart';
import 'storage/all_files_repo_storage.dart';
import 'storage/storage.dart';

/// Composition root. This is the ONLY place that names the concrete
/// [AllFilesRepoStorage] adapter and wires it to the [RepoStorage] port the rest
/// of the app depends on (AD-9 / AD-12) — and, since Story 4.3, the only place
/// that names the concrete [MessagesApiClient] adapter for the [AiClient] port.
void main() {
  final rootStore = RepoRootStore();
  final permission = StoragePermission();
  final keyStore = KeyStore();
  final aiClient = MessagesApiClient(httpClient: http.Client(), keyStore: keyStore);
  RepoStorage buildStorage(String rootPath) => AllFilesRepoStorage(rootPath);

  runApp(
    LoreStoryApp(
      rootStore: rootStore,
      permission: permission,
      storageFactory: buildStorage,
      keyStore: keyStore,
      aiClient: aiClient,
    ),
  );
}
