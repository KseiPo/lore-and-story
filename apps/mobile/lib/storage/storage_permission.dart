import 'package:permission_handler/permission_handler.dart';

/// Thin service around the all-files-access permission
/// (`MANAGE_EXTERNAL_STORAGE`).
///
/// Kept inside the `storage/` slice so the permission — like `dart:io` — never
/// leaks into the loader, editor, or UI (AD-3). On Android 11+ this is a special
/// "All files access" permission: it is granted by the user on a system Settings
/// screen, not via a normal runtime dialog, so [request] may return while the
/// user is still in Settings — always re-check with [isGranted] on app resume.
class StoragePermission {
  /// Whether all-files access is currently granted.
  Future<bool> isGranted() => Permission.manageExternalStorage.isGranted;

  /// Requests all-files access. On Android this routes the user to the system
  /// "All files access" settings screen. Returns the granted state as known
  /// immediately after; callers should still re-check on resume.
  Future<bool> request() async {
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  /// Opens the app's settings page (fallback when the request cannot surface the
  /// toggle, e.g. after a permanent denial).
  Future<bool> openSettings() => openAppSettings();
}
