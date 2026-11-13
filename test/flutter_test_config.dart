import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/navigation/menu_preview.dart';

/// Runs around every test file.
///
/// Kos TV: the menu showing pages as the person rests on its buttons is
/// shared by every menu, so one test resting on a button mustn't leave the
/// next one with the focus kept on a menu that is gone.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(MenuPreview.stopHolding);
  tearDown(MenuPreview.stopHolding);
  await testMain();
}
