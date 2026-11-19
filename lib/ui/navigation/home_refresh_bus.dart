import 'package:flutter/foundation.dart';

final homeRefreshBus = HomeRefreshBus();

class HomeRefreshBus extends ValueNotifier<int> {
  HomeRefreshBus() : super(0);

  bool _pendingRefresh = false;
  bool _newMediaBar = false;
  bool _newSectionsOnly = false;

  /// [newMediaBar] also loads a new set into the media bar, for a refresh the
  /// viewer asked for. [newSectionsOnly] loads only the sections Home has no
  /// rows for yet, for a change that only adds sections.
  void request({bool newMediaBar = false, bool newSectionsOnly = false}) {
    _newMediaBar = _newMediaBar || newMediaBar;
    _newSectionsOnly = newSectionsOnly;
    value = value + 1;
  }

  bool consumeNewMediaBar() {
    final newMediaBar = _newMediaBar;
    _newMediaBar = false;
    return newMediaBar;
  }

  bool consumeNewSectionsOnly() {
    final newSectionsOnly = _newSectionsOnly;
    _newSectionsOnly = false;
    return newSectionsOnly;
  }

  void requestAfterNavigation() {
    _pendingRefresh = true;
  }

  /// Kos TV: going to Home from the menu. A Home still alive underneath (on
  /// a TV or a phone menu pages go over it) stays as it was, so nothing is
  /// asked of it; only a Home built afresh (the web's) refreshes as it comes.
  /// Left pending with Home alive, the request lingered and fired on the
  /// next Home built: the next profile's.
  void requestOnArrival() {
    if (hasListeners) return;
    requestAfterNavigation();
  }

  void requestNowOrAfterNavigation({bool newSectionsOnly = false}) {
    if (hasListeners) {
      request(newSectionsOnly: newSectionsOnly);
    } else {
      requestAfterNavigation();
    }
  }

  bool consumePending() {
    if (!_pendingRefresh) {
      return false;
    }
    _pendingRefresh = false;
    return true;
  }
}
