import 'package:flutter/material.dart';

import '../ai/ai.dart';

/// The states this screen can be in. [error] covers any secure-storage
/// failure (read/write/delete) — AD-8: never crash, always a visible state.
enum _Stage { loading, notConfigured, configured, error }

/// Manage the AI provider API key (Story 4.1, FR20/NFR5): one field, Save,
/// Clear. Deliberately minimal — Epic 4 targets a single provider
/// (Anthropic), so there is no provider picker or multi-page settings
/// surface here.
///
/// The key is never re-displayed once saved (NFR5): this screen only ever
/// asks [KeyStore.isConfigured] (never [KeyStore.read]) to decide which UI to
/// show, so the real secret never becomes a widget-local variable it doesn't
/// need to be.
class SettingsPage extends StatefulWidget {
  final KeyStore keyStore;

  const SettingsPage({super.key, required this.keyStore});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Stage _stage = _Stage.loading;
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final configured = await widget.keyStore.isConfigured();
      if (!mounted) return;
      setState(() => _stage = configured ? _Stage.configured : _Stage.notConfigured);
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
    if (_saving) return;
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

  Future<void> _clear() async {
    if (_saving) return;
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
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(),
      ),
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
            const Text('AI provider API key'),
            const SizedBox(height: 8),
            const Text('API key configured', key: Key('settings-configured-label')),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  key: const Key('settings-replace-button'),
                  onPressed: _saving ? null : _replace,
                  child: const Text('Replace'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('settings-clear-button'),
                  onPressed: _saving ? null : _clear,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        );

      case _Stage.notConfigured:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            FilledButton(
              key: const Key('settings-save-button'),
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        );
    }
  }
}
