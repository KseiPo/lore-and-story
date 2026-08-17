import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai/ai.dart';
import 'ai/messages_api_client.dart';
import 'ai/openai_compatible_client.dart';
import 'app/app.dart';
import 'app/theme_mode_controller.dart';
import 'storage/all_files_repo_storage.dart';
import 'storage/storage.dart';

/// Composition root. This is the ONLY place that names the concrete
/// [AllFilesRepoStorage] adapter and wires it to the [RepoStorage] port the rest
/// of the app depends on (AD-9 / AD-12) — and, since Story 4.3, the only place
/// that names the concrete [MessagesApiClient]/[OpenAiCompatibleClient] adapters
/// (Story 4.8) for the [AiClient] port. The rest of the app is threaded with
/// one [ProtocolRoutingAiClient] over both — which adapter actually handles a
/// given call is decided per-request by `AiRequest.protocol`, never by
/// rebuilding anything here.
void main() {
  final rootStore = RepoRootStore();
  final permission = StoragePermission();
  final keyStore = KeyStore();
  final httpClient = http.Client();
  final aiClient = ProtocolRoutingAiClient(
    anthropicClient: MessagesApiClient(httpClient: httpClient, keyStore: keyStore),
    openAiClient: OpenAiCompatibleClient(httpClient: httpClient, keyStore: keyStore),
  );
  RepoStorage buildStorage(String rootPath) => AllFilesRepoStorage(rootPath);

  // Story 5.2 — starts at the AC6 default (light) before the stored
  // preference is known, mirroring the existing pattern where `main()` stays
  // synchronous and never blocks `runApp` on I/O (`RepoRootStore`'s own
  // persisted value is likewise read later, not here). `ThemeModeController`
  // owns the notifier + persistence behind one controlled surface (Review
  // fix) — its `loadStored()` never throws and safely no-ops if the user has
  // already toggled the theme by the time this fire-and-forget call resolves.
  final themeModeController = ThemeModeController(ThemeModeStore());

  runApp(
    LoreStoryApp(
      rootStore: rootStore,
      permission: permission,
      storageFactory: buildStorage,
      keyStore: keyStore,
      aiClient: aiClient,
      themeModeController: themeModeController,
    ),
  );

  themeModeController.loadStored();
}
