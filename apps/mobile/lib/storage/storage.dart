/// Public interface (barrel) of the `storage/` slice. Other slices depend only
/// on these exports, never on the slice's internal files (AD-12).
///
/// The concrete `AllFilesRepoStorage` adapter is deliberately NOT exported: only
/// the composition root (`main.dart`) may name it, by importing its file
/// directly. Feature slices see only the port and the value types (AD-9/AD-12).
library;

export 'repo_storage.dart';
export 'android_storage.dart';
export 'repo_root_store.dart';
export 'round_trip_spike.dart';
export 'storage_permission.dart';
