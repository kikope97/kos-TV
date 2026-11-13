import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/navigation/menu_preview.dart';
import 'package:moonfin/util/episode_code.dart';

/// Runs around every test file.
///
/// Kos TV: the menu showing pages as the person rests on its buttons is
/// shared by every menu, so one test resting on a button mustn't leave the
/// next one with the focus kept on a menu that is gone. And episode codes
/// follow the English texts the tests read.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(MenuPreview.stopHolding);
  // The tests read the English texts, so episodes are «S1:E6» in them.
  setUp(() => seasonMark = 'S');
  tearDown(MenuPreview.stopHolding);
  await testMain();
}
