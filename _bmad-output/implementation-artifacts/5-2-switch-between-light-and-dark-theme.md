---
baseline_commit: f170580
---

# Story 5.2: Switch between light and dark theme

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to switch the app between a light and a dark theme,
so that I can read and write comfortably in low-light conditions without the app forcing a bright screen on me.

## Context

**The app has run light-only since Epic 1.** `apps/mobile/lib/app/app.dart:36-38` hardcodes `ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true)` directly inline in the `MaterialApp` widget — no `darkTheme`, no `themeMode`, no `brightness` set at all. Flutter defaults to `Brightness.light` when `brightness` is omitted, so today the app is always light regardless of device settings.

**Good news: the color layer is already theme-friendly for free.** A repo-wide search confirms **zero** raw `Color(0x...)` literals anywhere in `lib/` — every widget already reads colors via `Theme.of(context).colorScheme`/`textTheme` rather than hardcoding them. This means once a dark `ThemeData` exists and is wired up, the overwhelming majority of the app will render correctly in dark mode with no per-widget changes (AC5).

**What isn't free: a handful of inline style/decoration choices that diverge from plain Material defaults, duplicated across files instead of centralized.** Two concrete families exist today, both confirmed by direct grep:

- A `'monospace'` `TextStyle` for anything showing raw markdown/code, hand-duplicated in **four** places: `apps/mobile/lib/app/editor_toolbar.dart:617`, `apps/mobile/lib/app/file_editor.dart:476`, and **twice** in `apps/mobile/lib/app/markdown_preview.dart` (lines 262 and 406 — the latter also layers `backgroundColor: scheme.surfaceContainerHighest` on top via `.copyWith(...)`).
- A recurring rounded-corner decoration on badges/banners, using **two different radius values** at five call sites: `BorderRadius.circular(6)` at `apps/mobile/lib/app/home_page.dart:508` and `:516`, `apps/mobile/lib/app/markdown_preview.dart:257`, and `apps/mobile/lib/app/settings_page.dart:287`; `BorderRadius.circular(4)` at `apps/mobile/lib/app/conflicts_page.dart:111`. **This story does not unify these two values** — it only extracts each as-is into a named constant (see Task 5) so a future visual change is made in one place, not five. Silently changing one site's radius to match the others would be an uncalled-for visual change outside this story's scope.

**No app-wide reactive state exists yet — this is genuinely new territory for this codebase.** A grep for `ChangeNotifier`/`ValueNotifier`/`InheritedWidget`/`Provider` across `lib/` returns zero matches, and no state-management package (`provider`, `riverpod`, etc.) is a dependency (`apps/mobile/pubspec.yaml:30-41`). Every screen today uses plain `StatefulWidget`/`setState`, with collaborators threaded down via constructor injection from `main.dart`'s composition root (`rootStore`, `permission`, `storageFactory`, `keyStore`, `aiClient` — see `apps/mobile/lib/main.dart:19-38` and `apps/mobile/lib/app/app.dart:13-32`). Flipping a theme toggle has to repaint the whole `MaterialApp`, which sits *above* every screen that could host the toggle (`SettingsPage`, `HomePage`) — so this story is the first to need a live signal that crosses the widget tree, not just a one-way constructor parameter.

**The existing non-secret preference-store precedent is exactly the shape to reuse.** `apps/mobile/lib/storage/repo_root_store.dart` persists the chosen repo root via `shared_preferences` (already a dependency, `pubspec.yaml:38`) with a tiny `read()`/`write()`/`clear()` API and a `static const String _key`. Its own doc comment states the rule this story's persisted theme choice falls under too: *"non-secret, so `shared_preferences` is used; `flutter_secure_storage` is reserved for the AI key."* `apps/mobile/test/storage/repo_root_store_test.dart` is the exact test-pattern precedent (`SharedPreferences.setMockInitialValues({})`, fresh-instance-per-read to simulate a relaunch).

## Acceptance Criteria

1. **(Toggle available)** Given the Settings screen or `HomePage`'s `AppBar.actions` (where the existing `settings-action` button lives), when I look for a way to switch themes, then a discoverable control (an icon toggle or a switch) lets me pick light or dark.
2. **(Live effect, app-wide)** Given I flip the toggle, when the change applies, then the entire app — not just the current screen — repaints in the chosen theme immediately, with no restart required.
3. **(Persisted across launches)** Given I've chosen a theme, when I relaunch the app, then it reopens in that same theme — persisted via the same `shared_preferences` mechanism `RepoRootStore` already uses, following the same small `read`/`write`/(`clear`) store-class shape, living alongside it in `lib/storage/`.
4. **(Centralized theme-definition file)** Given the app's theme, typography, and any decoration choices that differ from plain Material defaults, when this story ships, then they live in one dedicated file (`lib/app/theme.dart`) — a light and a dark `ThemeData`, the shared `'monospace'` code/editor `TextStyle` (today duplicated across four call sites), and the two existing corner-radius constants (today duplicated across five call sites) are defined once there and referenced from every call site — not reimplemented inline per-widget as they are today.
5. **(No regression to existing color usage)** Given every existing widget already reads colors via `Theme.of(context).colorScheme`/`textTheme` rather than hardcoded color literals, when dark mode is added, then no widget needs a rewrite to look correct in dark mode — this story does not have to touch every screen, only the theme definitions themselves plus the specific inline duplications named in AC4.
6. **(Never crashes, never blocks)** Given a missing or corrupted stored theme preference, when the app launches, then it falls back to light and never throws — mirroring `RepoRootStore`'s own "absent means unset, not an error" contract. *(AD-8)*

**Non-goals** (explicitly out of scope):
- No "follow system theme" mode. The user's own request is a binary light/dark switch ("switch the theme from light to dark") — this story implements exactly that, not a three-way light/dark/system picker. `ThemeMode` is used only as the vehicle (`ThemeMode.light`/`ThemeMode.dark`); `ThemeMode.system` is never set.
- No visual unification of the two existing corner-radius values (4 vs. 6) called out in Context/Task 5 — each is extracted as its own named constant preserving its current value, not merged into one.
- No new custom color palette beyond what Material 3's `ColorScheme.fromSeed` derives from the existing `Colors.indigo` seed for each brightness — this story is not a rebrand; the visual identity (indigo-derived tones) stays the same, only brightness changes.
- No settings-screen redesign — if the toggle goes into `SettingsPage`, it must not restructure the existing `_Stage`-switch body (Task 3 explains the recommended low-risk placement).
- No changes to `convention_styles.dart` (the wikilink/placeholder/error highlighting palette shared by the editor and preview) — that file already centralizes its own concern and is a different kind of styling (content-convention highlighting, not app chrome/typography); out of scope here.

## Tasks / Subtasks

- [ ] **Task 1: Create the dedicated theme-definition file `lib/app/theme.dart`** (AC: 4)
  - [ ] 1.1 Define `ThemeData lightTheme` and `ThemeData darkTheme` (top-level `final`/getters, or a single `ThemeData buildTheme(Brightness brightness)` — dev's call), both built from `ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light)` / `.dark` respectively, `useMaterial3: true` — preserving today's exact seed color so the visual identity is unchanged, only brightness differs.
  - [ ] 1.2 Define a top-level constant for the shared monospace style, e.g. `const TextStyle kMonospaceTextStyle = TextStyle(fontFamily: 'monospace');` — the base style every call site currently duplicates.
  - [ ] 1.3 Define two named corner-radius constants preserving today's two distinct existing values as-is (do not unify — see Non-goals), e.g. `const double kBadgeCornerRadius = 4;` (matches `conflicts_page.dart:111`'s existing value) and `const double kBannerCornerRadius = 6;` (matches the other four sites' existing value) — name them for what they're used for, not arbitrarily.
  - [ ] 1.4 Doc-comment on the file explaining its role per AD-12: this is the one place app-level theme/typography/decoration choices that diverge from Material default are defined; every other file references these constants rather than redefining them.

- [ ] **Task 2: Persist the theme choice — `lib/storage/theme_mode_store.dart`** (AC: 3, 6)
  - [ ] 2.1 New `class ThemeModeStore` mirroring `RepoRootStore`'s exact shape (`static const String _key`, `Future<ThemeMode?> read()`, `Future<void> write(ThemeMode mode)`, optionally `Future<void> clear()`) — store the mode as a string (`'light'`/`'dark'`) via `shared_preferences`, mapping to/from `ThemeMode` at the store boundary so nothing outside this file needs to know the storage representation.
  - [ ] 2.2 `read()` returns `null` when nothing is stored yet, or when the stored value is unrecognized/corrupted (AC6 — never throw; an unparseable stored string degrades to "unset," exactly mirroring `AiServerConfig`'s and `ProjectConfig`'s own "malformed becomes default, not an error" precedent elsewhere in this codebase).
  - [ ] 2.3 Add `export 'theme_mode_store.dart';` to `lib/storage/storage.dart`'s barrel (AD-12), alongside the existing `repo_root_store.dart` export.
  - [ ] 2.4 New `test/storage/theme_mode_store_test.dart` mirroring `test/storage/repo_root_store_test.dart`'s exact test shape (`SharedPreferences.setMockInitialValues({})`, read-before-any-write returns null, write-then-fresh-instance-read round-trips, plus one new case: a corrupted/unrecognized stored value read back as null rather than throwing).

- [ ] **Task 3: Wire a live, app-wide theme signal** (AC: 1, 2)
  - [ ] 3.1 `LoreStoryApp` (`app/app.dart`) **stays a `StatelessWidget`** — it only needs a new constructor field, `required ValueListenable<ThemeMode> themeMode`, **injected from `main.dart`, not constructed inside `LoreStoryApp`** (mirrors how every other collaborator — `rootStore`, `keyStore`, `aiClient` — is already injected per the composition-root pattern; `LoreStoryApp` "constructs none of them itself," `app.dart:11-12`'s own doc comment). `ValueListenableBuilder` (Task 3.3) supplies the actual rebuild-on-change mechanism internally — `LoreStoryApp` itself needs no mutable state or lifecycle.
  - [ ] 3.2 In `main.dart`, instantiate `final themeModeStore = ThemeModeStore();` and `final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);` — start at the AC6 default *before* the stored value is known (mirrors the existing pattern where `main()` stays synchronous and never blocks `runApp` on I/O; `HomePage` reads `rootStore` asynchronously post-launch, not `main()` itself). Immediately after `runApp(...)`, kick off `themeModeStore.read().then((stored) { if (stored != null) themeModeNotifier.value = stored; });` — fire-and-forget, wrapped so a read failure is swallowed (AD-8) and simply leaves the AC6 default in place.
  - [ ] 3.3 In `LoreStoryApp.build`, wrap `MaterialApp` in a `ValueListenableBuilder<ThemeMode>` (or `AnimatedBuilder`) listening to the injected notifier, passing `theme: lightTheme, darkTheme: darkTheme, themeMode: mode` (the three new params from Task 1's `theme.dart`) into `MaterialApp` — replacing the single hardcoded `theme:` line at `app.dart:38`.
  - [ ] 3.4 Thread `themeModeNotifier` (as a `ValueListenable<ThemeMode>` for reading current value, plus a way to also *write* — either pass the full `ValueNotifier` down to whichever screen hosts the toggle, or pass both the read-only listenable and a `void Function(ThemeMode) onThemeModeChanged` callback, dev's call) down to whichever screen hosts the toggle (Task 4), alongside `themeModeStore` for persisting the change.

- [ ] **Task 4: Add the toggle control** (AC: 1, 2, 3)
  - [ ] 4.1 **Recommended placement: `SettingsPage`'s own `AppBar.actions`** (`settings_page.dart` — its `AppBar(title: const Text('Settings'))` currently has no `actions` at all). This is the lowest-risk option: it satisfies "on the Settings screen" literally, requires zero changes to the existing `_Stage`-switch body (`_buildBody()`, `settings_page.dart:375+`), and avoids inventing a new `SwitchListTile`/`ListTile` placement precedent inside a screen whose body today is a plain `Column` of `TextField`/`FilledButton`/`OutlinedButton`, not a settings-list layout. The alternative the story's own source AC also allows — `HomePage`'s `AppBar.actions`, next to the existing `settings-action` `IconButton` (`home_page.dart:352-357`) — is equally acceptable; note if choosing that instead: no `home_page_test.dart` exists yet for precedent, so `SettingsPage`'s placement is easier to cover with a widget test using the existing `_pump` test harness (`test/app/settings_page_test.dart:16-30`).
  - [ ] 4.2 An `IconButton` toggling its icon between `Icons.dark_mode_outlined` (shown when currently light, i.e. tap to go dark) and `Icons.light_mode_outlined` (shown when currently dark) — matches the existing icon-button convention already used for `settings-action` (`Icons.settings_outlined`), rather than introducing a `Switch` widget as this app's first. Key: `Key('theme-toggle-button')`.
  - [ ] 4.3 On tap: flip the injected `ThemeMode` (light↔dark only — never `system`, per Non-goals) via the Task 3.4 mechanism, and persist via `themeModeStore.write(newMode)` — wrap the write in `try`/`catch` and ignore any failure (AD-8): a persistence failure must never block the immediate visual toggle (AC2 still applies even if AC3's persistence silently fails this one time).

- [ ] **Task 5: Consolidate the four `'monospace'` `TextStyle` sites** (AC: 4)
  - [ ] 5.1 `apps/mobile/lib/app/editor_toolbar.dart:617` — replace `const TextStyle(fontFamily: 'monospace')` with `kMonospaceTextStyle`.
  - [ ] 5.2 `apps/mobile/lib/app/file_editor.dart:476` — same replacement.
  - [ ] 5.3 `apps/mobile/lib/app/markdown_preview.dart:262` — `.copyWith(fontFamily: 'monospace')` becomes `.copyWith(fontFamily: kMonospaceTextStyle.fontFamily)` (this site merges the monospace family onto an existing inherited style via `copyWith`, not a standalone `TextStyle` — preserve that merge, don't replace the whole style).
  - [ ] 5.4 `apps/mobile/lib/app/markdown_preview.dart:406` — same `copyWith` treatment; this site also sets `backgroundColor: scheme.surfaceContainerHighest` alongside — preserve that untouched, only the `fontFamily: 'monospace'` line changes.

- [ ] **Task 6: Consolidate the corner-radius decoration sites** (AC: 4)
  - [ ] 6.1 `apps/mobile/lib/app/conflicts_page.dart:111` — `BorderRadius.circular(4)` → `BorderRadius.circular(kBadgeCornerRadius)`.
  - [ ] 6.2 `apps/mobile/lib/app/home_page.dart:508` and `:516` — `BorderRadius.circular(6)` → `BorderRadius.circular(kBannerCornerRadius)` at both sites.
  - [ ] 6.3 `apps/mobile/lib/app/markdown_preview.dart:257` — same replacement.
  - [ ] 6.4 `apps/mobile/lib/app/settings_page.dart:287` — same replacement.

- [ ] **Task 7: Regression + new-behavior tests** (AC: 1, 2, 3, 4, 5, 6)
  - [ ] 7.1 `test/storage/theme_mode_store_test.dart` — see Task 2.4.
  - [ ] 7.2 Widget test(s) in `test/app/settings_page_test.dart` (or a new `test/app/theme_toggle_test.dart` if the toggle's own test setup diverges meaningfully from `SettingsPage`'s existing `_pump` harness): tapping the toggle flips the app's effective `Brightness`/`ThemeMode` (assert via `Theme.of(context).brightness` on the pumped tree, or via the injected notifier's value) and persists it (assert `ThemeModeStore().read()` reflects the new value after the tap, using the same `SharedPreferences.setMockInitialValues({})` pattern).
  - [ ] 7.3 A launch test: given `SharedPreferences.setMockInitialValues({'<theme_key>': 'dark'})` pre-seeded before pumping `LoreStoryApp`, the app starts in dark mode (AC3) — and given no seeded value at all, it starts in light (AC6 default).
  - [ ] 7.4 Full regression: run the entire existing `flutter test` suite — Task 5/6's replacements must not change any existing widget test's rendered output (radius/font-family values are unchanged, only their *source* moves), and no other screen's tests should need updating.
  - [ ] 7.5 `flutter analyze` clean.

## Dev Notes

- **Architecture fit:** this story follows AD-9 (I/O isolated to adapter files — `ThemeModeStore` is the only file touching `shared_preferences` for this concern) and AD-12 (composition root owns construction; `LoreStoryApp`/`SettingsPage`/`HomePage` receive collaborators by injection, never construct them). `lib/app/theme.dart` is a pure-Dart-plus-Flutter-material styling module, not a new slice — it lives beside `app.dart`/`home_page.dart`/`settings_page.dart` in the existing `app/` UI layer.
- **This is the first `ValueNotifier`/reactive-state usage in the codebase.** Every other piece of shared state today flows one-way via constructor injection and `setState` within a single screen's own `StatefulWidget`. Task 3's `ValueNotifier<ThemeMode>` is a deliberate, minimal exception to reach the one genuinely new requirement (a change made in a child screen must repaint `MaterialApp` itself) — it introduces no new package dependency (`ValueNotifier`/`ValueListenableBuilder` are core Flutter). Do not reach for `provider`/`riverpod`/`flutter_bloc` — none are dependencies today and none are needed for a single boolean-shaped piece of state.
- **Async loading must not block `runApp`.** `main()` is synchronous today (`void main()`, not `async`) and no existing collaborator's construction awaits I/O before `runApp` — `RepoRootStore`'s own persisted value is read later, inside `HomePage`'s `initState`-driven scan, not in `main()`. Follow the same shape for the theme preference: start at the AC6 default, kick off the async read after `runApp`, and update the notifier when it resolves (a one-frame flash of the default theme before the stored one applies is an acceptable, pre-existing-pattern tradeoff — do not introduce a loading spinner or splash screen for this).
- **The existing `errorContainer`-tinted flat-`Container` banner pattern** (`file_editor.dart:429-441`, `:442-454`; `conflicts_page.dart:64-73`) is a *different*, looser pattern from the `BoxDecoration`-with-`borderRadius` sites Task 6 targets — those banners use a flat `color:` on `Container` with no `BoxDecoration`/`borderRadius` at all. They are correctly out of scope for Task 6 (nothing to consolidate there — no radius value is being duplicated) and are not mentioned in the ACs; do not touch them.
- **Testing standards:** this project's existing widget tests key every interactive control (`Key('settings-*')`, `Key('settings-action')`) and use `SharedPreferences.setMockInitialValues({})` for any `shared_preferences`-backed test. Follow both conventions exactly — see `test/storage/repo_root_store_test.dart` and `test/app/settings_page_test.dart`'s `_pump` helper as the direct templates for Task 2.4/7.2/7.3.

### Project Structure Notes

- New files: `lib/app/theme.dart`, `lib/storage/theme_mode_store.dart`, `test/storage/theme_mode_store_test.dart`.
- Modified files: `lib/app/app.dart` (StatelessWidget → holds/consumes the notifier), `lib/main.dart` (composition root: instantiate store + notifier, thread through), `lib/storage/storage.dart` (barrel export), `lib/app/settings_page.dart` (or `lib/app/home_page.dart`, per Task 4.1's placement decision), `lib/app/editor_toolbar.dart`, `lib/app/file_editor.dart`, `lib/app/markdown_preview.dart`, `lib/app/conflicts_page.dart` (Task 5/6 call-site replacements).
- No conflicts detected with the unified project structure — `theme.dart` and `theme_mode_store.dart` slot naturally beside their existing `app/`/`storage/` siblings, matching every precedent cited above.

### References

- [Source: apps/mobile/lib/app/app.dart#L36-38] — current hardcoded `ThemeData`.
- [Source: apps/mobile/lib/main.dart#L19-38] — composition-root injection pattern to extend.
- [Source: apps/mobile/lib/storage/repo_root_store.dart] — the exact store-class shape to mirror.
- [Source: apps/mobile/test/storage/repo_root_store_test.dart] — the exact test shape to mirror.
- [Source: apps/mobile/lib/app/home_page.dart#L346-359] — the app bar `settings-action` button, the alternative toggle placement.
- [Source: apps/mobile/lib/app/settings_page.dart#L1-30] — the recommended toggle placement's existing structure.
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-8, AD-9, AD-12] — the architecture decisions this story must comply with.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.2] — the epic-level acceptance criteria this story file expands on.

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
