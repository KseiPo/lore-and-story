---
baseline_commit: 2b6e8e6873ce1af7d6db08d25f605cf014a19212
---

# Story 5.8: Keep the editor clear of the Android navigation bar

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the read/edit screen to stop above Android's on-screen navigation buttons,
so that I can read the last lines of a file and reach every button of the editing toolbar.

## Context

**Bug report (KseiPo, 2026-10-01):** on the read/edit screen the on-screen
navigation buttons cover the bottom of the screen, so the last two lines of text
can't be read. KseiPo's phone uses 3-button navigation (a 48dp bar); gesture
navigation has the same bug with a thinner bar.

**Root cause: Android edge-to-edge.** `android/app/build.gradle.kts:29` sets
`targetSdk = flutter.targetSdkVersion`, which is **36** in the pinned Flutter
3.44.7 (`flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:34`).
- Android 15 forces edge-to-edge on apps that target API 35+.
- Android 16 disables the `windowOptOutEdgeToEdgeEnforcement` opt-out for apps
  that target 36.

So the app's window always extends under the navigation bar. Flutter reports the
bar's height as `MediaQuery.padding.bottom`, and each layout must consume it
itself.

`Scaffold` does not consume it for its body. In `material/scaffold.dart` it
removes bottom padding from the body's `MediaQuery` only when there is a
`bottomNavigationBar` or `persistentFooterButtons`. No editor host has either,
so the body still carries `padding.bottom` and the body's own layout must honor
it.

**`FileEditor` ignores it in both of its modes:**
- **Preview (the default mode, "reading"):** `MarkdownPreview` returns
  `SingleChildScrollView(padding: const EdgeInsets.all(16))`
  (`apps/mobile/lib/app/markdown_preview.dart:122`). `SingleChildScrollView`
  never adds the system inset, so the scroll end sits at the physical bottom of
  the screen. Even at maximum scroll, the last ~2 lines stay under the bar.
- **Raw editor ("editing"):** the ready-state `Column`
  (`apps/mobile/lib/app/file_editor.dart:427`) ends with `EditorToolbar`
  (`file_editor.dart:510`, a 48-high `Material`). While the keyboard is hidden,
  the toolbar sits under the bar.

**Why `FileEditor` (and, found in review round 2, `HomePage`'s bottom buttons) are broken: a survey of every screen.**

| Screen | Bottom layout | Status |
|---|---|---|
| `EditorPage` (`editor_page.dart:244`), `PairedEditorPage` (`paired_editor_page.dart:556`, one `FileEditor` per tab), `UndeterminedLanguagePage` (`undetermined_language_page.dart:406`) | `body: FileEditor` | **broken — this story** |
| `CategoryEntitiesPage`, `ConflictsPage`, `EntityDetailPage` | `ListView` with no explicit `padding` | fine in portrait: `BoxScrollView` adds `MediaQuery.padding` along its scroll axis itself (left/right in landscape is a deferred item) |
| `HomePage` (`home_page.dart:368`) | `Padding(24, Center(...))` around a `Column` that ends with the "Refresh" and "Change folder" buttons; the padding-less `ListView` above them sits mid-`Column` and protects nothing below it | **broken — fixed in this story (Task 6).** Round 1 of this survey wrongly filed it under the `ListView` screens; review round 2 caught it: "Change folder" spanned y 728–776 against a bar starting at 752 |
| `EntityDetailPage`'s embedded `MarkdownPreview` (`entity_detail_page.dart:288`) | inside that `ListView` (`:272`) | fine: the `ListView` consumes the padding and removes it from its children's `MediaQuery` |
| `RootPickerPage` | `bottomNavigationBar: SafeArea(...)` (`root_picker_page.dart:146`) | fine |
| Lint / Grammar panels, AI context preview | bottom sheets wrapped in `SafeArea` (`lint_panel.dart:23`, `grammar_panel.dart:23`, `context_preview.dart:64`) | fine |
| `SettingsPage` | `Padding(24)` around a short, top-anchored `Column` (`settings_page.dart:374`, `_buildBody`) | fine: it never reaches the bottom on a phone. The planning chat floated it as optional; reading the code showed it isn't affected. Out of scope. |

**All three editor hosts render `FileEditor` as their whole body, so one fix
inside `FileEditor` covers all of them.** `HomePage` is a separate, second fix
(Task 6): the same `SafeArea(top: false)`, around its own body.

**Decided approach (KseiPo, 2026-10-01 — "option A"):** wrap the ready-state
`Column` in `SafeArea(top: false)`.

Rejected alternatives (don't re-litigate):
- **B, "true" edge-to-edge.** Add `MediaQuery.paddingOf(context).bottom` to
  `MarkdownPreview`'s scroll padding and put a `SafeArea` around the toolbar
  only, so text scrolls *behind* the bar but can be scrolled clear. That means
  two edit points instead of one. And with 3-button navigation, text passing
  under the translucent buttons is worse to read.
- **The `windowOptOutEdgeToEdgeEnforcement` flag.** It does nothing at
  targetSdk 36.
- **A global `SafeArea` in `MaterialApp.builder`.** It changes every screen
  although only one is broken, and it takes away the scroll-under behavior the
  `ListView` screens already handle correctly.

**Keyboard behavior: why the fix doesn't open a gap above the keyboard.**
- Per the `MediaQueryData` docs (`widgets/media_query.dart`, "Insets and
  Padding"), `padding = max(0, viewPadding - viewInsets)`. With the keyboard up,
  `padding.bottom` is 0, so `SafeArea` adds nothing and the toolbar stays flush
  on top of the keyboard (FR8, Story 2.5).
- `Scaffold` removes `viewInsets` from the body: `resizeToAvoidBottomInset`
  defaults to true, and no `Scaffold` in `lib/` overrides it.
- `SafeArea.maintainBottomViewPadding` stays at its default `false`, but it makes no
  difference here (review round 2, probed): the `Scaffold` has already removed the
  keyboard inset from the body's `viewPadding`, so `true` gives the same layout. A
  gap above the keyboard appears only where the `Scaffold` does not consume that
  inset (`resizeToAvoidBottomInset: false`, or a `SafeArea` above the `Scaffold`).

## Acceptance Criteria

1. **(Reading)** **Given** a file open in the preview (the editor's default mode)
   on an Android device with an on-screen navigation bar, **When** I scroll to the
   end, **Then** the last line rests fully above the bar. This holds on all three
   `FileEditor` hosts (single-file editor, both tabs of a RU/EN pair, the
   undetermined-language page).
2. **(Editing, keyboard hidden)** **Given** the raw editor with the keyboard
   hidden, **When** I look at the bottom of the screen, **Then** the helper
   toolbar (and the `[[` suggestion row when shown) sits fully above the
   navigation bar, every toolbar button is tappable, and the text field ends
   above the toolbar.
3. **(Editing, keyboard shown)** **Given** the keyboard is open, **When** the
   layout settles, **Then** the toolbar sits directly on top of the keyboard with
   no extra gap, exactly as before this story (FR8).
4. **(Landscape)** **Given** landscape orientation with the navigation bar on a
   side edge, **When** the editor or preview is shown, **Then** no content runs
   under that bar.
5. **(No regression)** **Given** this change, **When** the existing behaviors
   run, **Then** the following are unchanged:
   - load / save / dirty / pop / save-on-background;
   - the lossy-UTF-8 guard and the conflict-copy banner;
   - the preview toggle, `jumpToLine`, `setText`, wikilink tap and autocomplete;
   - every other screen (the Home screen's bottom buttons aside, AC6).

   The existing test suite passes without edits.
6. **(Home screen)** **Given** the Home screen in its ready state on a device with
   an on-screen navigation bar (portrait), **When** I look at the bottom of the
   screen, **Then** the "Refresh" and "Change folder" buttons sit fully above the
   bar. With no inset the layout is exactly as before.

**Non-goals** (explicitly out of scope):
- No edge-to-edge polish. Text does not scroll behind the bar, and the strip under
  the bar shows the scaffold's surface color, not the toolbar's.
- No change to any other screen (see the survey table) — except `HomePage`'s body
  wrapper (Task 6, added after review round 2) — and none to `MarkdownPreview`, to
  `EditorToolbar`, or to any host page.
- No opt-out flag, no `targetSdk`/`compileSdk` change, no global `SafeArea`, and
  no `SystemChrome` / system-bar color changes.
- No new permanent test. This is layout, not business logic (project-context.md
  → "Testing emphasis"). A throwaway probe verifies it instead (Task 2).

## Tasks / Subtasks

- [x] **Task 1: Consume the system inset in `FileEditor`'s ready state** (AC: 1, 2, 3, 4, 5)
  - [x] 1.1 `apps/mobile/lib/app/file_editor.dart:427`: change `return Column(` to
    `return SafeArea(top: false, child: Column(...))`. The `Column`'s children are
    unchanged.
    - `top: false` because every host's `AppBar` already consumes the top inset
      (`Scaffold` strips top padding from the body when `appBar != null`).
    - `left`/`right`/`bottom` stay at their default `true` (AC4).
  - [x] 1.2 Keep `maintainBottomViewPadding` at its default `false` (AC3), and don't
    set `minimum`.
  - [x] 1.3 Add a short comment above the `SafeArea`, in this file's comment style,
    saying:
    - the app is edge-to-edge (targetSdk 36, enforced from Android 15), so the
      body extends under the navigation bar;
    - `Scaffold` leaves the bottom inset to its body;
    - this is the one spot for all three hosts;
    - the keyboard collapses `padding.bottom` to 0, so no gap opens above it.
  - [x] 1.4 Leave the `loading` / `error` cases untouched: centered content,
    nothing bottom-anchored.
  - [x] 1.5 Do **not** edit `MarkdownPreview`'s `SingleChildScrollView` padding.
    It is also embedded in `EntityDetailPage`'s `ListView`, which already
    consumes the inset, and option A deliberately has a single edit point.

- [x] **Task 2: Verify with a throwaway probe test — do NOT commit it** (AC: 1, 2, 3, 4)
  - [x] 2.1 Create `apps/mobile/test/app/zz_inset_probe_test.dart`. Copy
    `pumpEditor` from `test/app/editor_page_test.dart:21` (it's a top-level helper
    in a test file; copy it rather than import it), plus `FakeRepoStorage` from
    `test/fakes.dart` and `enterEditMode` from `test/app/editor_test_helpers.dart`.
  - [x] 2.2 View setup, with `addTearDown(tester.view.reset)`:
    - `tester.view.physicalSize = const Size(1080, 2400)` and
      `devicePixelRatio = 3.0`, giving 360×800 logical;
    - `tester.view.viewPadding = const FakeViewPadding(bottom: 144)` and
      `tester.view.padding = const FakeViewPadding(bottom: 144)`, a 48-logical bar.

    **Gotcha:** in `flutter_test` the faked `padding` and `viewPadding` are
    *independent* (`flutter_test/lib/src/window.dart`). The test does not derive
    one from the other the way the engine does, so set both explicitly.
  - [x] 2.3 **Preview (AC1):**
    - seed a ~200-line file whose last line contains a unique `LAST-LINE-MARKER`;
    - pump it with `edit: false`;
    - fling or drag the `SingleChildScrollView` far up, then `pumpAndSettle`;
    - assert
      `tester.getRect(find.textContaining('LAST-LINE-MARKER', findRichText: true)).bottom <= 752`.

    Run it **without** the fix first and confirm it fails: that proves the probe
    reproduces the bug. Then confirm it passes with the fix.
  - [x] 2.4 **Edit mode, keyboard hidden (AC2):**
    `tester.getRect(find.byType(EditorToolbar)).bottom` is `<= 752` with the fix
    (expect exactly 752) and `800` without it.
  - [x] 2.5 **Keyboard (AC3):** emulate the engine:
    - `tester.view.viewInsets = const FakeViewPadding(bottom: 900)` (300 logical);
    - keep `viewPadding` at 144;
    - set `padding` to `FakeViewPadding.zero` (= max(0, viewPadding − viewInsets)).

    Assert the toolbar's bottom is exactly `500` (no gap).
  - [x] 2.6 *(Optional, AC4)* Landscape: set `physicalSize` to 2400×1080 and
    `viewPadding`/`padding` to `right: 144`, then assert the toolbar's
    `right <= 800 - 48`.
  - [x] 2.7 Record the before/after numbers in **Debug Log References**, then
    **delete the probe file**. `git status` must not show it.

- [x] **Task 3: Write the rule down so the next screen doesn't repeat the bug** (AC: 5)
  - [x] 3.1 In `_bmad-output/project-context.md` → "Developer workflow", append
    this bullet (exact text — **superseded by the review patches, see Review Findings;
    the committed bullet in project-context.md differs, do not restore this wording**):
    `- **Android edge-to-edge (targetSdk 36):** every screen draws under the system navigation bar, which Flutter reports as \`MediaQuery.padding.bottom\`; \`Scaffold\` leaves it to the body unless it has a \`bottomNavigationBar\`. Bottom-anchored content must consume it — \`SafeArea(top: false)\` around the layout, or a \`ListView\` without an explicit \`padding\` (it adds the inset itself). A scrollable given an explicit \`padding\` (e.g. \`SingleChildScrollView(padding: …)\`) does not — that was the Story 5.8 bug. Keep \`SafeArea.maintainBottomViewPadding\` false above the keyboard toolbar, or a gap opens above the keyboard.`

- [x] **Task 4: Gates** (AC: 5)
  - [x] 4.1 `flutter analyze` → no issues. Use the PATH prefix: Flutter lives at
    `C:\programs\flutter\bin` and is not on PATH; run it through PowerShell with
    `$env:Path = "C:\programs\flutter\bin;$env:Path"`.
  - [x] 4.2 `flutter test` → all green. The existing suite runs at zero view
    padding, so `SafeArea` is a no-op there and nothing should change.
  - [x] 4.3 `npm test` from the repo root → 4/4.
  - [x] 4.4 Contract git-clean: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` → empty.

- [ ] **Task 5: Device check — KseiPo, after installing the build** (AC: 1–4)
  - [ ] 5.1 Long file, preview, scroll to the end → the last line is above the buttons.
  - [ ] 5.2 Edit mode, keyboard hidden → the toolbar is above the buttons and every button responds.
  - [ ] 5.3 Tap into the text → the toolbar sits flush on the keyboard, no gap.
  - [ ] 5.4 RU/EN pair, both tabs; a file on the undetermined-language page.
  - [ ] 5.5 Rotate to landscape → nothing is under the side bar.
  - [ ] 5.6 Home screen (portrait) → "Change folder" is fully above the buttons.

- [x] **Task 6: Keep the Home screen's bottom buttons clear of the bar** (AC: 6; added after review round 2, option A chosen by KseiPo 2026-10-02)
  - [x] 6.1 `apps/mobile/lib/app/home_page.dart:368`: wrap the body `Padding` in
    `SafeArea(top: false, child: ...)`, with a short comment. `top: false` because the
    `AppBar` consumes the top inset; the floating action button is positioned by
    `Scaffold` itself and is unaffected.
  - [x] 6.2 Throwaway probe `zz_home_inset_probe_test.dart` (deleted): real `LoreStoryApp`
    in its ready state, 360×800 with a 48 dp bar. Failed before the fix, passes after
    (see Debug Log). The existing suite runs at zero padding, so it stays unchanged.
  - [x] 6.3 Gates re-run: `flutter analyze` clean, `flutter test` 834/834, `npm test` 4/4,
    contract git-clean.
  - [x] 6.4 Correct the survey row, the `epics.md` Context sentence "Every other screen
    already handles the inset", and amend the Non-goal.

### Review Findings

Code review 2026-10-01, cross-model (implemented on Opus 5.5; all three layers on Sonnet 5.5: Blind Hunter, Edge Case Hunter with live Flutter probes, Acceptance Auditor). The Auditor found no AC or constraint violation and re-ran every gate itself (`flutter analyze` clean, `flutter test` 834/834, `npm test` 4/4, contract git-clean). The Edge Case Hunter probed all three hosts across the keyboard sweep (hidden, animating, equal to the bar, fully open) and found no behavior defect.

- [x] [Review][Patch] The edge-to-edge rule in project-context.md misstates the cause. It says a scrollable "given an explicit `padding`" fails to add the inset, which reads as "without `padding` it would". `SingleChildScrollView` never adds the inset, with or without `padding` (`single_child_scroll_view.dart` only wraps in `Padding`). Only `ListView`/`GridView` with a null `padding` do, and only along their scroll axis (`scroll_view.dart` `BoxScrollView.buildSlivers`). [_bmad-output/project-context.md:251] — fixed: the rule now says `SingleChildScrollView` (with or without `padding`) and a plain `Column` never add the inset, and `ListView`/`GridView` with no `padding` add it only along their scroll axis. Task 3.1's quoted text above is left as the original wording.
- [x] [Review][Defer] In landscape with a side navigation bar, the `ListView` screens (home, category entities, conflicts, entity detail, root picker) inset only along their scroll axis, so list tiles and trailing icons can run under the bar's side — deferred, pre-existing. [apps/mobile/lib/app/home_page.dart:561]
- Dismissed (12), each verified:
  - "no automated test pins the inset": a spec Non-goal and the project's testing emphasis (layout is not business logic); the throwaway probe covered it;
  - "AC3 rests on the engine collapsing `padding.bottom`", and "the `maintainBottomViewPadding` sentence restates the default": the Edge Case Hunter swept `viewInsets` 0–300 and the toolbar bottom stayed correct throughout; the engine half is Task 5.3 on the device, and the sentence guards a future change;
  - "one spot covering every host is only asserted", and the loading/error states untouched: `FileEditor` is used only by the three hosts, all probed (toolbar at 752 on each, on both paired tabs); the loading and error states are centered content with nothing bottom-anchored;
  - "`top: false` assumes an AppBar": every host has one, and `Scaffold` strips the top padding from the body when `appBar != null`;
  - "the other screens and bottom sheets were never audited": the survey table in this story's Context audits them (the sheets are wrapped in `SafeArea`);
  - "full-width chrome stops short of the screen edges", and the landscape side strips (Blind Hunter and Edge Case Hunter independently): an accepted trade-off, since the spec Non-goals say "No edge-to-edge polish";
  - "the rule is buried in a Node-oriented list": Task 3.1 prescribes that spot, and the section is the generic "Developer workflow";
  - "the comment is long and cites Story 5.8 and targetSdk": it matches this file's comment style, which cites story numbers throughout;
  - Auditor observations: the probe is not re-runnable (deleted by design); `UndeterminedLanguagePage` was not probed by the dev but the Edge Case Hunter probed it (toolbar at 752); the `epics.md` AC2 is shorter than the spec's (immaterial); `dart format` is not enforced by the project (it also flags the untouched `editor_page.dart`).

#### Review round 2 (2026-10-02)

Re-run after the round-1 patch, same three layers on Sonnet 5.5 (the code in `file_editor.dart` was unchanged; the delta was the reworded project-context rule and the deferral entry). The Auditor again found every AC and Task 1–4 satisfied and reproduced all gates on a clean tree (`flutter analyze` clean, `flutter test` 834/834, `npm test` 4/4, contract git-clean); the Edge Case Hunter re-walked the keyboard sweep, all three hosts, `TabBarView`, landscape and the `bottomNavigationBar`/`persistentFooterButtons` interaction with no defect in the code. Both layers then found problems in the **written claims**, one outside the editor:

- [x] [Review][Decision] The Home screen's bottom buttons sit partly under the navigation bar in portrait with 3-button navigation — the same bug class as this story, on a screen the Context survey marked "fine". `HomePage`'s body is `Padding(24, Center(_buildStage()))` and the ready-state `_ReadyView` `Column` ends with the "Refresh" and "Change folder" buttons, so nothing consumes `padding.bottom`; the padding-less `ListView` above them sits mid-Column and protects nothing below it. Two independent widget-test probes agree (48 dp bar: "Change folder" at y 728–776 against a bar starting at 752, so about half of the button, including its centre, is covered; "Refresh" clears). Gesture navigation (about 24 dp) barely clears it, so this is the 3-button case of the bug report. Pre-existing, but this story's Non-goal "no change to any other screen" was premised on that survey being right. Options: **A)** fix it in this story as a new Task 6: wrap `HomePage`'s body in `SafeArea(top: false)` (the FAB is positioned by `Scaffold` already; the wrap also removes the dead bar-height padding the `ListView` adds at its own end), and amend the Non-goal; **B)** leave it for a separate follow-up story, together with the landscape item already deferred. Either way the survey row "HomePage … fine" and the sentence "Every other screen already handles the inset" in this story's Context and in `epics.md` are wrong and must be corrected. [apps/mobile/lib/app/home_page.dart:368] — **resolved 2026-10-02 (KseiPo): option A**, implemented as Task 6; the survey row, the Non-goal and `epics.md` are corrected.
- [x] [Review][Patch] The `maintainBottomViewPadding` rationale is wrong inside a `Scaffold`. The rule says it must stay false "or a gap opens above the keyboard", and this story's Context and Dev Notes say the same. But `Scaffold` calls `removeViewInsets(removeBottom: true)` on its body (`scaffold.dart:3034`, `resizeToAvoidBottomInset` unset in `lib/`), which reduces `viewPadding.bottom` by the keyboard height (`media_query.dart:978`), so the flag has no effect there; probed at keyboard heights 0/20/40/300, `true` and `false` gave identical toolbar positions. A gap appears only where the Scaffold does not consume the keyboard inset (`resizeToAvoidBottomInset: false`, or a `SafeArea` above the `Scaffold`). The instruction is harmless, the stated reason is false. Reword in all three places. [_bmad-output/project-context.md:258] — fixed: the rule, this Context bullet and the Dev Notes bullet now say the flag has no effect in a `Scaffold` body, and when a gap can appear.
- [x] [Review][Patch] The rule says `Scaffold` leaves the bottom inset to the body "unless it has a `bottomNavigationBar`"; `persistentFooterButtons` has the same effect (`scaffold.dart:3033`, probed). [_bmad-output/project-context.md:251] — fixed: the rule now names `persistentFooterButtons`.
- [x] [Review][Patch] The deferral entry says `FileEditor` "now uses `SafeArea`, which insets all four sides"; it is `SafeArea(top: false)`, so three. It also still says "not reproduced on a device" although a widget test now reproduces it (landscape, 48 dp left bar: the first tile's left edge is at x = 0 while its `MediaQuery` still carries `padding.left` = 48), and it should note that `HomePage` and `SettingsPage` use a fixed 24 dp padding against a roughly 48 dp bar (source only). [_bmad-output/implementation-artifacts/deferred-work.md] — fixed: the entry now says `SafeArea(top: false)`, records the widget-test reproduction, mentions `SettingsPage`, and drops `HomePage` (fixed by Task 6).
- [x] [Review][Patch] Dev Notes → Git intelligence → Stage lists the files to commit but omits `deferred-work.md`, which the File List now includes. [this file, Dev Notes] — fixed: the Stage list now includes `deferred-work.md` and `home_page.dart`.
- [x] [Review][Patch] Task 3.1 still says "exact text" for a bullet that the review has since reworded; add a note that the review patches supersede it, so nobody restores the original wording. [this file, Task 3.1] — fixed: Task 3.1 now carries a "superseded" note.
- [x] [Review][Defer] `project-context.md:25` still says "There is no Dart code in the repo yet; today's work is still the Node POC", which has been false since Epic 1; it makes the Flutter rule read as orphaned. [_bmad-output/project-context.md:25] — deferred, pre-existing
- [x] [Review][Defer] On the Home screen, the floating action button covers the right end of the "Change folder" button (FAB x 288–344, button x 24–336, same top edge), with or without a bar inset; the label is centred so the text stays clear, but a tap on the button's right end hits the FAB. Found while implementing Task 6; the fix keeps this relative geometry. [apps/mobile/lib/app/home_page.dart:368] — deferred, pre-existing
- [x] [Review][Defer] On the Home screen in landscape at 360 dp height, the ready-state `Column` overflows its bottom by 24 px (a `RenderFlex` overflow; it is not scrollable). Reported by the Task 6 probe in the run without the fix as well, and there is no bottom inset in landscape, so the fix does not cause it. [apps/mobile/lib/app/home_page.dart:489] — deferred, pre-existing
- Dismissed (13), each verified:
  - repeats of round 1: "no test pins the inset"; "`top: false` assumes an AppBar" (Scaffold strips the top padding when `appBar != null`, all three hosts have one); "the non-ready states are untouched" (centered content); "the banner and toolbar are not full-bleed when a side inset exists", and "a dead strip under the toolbar with gesture navigation" (both accepted: "No edge-to-edge polish"); "the comment is long and cites Story 5.8"; "the rule sits in a Node-oriented list"; "the diff shows no device evidence" (Task 5 is open on purpose); "the re-indent is hidden, so formatter compliance is unknown" (the Auditor diffed it after stripping leading whitespace, and `dart format` is already non-clean at HEAD);
  - "`SafeArea` strips the padding from the `MediaQuery` of every descendant": nothing in the subtree reads it (grep over `file_editor`, `editor_toolbar`, `wikilink_autocomplete`, `convention_highlighting_controller`, `markdown_preview`; the suggestion row has an explicit `padding`);
  - "the status is `done` in the diff under review": a process note; the status is reset to `in-progress` until these findings are resolved;
  - "the deferral's line numbers will rot, and the claim is unreproduced": the five numbers were verified accurate, and the claim is now reproduced in a widget test (see the patch above);
  - "`AnimatedList`/`AnimatedGrid` also add the main-axis inset, so 'anything else never does' is broad": the app uses neither;
  - the Edge Case Hunter's boundary walk (keyboard sweep, hosts with `bottomNavigationBar`, `TabBarView`, cutouts, split-screen): no defect, so nothing to record.

## Dev Notes

### Current state of the code this story touches (read before editing)

- **`apps/mobile/lib/app/file_editor.dart` → `FileEditorState.build`
  (`:415–515`).** It switches on `_loadState`:
  - `loading` → a centered spinner;
  - `error` → centered text;
  - `ready` → a `Column`. Its children, in order:
    - the conflict-copy banner, if `_isConflictCopy`;
    - the lossy-UTF-8 banner, if `_lossyLoad`;
    - then **either** `Expanded(MarkdownPreview(...))` (`_previewing`, the
      default after load) **or** `Expanded(Padding(12, TextField(expands: true)))`,
      the optional 44-high `[[` suggestion `ListView` (Story 3.2), and
      `EditorToolbar(controller: _controller)`.

  Only the `ready` `Column` changes.
- **`apps/mobile/lib/app/editor_toolbar.dart:456–466`.** `EditorToolbar` is a
  `Material(color: surfaceContainerHighest)` → `Focus(canRequestFocus: false,
  descendantsAreFocusable: false)` → `SizedBox(height: 48)` → a horizontal
  `SingleChildScrollView`.

  The non-focusable `Focus` keeps taps from stealing focus from the `TextField`
  and dismissing the keyboard (FR8). Don't touch this file.
- **Hosts.** Each has an `AppBar` and no `bottomNavigationBar`, and none sets
  `resizeToAvoidBottomInset` (grep confirms it isn't set anywhere in `lib/`). The
  `AppBar`s with a `TabBar` in `AppBar.bottom` are on the top inset side, which
  this story doesn't touch.
  - `EditorPage`: `body: FileEditor`, `editor_page.dart:244`.
  - `PairedEditorPage`: `body: TabBarView` of `_KeepAlive(FileEditor)`,
    `paired_editor_page.dart:556`.
  - `UndeterminedLanguagePage`: `body: FileEditor`,
    `undetermined_language_page.dart:406`.

### What must be preserved

- Everything `FileEditorState` does beyond `build`. This story changes one
  widget wrapper; no state, lifecycle, or save logic moves.
- The toolbar sits flush on the keyboard (FR8). Any gap there means something other
  than this wrapper changed: a host's `resizeToAvoidBottomInset` was turned off, or a
  `SafeArea` was put above the `Scaffold` (`maintainBottomViewPadding` alone does
  nothing inside it).
- The `[[` suggestion row stays docked between the text and the toolbar
  (Story 3.2).
- The `Save failed` SnackBar (`file_editor.dart:389`) is shown by the host's
  `Scaffold`, which positions it above the inset on its own. It is unaffected.
- `EntityDetailPage`'s card preview is a separate `MarkdownPreview` instance
  inside a `ListView` and already correct. It is unaffected because
  `MarkdownPreview` isn't edited.

### Architecture guardrails

- UI-only change inside the `app/` slice (AD-12). No `lore/`, `storage/` or `ai/`
  code is touched, and no port or model shape changes, so AD-2's fixtures are
  irrelevant (the contract gate must still be clean).
- No new dependency. `SafeArea` comes from `package:flutter/widgets.dart` and is
  already available through the existing `material.dart` import.

### Testing standards

- Per project-context.md "Testing emphasis": layout is not business logic, so
  **no new committed test.** The probe in Task 2 exists to *verify*, the same way
  the [[verify-before-asserting]] practice handles Flutter layout uncertainty.
  Then it's deleted.
- The existing suite runs with zero view padding (the `flutter_test` default), so
  the wrapper is a no-op there. If any existing test breaks, that's a signal: an
  earlier test asserting exact positions or `Column` ancestry. Investigate it,
  don't paper over it.
- The probe can only verify the framework side (`SafeArea` + `Scaffold`). The
  engine side (Android really reporting `padding.bottom = 0` while the keyboard
  is up) is covered by Task 5's device check.

### Previous story intelligence

- **5.2 (theme):** the last app-wide UI-chrome story. Its lesson applies here
  too: fix at the shared seam (`theme.dart` there, `FileEditor` here), not per
  call site.
- **2.5 / 2.14:** established that the toolbar lives above the keyboard and must
  not steal focus. This story must not change what sits between the toolbar and
  the keyboard.
- **3.2:** docked the suggestion row deliberately (not a floating overlay). It
  moves up together with the toolbar inside the same `SafeArea`; nothing to
  adjust.
- **5.7 / 5.5:** cross-model review caught real issues every story; plan the
  review on a different model than the implementer.

### Git intelligence

- HEAD `2b6e8e6` (Story 5.7). `main` is clean. No parallel story is touching
  `file_editor.dart` (its last change was Story 5.2's monospace constant,
  `fd90367`).
- Branch `story/5-8-keep-the-editor-clear-of-the-android-navigation-bar` off
  `main`; one commit with a `Co-Authored-By` trailer; `git merge --ff-only`;
  never push.
- Stage:
  - `apps/mobile/lib/app/file_editor.dart` and `apps/mobile/lib/app/home_page.dart` (Task 6);
  - this story file and `sprint-status.yaml`;
  - `_bmad-output/project-context.md` (Task 3);
  - `_bmad-output/planning-artifacts/epics.md` (Story 5.8 entry);
  - `_bmad-output/implementation-artifacts/deferred-work.md` (the review deferrals).

  Verify the probe test is **not** staged.

### Latest tech information

- Flutter 3.44.7 stable (`C:\programs\flutter\bin\cache\flutter.version.json`).
  Default `targetSdkVersion = 36`, `compileSdkVersion = 36`. The app pins
  `compileSdk = 37` (Story 4.1, for `flutter_secure_storage`); `minSdk = 30`.
- Android 16 behavior changes: for apps targeting API 36,
  `R.attr#windowOptOutEdgeToEdgeEnforcement` is deprecated and disabled, and the
  app can't opt out of edge-to-edge. Source:
  https://developer.android.com/about/versions/16/behavior-changes-16
- Community confirmation of the same Flutter symptom and fix (consume the insets
  with `SafeArea` / `MediaQuery` padding rather than opting out):
  https://startdebugging.net/2026/08/fix-flutter-ui-overlaps-the-android-navigation-bar-after-targeting-sdk-35/

### Project Structure Notes

- Production change: one file, `apps/mobile/lib/app/file_editor.dart`.
- Doc change: `_bmad-output/project-context.md`. `docs/agent-writing-rules.md`
  is the external-agent *prose* rulebook, so this layout rule doesn't belong
  there.
- No conflicts with the unified structure.

### References

- [Source: apps/mobile/lib/app/file_editor.dart:415-515 — `FileEditorState.build`]
- [Source: apps/mobile/lib/app/markdown_preview.dart:122 — preview `SingleChildScrollView` with an explicit padding]
- [Source: apps/mobile/lib/app/editor_toolbar.dart:456-466 — toolbar `Material`/`Focus`/48-high bar]
- [Source: apps/mobile/lib/app/editor_page.dart:244, paired_editor_page.dart:556, undetermined_language_page.dart:406 — the three hosts]
- [Source: apps/mobile/android/app/build.gradle.kts:14,28-29 — compileSdk 37, minSdk 30, targetSdk from Flutter]
- [Source: C:/programs/flutter/packages/flutter/lib/src/material/scaffold.dart — body `removeBottomPadding` only with `bottomNavigationBar`/`persistentFooterButtons`]
- [Source: C:/programs/flutter/packages/flutter/lib/src/widgets/media_query.dart — "Insets and Padding": `padding = max(0, viewPadding - viewInsets)`]
- [Source: _bmad-output/project-context.md — "Testing emphasis"]
- [Source: _bmad-output/planning-artifacts/epics.md — Epic 5, Story 5.8]

## Dev Agent Record

### Agent Model Used

Claude Opus 5.5 (`claude-opus-5-5`) for Tasks 1–5; Claude Sonnet 5.5 (`claude-sonnet-5-5`) for the review patches and Task 6.

### Debug Log References

Throwaway probe `apps/mobile/test/app/zz_inset_probe_test.dart`. The view was 360×800 logical (1080×2400 @ dpr 3) with a 48-logical bottom bar: `viewPadding` and `padding` were both set to 144 physical. The probe was deleted after the run and never staged.

| Probe | Before fix | After fix |
|---|---|---|
| `EditorPage` preview, last-line bottom (AC1) | 784 (fail, under the bar) | 736 = 752 − 16 scroll padding |
| `EditorPage` edit mode, toolbar bottom, keyboard hidden (AC2) | 800 (fail) | 752 |
| Edit mode with the keyboard: `viewInsets` 900, `padding` 0 (AC3) | 500 | 500 (no gap) |
| Landscape 800×360, 48 right bar, toolbar right edge (AC4) | 800 (fail) | 752 |
| `PairedEditorPage` preview, last-line bottom (AC1) | 784 (fail) | 736 |

The keyboard probe passes on both sides on purpose: it is the regression baseline proving the fix opens no gap above the keyboard.

Task 6 probe `apps/mobile/test/app/zz_home_inset_probe_test.dart` (deleted after the run): the real `LoreStoryApp` in its ready state, 360×800 logical, 48 dp bottom bar.

| Probe | Before fix | After fix |
|---|---|---|
| Home portrait, "Change folder" button rect (AC6) | y 728–776 (fail: 24 dp under the bar) | y 680–728 (clear of 752) |
| Home with no inset | y 728–776 | y 728–776 (unchanged) |
| Home landscape 800×360, 48 dp right bar, button right edge | 776 | 728 |

The landscape probe also raised a `RenderFlex` bottom overflow of 24 px in the post-fix run, and an overflow-type error already appeared in the pre-fix run; no bottom inset exists in landscape, so the fix does not cause it (deferred, see Review Findings).

Probe gotcha, for the next layout probe: the whole preview is one tall paragraph whose centre is off-screen, so `.hitTestable()` finds nothing. Pick the copy by its rect instead.

### Completion Notes List

- Wrapped `FileEditor`'s ready-state `Column` in `SafeArea(top: false)` (`file_editor.dart`), with a comment saying why.
  - `maintainBottomViewPadding` stays at its default `false`; no `minimum`.
  - The loading/error states, `MarkdownPreview`, `EditorToolbar` and every host page are untouched.
  - The `Column` body moved one indent level. `git diff -w` shows the change is the wrapper alone.
- The probe reproduced the bug on unfixed code for both the single and the paired host (AC1/AC2/AC4) and passed with the fix, with no keyboard gap (AC3).
  - `UndeterminedLanguagePage` was not probed separately: its body is a bare `FileEditor` with no `bottomNavigationBar`, the same structure as `EditorPage`.
- Added the edge-to-edge rule to `_bmad-output/project-context.md` → "Developer workflow", wrapped to the section's width with code spans kept intact.
- Gates:
  - `flutter analyze`: no issues;
  - `flutter test`: 834/834 pass, existing suite unedited (AC5);
  - `npm test`: 4/4;
  - contract git-clean: empty.
- No permanent test added, per project-context.md "Testing emphasis": this is layout, not business logic.
- **Task 6 (Home screen, review round 2, option A):** `home_page.dart`'s body is now `SafeArea(top: false, child: Padding(24, ...))`, with a comment. No other line of that file changed. The probe failed before and passes after (see Debug Log); gates re-run green (`flutter analyze` clean, `flutter test` 834/834, `npm test` 4/4, contract git-clean).
  - The wrap also stops the padding-less `ListView` above the buttons from adding a bar-height of dead space at its own end.
  - Two pre-existing Home-screen items surfaced and are deferred: the FAB covers the right end of "Change folder", and the landscape overflow.
- **Task 5 (device check) is open and belongs to KseiPo.** It needs the built APK on a real phone, which is the only place the engine side is verified: Android reporting `padding.bottom = 0` while the keyboard is up.

### File List

- `apps/mobile/lib/app/file_editor.dart` (modified)
- `apps/mobile/lib/app/home_page.dart` (modified: Task 6)
- `_bmad-output/project-context.md` (modified)
- `_bmad-output/planning-artifacts/epics.md` (modified: Story 5.8 entry, at story creation; AC6 and the Context sentence after review round 2)
- `_bmad-output/implementation-artifacts/5-8-keep-the-editor-clear-of-the-android-navigation-bar.md` (new)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified)
- `_bmad-output/implementation-artifacts/deferred-work.md` (modified: one deferred review finding)

## Change Log

- 2026-10-01: Story created from KseiPo's bug report (the navigation bar covers the last lines on the read/edit screen) and the option-A fix agreed in planning. Ultimate context engine analysis completed; comprehensive developer guide created.
- 2026-10-01: Implemented (Opus 5.5). `FileEditor` ready state wrapped in `SafeArea(top: false)`; probe-verified before/after on single and paired hosts, portrait/keyboard/landscape; edge-to-edge rule added to project-context.md. Status → review; Task 5 (on-device check) pending KseiPo.
- 2026-10-01: Code review (cross-model, Sonnet 5.5): 0 decision-needed, 1 patch (applied: the edge-to-edge rule in project-context.md reworded), 1 defer (landscape side insets on the `ListView` screens), 12 dismissed. Status → done; Task 5 (on-device check) is still open for KseiPo.
- 2026-10-02: Review round 2 (Sonnet 5.5) found the Home screen's "Change folder" button partly under the bar; KseiPo chose option A. Task 6 added and done (`home_page.dart` body wrapped in `SafeArea(top: false)`), AC6 added, survey row / Non-goal / `epics.md` corrected. Status → in-progress while the five documentation patches from round 2 are still open.
- 2026-10-02: Applied the five documentation patches from review round 2 (the `maintainBottomViewPadding` rationale, `persistentFooterButtons`, the deferral entry, the Stage list, the Task 3.1 note). All decision-needed and patch findings are resolved; Status → done. Task 5 (on-device check, now including the Home screen) is still open for KseiPo.
