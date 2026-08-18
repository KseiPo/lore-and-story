import 'package:wakelock_plus/wakelock_plus.dart';

/// Seam over the platform's "keep screen on" mechanism (Story 5.4) — pure
/// interface, no I/O, mirroring every other I/O boundary in this app
/// ([KeyStore], [RepoStorage]): a real adapter here, a fake in tests, so
/// [WakeLockAiClient] (`ai_client.dart`) is testable without a platform
/// channel.
///
/// Not exported from `ai/ai.dart`'s barrel (AD-12) — only `main.dart` (the
/// composition root) and this slice's own tests import this file directly,
/// mirroring exactly why `messages_api_client.dart`/
/// `openai_compatible_client.dart` are withheld.
abstract interface class ScreenWakeLock {
  /// Prevents the screen from turning off due to inactivity, from now until
  /// [disable] is called.
  ///
  /// **Every implementation must never throw** (AD-8) — this is part of the
  /// interface contract, not just a style preference (Review fix, Story
  /// 5.4): [WakeLockAiClient.sendMessage] calls [enable] before its `try`
  /// block and [disable] inside a `finally`. An exception from [enable]
  /// would propagate before the request is even attempted; an exception
  /// from [disable] inside that `finally` would replace whichever exception
  /// was already propagating, silently masking the real stream error the
  /// `finally` was unwinding from. A wake-lock failure must never be
  /// surfaced as, or allowed to cause, an AI request failure (AC3) — any
  /// implementer (including a test fake) must swallow its own failures
  /// exactly like [WakelockPlusScreenWakeLock] does.
  Future<void> enable();

  /// Allows the screen to turn off normally again. See [enable]'s doc
  /// comment for why this must never throw.
  Future<void> disable();
}

/// The real [ScreenWakeLock], backed by `package:wakelock_plus` —
/// `FLAG_KEEP_SCREEN_ON` on the Android window, no special permission.
class WakelockPlusScreenWakeLock implements ScreenWakeLock {
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // AD-8: never throw — see ScreenWakeLock.enable's own doc comment.
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // AD-8: never throw — see ScreenWakeLock.enable's own doc comment.
    }
  }
}
