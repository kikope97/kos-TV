import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show BrowserContextMenu;

/// Kos TV: the browser's own right-click menu kept off while a page with a
/// menu of its own is open. Counted, since the switch is one for the whole
/// app: going back from one such page to another mustn't turn it on again
/// under the one still open.
int _holding = 0;

/// A page with its own right-click menu opened.
void kostvHoldBrowserMenu() {
  if (!kIsWeb) return;
  if (_holding++ == 0) unawaited(BrowserContextMenu.disableContextMenu());
}

/// That page closed.
void kostvReleaseBrowserMenu() {
  if (!kIsWeb || _holding == 0) return;
  if (--_holding == 0) unawaited(BrowserContextMenu.enableContextMenu());
}
