import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../auth/repositories/session_repository.dart';
import '../../data/models/aggregated_library.dart';

/// Kos TV: the libraries the menus (top bar, side bar, bottom bar) last
/// loaded, and whose they were. Each page builds its own menu, and the
/// list, even cached, only comes after its first frame: starting from the
/// last one, a page the menu brings in has the same buttons as the one it
/// covers from that first frame, and nothing jumps a frame later. The load
/// each menu still makes corrects it if they changed.
///
/// Kept per person: another profile (a child's, with fewer libraries)
/// starts empty rather than with somebody else's buttons.
class NavLibrariesMemory {
  NavLibrariesMemory._();

  static String? _userId;
  static List<AggregatedLibrary> _libraries = const [];

  /// Whoever is signed in now, or null.
  static String? activeUserId() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<SessionRepository>()) return null;
    try {
      return getIt<SessionRepository>().activeUserId;
    } catch (_) {
      return null;
    }
  }

  /// The last libraries loaded for whoever is signed in now, or none.
  static List<AggregatedLibrary> forActiveUser() {
    final userId = activeUserId();
    if (userId == null || userId != _userId) return const [];
    return List.of(_libraries);
  }

  /// [libraries] were just loaded for [userId] (the one signed in when the
  /// load began). Nothing is kept for a load that finished after someone
  /// else signed in.
  static void remember(String? userId, List<AggregatedLibrary> libraries) {
    if (userId == null || userId != activeUserId()) return;
    _userId = userId;
    _libraries = List.unmodifiable(libraries);
  }

  @visibleForTesting
  static void reset() {
    _userId = null;
    _libraries = const [];
  }
}
