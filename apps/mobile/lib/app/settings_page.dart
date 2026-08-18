import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../storage/storage.dart';
import 'theme.dart';
import 'theme_mode_controller.dart';

/// The states this screen can be in. [error] covers any secure-storage
/// failure (read/write/delete) — AD-8: never crash, always a visible state.
enum _Stage { loading, notConfigured, configured, error }

/// Manage the AI provider API key (Story 4.1, FR20/NFR5): one field, Save,
/// Clear. Deliberately minimal — Epic 4 targets a single provider
/// (Anthropic), so there is no provider picker or multi-page settings
/// surface here. Story 4.7 adds one Test Connection action; it still shows
/// no server/protocol/model picker or display — those are configured
/// entirely by editing `lore-story.json` (AC5). It does show a warning when
/// that file's `ai` object exists but could not be parsed at all — distinct
/// from a *display* of the resolved values, which AC5 forbids.
///
/// The key is never re-displayed once saved (NFR5): this screen only ever
/// asks [KeyStore.isConfigured] (never [KeyStore.read]) to decide which UI to
/// show, so the real secret never becomes a widget-local variable it doesn't
/// need to be.
class SettingsPage extends StatefulWidget {
  final KeyStore keyStore;

  /// Story 4.7 — used by Test Connection to actually attempt a live request.
  /// The same long-lived instance every other AI action already uses
  /// (`main.dart`'s composition root); never rebuilt here.
  final AiClient aiClient;

  /// Story 4.7 — resolves `lore-story.json`'s `ai` object for Test
  /// Connection and the malformed-config warning. `null` when this screen
  /// is opened before a repo root is granted/picked (`HomePage`'s
  /// `needsPermission`/`needsRoot`/`loading` stages) — both features then
  /// fall back to [AiServerConfig.empty], i.e. today's hardcoded Anthropic
  /// defaults, never blocking Settings from opening (AD-8).
  final RepoStorage? storage;

  /// Story 5.2 — the app-wide theme signal + persistence this screen's
  /// toggle reads (to decide which icon to show) and calls [ThemeModeController.set]
  /// on (to flip it and save the change together).
  final ThemeModeController themeModeController;

  const SettingsPage({
    super.key,
    required this.keyStore,
    required this.aiClient,
    required this.storage,
    required this.themeModeController,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Stage _stage = _Stage.loading;
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  /// Re-entrancy guard, same shape as [_saving].
  bool _testing = false;

  /// Held so [dispose] can cancel a still-in-flight test — otherwise
  /// popping and reopening this screen starts a fresh, unbounded, billed
  /// request every time with no way to stop the earlier one (Review fix,
  /// Story 4.7 code review).
  StreamSubscription<String>? _testSubscription;

  /// True when `lore-story.json`'s `ai` object exists but the file's JSON
  /// itself could not be decoded at all (Review fix, Story 4.7 code review
  /// Decision 4) — shown as a warning, never as a display of the resolved
  /// config (AC5 forbids that; a warning is not a display).
  bool _aiConfigMalformed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _testSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final configured = await widget.keyStore.isConfigured();
      final malformed = widget.storage != null
          ? (await resolveAiServerConfig(widget.storage!)).parseFailed
          : false;
      if (!mounted) return;
      setState(() {
        _stage = configured ? _Stage.configured : _Stage.notConfigured;
        _aiConfigMalformed = malformed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.error);
    }
  }

  /// (Review fix — AC4) The error stage was a dead end with no way back.
  Future<void> _retryLoad() async {
    setState(() => _stage = _Stage.loading);
    await _load();
  }

  /// (Review fix — AC3) Switches to the entry field *without* deleting the
  /// currently-stored key, so replacing a key is possible without a window
  /// where none is configured. If the user backs out without saving, the
  /// original key is untouched — nothing was cleared to get here.
  void _replace() {
    setState(() => _stage = _Stage.notConfigured);
  }

  Future<void> _save() async {
    final apiKey = _controller.text.trim();
    if (_saving || _testing) return;
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a key first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.keyStore.write(apiKey);
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.configured;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the key. Try again.')),
      );
    }
  }

  /// Story 5.3 (AC1) — narrows Story 4.7's AC5 "no server/protocol/model
  /// display" rule: that rule was about not permanently cluttering the
  /// screen with a config summary, not about withholding this information
  /// at the one moment the author explicitly asked the app to prove the
  /// connection works (`lore-story.json` syncs via Syncthing, so it can take
  /// a moment to arrive — this is how the author checks whether the app
  /// already picked up their latest edit). [model] is gracefully omitted
  /// (no dangling comma) when `null` — the Anthropic-default case with no
  /// override set.
  ///
  /// On its own line (Review fix), not appended inline with a bare leading
  /// space: [e.message] in the exception-handler call site can originate
  /// from a remote server's response body (an untrusted string, per the
  /// existing "Review fix" comment there) — a plain space is too weak a
  /// boundary between that and this trusted, app-generated text. The
  /// `Tried:` label makes this segment's origin unambiguous even if a
  /// crafted remote message tried to imitate it.
  String _connectionTargetSuffix(String endpoint, AiProtocol protocol, String? model) =>
      '\nTried: $endpoint (${protocol.name}${model != null ? ', $model' : ''})';

  /// Story 4.7/AC4 — makes one minimal live request against the resolved
  /// server/model (falling back to today's hardcoded Anthropic defaults when
  /// [SettingsPage.storage] is `null`) and reports success or a clear
  /// failure reason, so the author doesn't need a real translate/grammar
  /// action just to find out the configuration is wrong.
  ///
  /// `maxTokens: 16384` (Review fix, Story 4.7 code review) — matches every
  /// other caller (`translate_action.dart`/`grammar_action.dart`); the
  /// client's unconditional `thinking: {type: adaptive}` draws from the same
  /// budget, so a small `maxTokens` truncates even a correct, working
  /// configuration and reports it as failed.
  ///
  /// Success requires at least one non-empty text chunk to have arrived
  /// (Review fix) — a 200 response that streams no actual text (a proxy, an
  /// nginx welcome page, an OpenAI-format server replying in the wrong
  /// shape) previously counted as "successful" merely for not throwing.
  ///
  /// Held as a cancellable [_testSubscription] (not a plain `await for`) so
  /// [dispose] can stop a still-in-flight request when this screen is
  /// popped mid-test (Review fix) — an explicit UI-level `.timeout()` on top
  /// of that was tried and dropped: it deadlocks `pumpAndSettle` inside
  /// `testWidgets`' fake-time zone even though it works in production,
  /// verified empirically with an isolated probe. `MessagesApiClient`'s own
  /// `requestTimeout`/`streamIdleTimeout` (30s/60s, ×3 attempts) already
  /// bound how long a stalled request can run.
  Future<void> _testConnection() async {
    if (_testing || _saving) return;
    setState(() => _testing = true);

    // Story 5.3 (AC3, Review fix) — resolved first, in its own try/catch,
    // exactly mirroring `translate_action.dart`/`grammar_action.dart`'s own
    // early-resolve pattern: an `AiConfigException` here means nothing was
    // actually resolved, so it's shown exactly as it was pre-Story-5.3, with
    // no diagnostic suffix. Structuring it this way (rather than one shared
    // try/catch with a nullable "did resolution succeed" flag threaded
    // through it) makes that a fact the rest of this method can rely on,
    // not a runtime flag every future edit has to keep consistent by hand.
    final AiServerConfig serverConfig;
    final Uri? resolvedOrigin;
    final AiProtocol protocol;
    try {
      serverConfig = widget.storage != null
          ? await resolveAiServerConfig(widget.storage!)
          : AiServerConfig.empty;
      resolvedOrigin = resolveOrigin(serverConfig);
      protocol = resolveEffectiveProtocol(serverConfig);
    } on AiConfigException catch (e) {
      if (!mounted) return;
      setState(() => _testing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _testing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection test failed.')),
      );
      return;
    }

    // Story 5.3 (AC1) — the exact endpoint/protocol/model this test will
    // try. `describeEndpoint` mirrors each `AiClient` adapter's own request
    // path (`/messages`/`/chat/completions`), not just the bare origin
    // (Review fix), so what's shown matches what's actually requested.
    final endpoint = describeEndpoint(origin: resolvedOrigin, protocol: protocol);
    final targetSuffix =
        _connectionTargetSuffix(endpoint, protocol, serverConfig.model);

    try {
      final request = AiRequest(
        system: 'Reply with exactly: OK',
        userContent: 'Connection test.',
        maxTokens: 16384,
        model: serverConfig.model,
        baseUrl: resolvedOrigin,
        protocol: protocol,
      );

      var receivedText = false;
      final completer = Completer<void>();
      _testSubscription = widget.aiClient.sendMessage(request).listen(
            (chunk) {
              if (chunk.trim().isNotEmpty) receivedText = true;
            },
            onError: completer.completeError,
            onDone: completer.complete,
            cancelOnError: true,
          );
      await completer.future;
      _testSubscription = null;

      if (!receivedText) {
        if (!mounted) return;
        setState(() => _testing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Connected, but the server returned no text — check the '
                  'server address and protocol.$targetSuffix')),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _testing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection successful.$targetSuffix')),
      );
    } on AiClientException catch (e) {
      _testSubscription = null;
      if (!mounted) return;
      setState(() => _testing = false);
      // (Review fix) A custom endpoint can put attacker-chosen text into a
      // provider error body (`_extractErrorMessage`), which would otherwise
      // render in this SnackBar indistinguishably from the app's own
      // copy — prefix it as remote-sourced so its origin is unambiguous.
      // Locally-diagnosed failures (no key configured, network-level,
      // config-resolution) never touched a remote body, so they stay
      // unprefixed.
      final fromRemoteBody = e is AiAuthException ||
          e is AiInvalidRequestException ||
          e is AiRateLimitException ||
          e is AiServerException;
      final text = fromRemoteBody ? 'Server said: ${e.message}' : e.message;
      // Story 5.3 (AC1) — reached only once resolution already succeeded
      // above, so `targetSuffix` is always available here (see this
      // method's own restructuring note).
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$text$targetSuffix')));
    } catch (_) {
      _testSubscription = null;
      if (!mounted) return;
      setState(() => _testing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection test failed.')),
      );
    }
  }

  /// Story 5.2 (AC1/AC2/AC3) — flips light↔dark only (never `system`, per
  /// Non-goals). [ThemeModeController.set] applies the change immediately
  /// (the [ValueListenableBuilder] above `MaterialApp` — see `app.dart` —
  /// repaints the whole app the instant the value changes) and persists it
  /// in the background, all behind that one call: a persistence failure
  /// can't undo or block the visual toggle that already happened (AC6/AD-8),
  /// and this widget no longer needs its own separate persist-and-swallow
  /// logic (Review fix — that guarantee now lives once, in the controller).
  void _toggleTheme() {
    final current = widget.themeModeController.value;
    final newMode = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    unawaited(widget.themeModeController.set(newMode));
  }

  /// The theme toggle (AC1) — an icon button matching the existing
  /// `settings-action`-style icon-button convention (rather than introducing
  /// a `Switch`, this app's first). Shows the icon for the theme a tap would
  /// switch *to*. Wrapped in its own [ValueListenableBuilder] (Review fix)
  /// rather than reading `widget.themeModeController.value` as a plain field
  /// access — the icon now reacts to *any* change to the theme (not just a
  /// tap on this exact button), instead of relying on the enclosing screen
  /// happening to rebuild for an unrelated reason.
  Widget _themeToggleButton() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeModeController.listenable,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return IconButton(
          key: const Key('theme-toggle-button'),
          tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
          icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: _toggleTheme,
        );
      },
    );
  }

  Future<void> _clear() async {
    if (_saving || _testing) return;
    setState(() => _saving = true);
    try {
      await widget.keyStore.clear();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.notConfigured;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear the key. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [_themeToggleButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(),
      ),
    );
  }

  /// The malformed-`lore-story.json` warning (Review fix, Story 4.7 code
  /// review Decision 4) — a warning that *something* failed to parse, never
  /// a display of what the resolved config actually is (AC5 forbids that).
  Widget? _configWarning(BuildContext context) {
    if (!_aiConfigMalformed) return null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: const Key('settings-ai-config-warning'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(kBannerCornerRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_outlined, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "lore-story.json could not be read as valid JSON — AI "
                'requests are using the default configuration until it is '
                'fixed.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Test Connection button (Story 4.7, gating widened Story 4.8/AC3) —
  /// shared between the `configured` and `notConfigured` stages so tapping
  /// it always resolves against whatever `KeyStore` currently holds
  /// (possibly no key, the local-server case) rather than an unsaved,
  /// just-typed value.
  Widget _testConnectionButton() {
    return OutlinedButton(
      key: const Key('settings-test-connection-button'),
      onPressed: (_testing || _saving) ? null : _testConnection,
      child: _testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Test connection'),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());

      case _Stage.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't access secure storage on this device."),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('settings-retry-button'),
                onPressed: _retryLoad,
                child: const Text('Retry'),
              ),
            ],
          ),
        );

      case _Stage.configured:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?_configWarning(context),
            const Text('AI provider API key'),
            const SizedBox(height: 8),
            const Text('API key configured', key: Key('settings-configured-label')),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  key: const Key('settings-replace-button'),
                  onPressed: (_saving || _testing) ? null : _replace,
                  child: const Text('Replace'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('settings-clear-button'),
                  onPressed: (_saving || _testing) ? null : _clear,
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 12),
                _testConnectionButton(),
              ],
            ),
          ],
        );

      case _Stage.notConfigured:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?_configWarning(context),
            const Text('AI provider API key'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('settings-key-field'),
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'API key',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  key: const Key('settings-save-button'),
                  onPressed: (_saving || _testing) ? null : _save,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 12),
                // Story 4.8/AC3: reachable here too, not only once a key is
                // saved — a local OpenAI-compatible server (e.g. LM Studio)
                // typically needs no key at all, so there must be a way to
                // test one before ever saving anything.
                _testConnectionButton(),
              ],
            ),
          ],
        );
    }
  }
}
