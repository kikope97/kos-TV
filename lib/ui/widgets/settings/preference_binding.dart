import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../../preference/user_preferences.dart';

/// A setting's value for a tile. It follows the stored value, so a change
/// made elsewhere (the server's sync, another screen, a reset) shows here
/// too instead of the tile keeping what it read when it was built.
class PreferenceBinding<T> extends ValueNotifier<T> {
  final Preference<T> _preference;
  final UserPreferences _prefs;

  PreferenceBinding(PreferenceStore store, this._preference)
    : _prefs = GetIt.instance<UserPreferences>(),
      super(GetIt.instance<UserPreferences>().get(_preference)) {
    _prefs.addListener(_follow);
  }

  void _follow() {
    final stored = _prefs.get(_preference);
    if (stored != super.value) super.value = stored;
  }

  @override
  set value(T newValue) {
    super.value = newValue;
    unawaited(_prefs.set(_preference, newValue));
  }

  void reset() {
    value = _preference.defaultValue;
  }

  @override
  void dispose() {
    _prefs.removeListener(_follow);
    super.dispose();
  }
}
