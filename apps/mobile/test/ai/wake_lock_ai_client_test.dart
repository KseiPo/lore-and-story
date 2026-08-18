import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/ai/screen_wake_lock.dart';

import '../fakes.dart';

/// In-memory [ScreenWakeLock] for widget/unit tests (no platform channel) —
/// records call order so tests can assert enable-before-yield and
/// disable-exactly-once, mirroring [FakeAiClient]'s own recording-double
/// pattern.
class FakeScreenWakeLock implements ScreenWakeLock {
  final List<String> calls = [];
  final _disabledCompleter = Completer<void>();

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async {
    calls.add('disable');
    if (!_disabledCompleter.isCompleted) _disabledCompleter.complete();
  }

  /// Completes the instant [disable] is first called (Review fix, Story
  /// 5.4) — lets a test await the exact moment `disable()` runs instead of
  /// guessing how many event-loop turns a `Duration.zero` delay needs to
  /// cover.
  Future<void> get disabled => _disabledCompleter.future;
}

void main() {
  group('WakeLockAiClient (Story 5.4)', () {
    const request = AiRequest(system: 's', userContent: 'u');

    test('enable() is called before any chunk is yielded, disable() exactly '
        'once after the stream completes (AC1)', () async {
      final wakeLock = FakeScreenWakeLock();
      final inner = FakeAiClient(response: 'OK');
      final client = WakeLockAiClient(inner: inner, screenWakeLock: wakeLock);

      final chunks = <String>[];
      await for (final chunk in client.sendMessage(request)) {
        // enable() must have already happened by the time the first chunk
        // arrives.
        expect(wakeLock.calls, ['enable']);
        chunks.add(chunk);
      }

      expect(chunks, ['OK']);
      expect(wakeLock.calls, ['enable', 'disable']);
    });

    test('disable() is still called exactly once when the stream errors, and '
        'the original AiClientException still propagates unchanged (AC1, AC3)',
        () async {
      final wakeLock = FakeScreenWakeLock();
      final inner = FakeAiClient(error: const AiAuthException('bad key'));
      final client = WakeLockAiClient(inner: inner, screenWakeLock: wakeLock);

      await expectLater(
        client.sendMessage(request),
        emitsError(isA<AiAuthException>()
            .having((e) => e.message, 'message', 'bad key')),
      );
      // `disable()` runs inside the outer generator's `finally`, which the
      // error's delivery is nested inside — await the exact completion
      // signal (Review fix) rather than guessing a fixed number of
      // event-loop turns.
      await wakeLock.disabled;

      expect(wakeLock.calls, ['enable', 'disable']);
    });

    test('disable() is still called when the subscription is cancelled '
        'partway through an in-progress response (AC4 — the exact scenario '
        "SettingsPage's _testSubscription?.cancel() exercises)", () async {
      final wakeLock = FakeScreenWakeLock();
      final inner = ControllableAiClient();
      final client = WakeLockAiClient(inner: inner, screenWakeLock: wakeLock);

      final received = <String>[];
      final firstChunk = Completer<void>();
      final subscription = client.sendMessage(request).listen((chunk) {
        received.add(chunk);
        if (!firstChunk.isCompleted) firstChunk.complete();
      });

      inner.add('partial');
      // Wait for the actual event (the chunk being received) rather than a
      // guessed delay — proves the response was genuinely in progress, not
      // cancelled before anything happened.
      await firstChunk.future;
      expect(received, ['partial']);

      await subscription.cancel();
      await wakeLock.disabled;

      expect(wakeLock.calls, ['enable', 'disable']);
    });

    test('yielded chunks pass through completely unchanged, in order and '
        'content (transparent decorator, AC5)', () async {
      final wakeLock = FakeScreenWakeLock();
      final inner = ControllableAiClient();
      final client = WakeLockAiClient(inner: inner, screenWakeLock: wakeLock);

      final received = <String>[];
      final done = Completer<void>();
      client.sendMessage(request).listen(
            received.add,
            onDone: done.complete,
          );

      inner.add('one');
      inner.add('two');
      inner.complete('three');
      await done.future;

      expect(received, ['one', 'two', 'three']);
    });
  });
}
