import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user-chosen repo root path across launches.
///
/// The root path is **user configuration**, not derived model data — so
/// persisting it is expected and does not violate AD-1 ("derived data is never
/// persisted"). It is non-secret, so `shared_preferences` is used;
/// `flutter_secure_storage` is reserved for the AI key (Epic 4).
class RepoRootStore {
  static const String _key = 'repo_root_path';

  /// Returns the stored absolute root path, or null if none has been chosen.
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Stores [rootPath] as the remembered repo root.
  Future<void> write(String rootPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, rootPath);
  }

  /// Forgets the stored root (e.g. when the user picks a different folder).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
