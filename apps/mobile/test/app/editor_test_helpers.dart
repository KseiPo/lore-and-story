import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor opens in the read-only **preview** by default (Story 2.7).
/// Tests that need the raw editing surface (the `TextField`, the toolbar) call
/// this to flip into edit mode via the AppBar toggle. A no-op if the toggle
/// isn't present (e.g. the load-error state), so it's always safe to call.
Future<void> enterEditMode(WidgetTester tester) async {
  final editToggle = find.byIcon(Icons.edit_outlined);
  if (editToggle.evaluate().isNotEmpty) {
    await tester.tap(editToggle);
    await tester.pumpAndSettle();
  }
}
