/// Android platform-storage constants used by the all-files adapter and the
/// repo-root picker.
///
/// Kept out of the pure [RepoStorage] port (`repo_storage.dart`) so the port
/// stays platform-agnostic — a future SAF or desktop backend would not inherit
/// an Android-specific path.
library;

/// Primary shared-storage root on Android. With `MANAGE_EXTERNAL_STORAGE`
/// granted, the app enumerates real filesystem paths from here — the base for
/// the in-app repo-root picker (a real path, never a SAF `content://` URI; see
/// addendum §A).
const String kPrimaryExternalStorageRoot = '/storage/emulated/0';
