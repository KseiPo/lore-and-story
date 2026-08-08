/// Public interface (barrel) of the `ai/` slice — port, adapter-facing key
/// storage, and the context-preview / translate UI. Other slices depend only
/// on these exports, never on the slice's internal files (AD-12).
///
/// The concrete `MessagesApiClient` adapter is deliberately NOT exported: only
/// the composition root (`main.dart`, and this slice's own tests) may name it,
/// by importing its file directly — mirrors `storage/storage.dart` withholding
/// `AllFilesRepoStorage`.
///
/// The `ai/` slice produces text only — it never writes files; generated
/// output is persisted by the `lore/` slice via `RepoStorage` (AD-11).
library;

export 'ai_client.dart';
export 'context_preview.dart';
export 'key_store.dart';
export 'translate_action.dart';
