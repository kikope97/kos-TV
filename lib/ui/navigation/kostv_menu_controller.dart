import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/user_repository.dart';
import '../../data/models/aggregated_library.dart';
import '../../data/repositories/multi_server_repository.dart';
import '../../data/repositories/user_views_repository.dart';
import '../../data/services/achievements_service.dart';
import '../../data/services/installed_apps_service.dart';
import '../../data/services/kostv_favorites_news.dart';
import '../../data/services/library_scope_service.dart';
import '../../data/services/plugin_sync_service.dart';
import '../../data/services/saved_media_presence.dart';
import '../../data/services/server_messages_service.dart';
import '../../data/services/stremfin/stremfin_service.dart';
import '../../data/utils/user_avatar_url.dart';
import '../../preference/bottom_nav_tabs.dart';
import '../../preference/user_preferences.dart';
import '../../util/game_library.dart';
import '../../util/live_tv_library.dart';
import '../../util/platform_detection.dart';
import '../../util/signed_in_server_features.dart';
import '../widgets/bottom_nav/bottom_nav_model.dart';
import '../widgets/downloads_nav_slot.dart';
import '../widgets/friends_nav_slot.dart';
import '../widgets/kostv_requests_tray_button.dart';
import 'nav_libraries_memory.dart';

/// Kos TV: everything the menu knows beyond its own layout, the same for the
/// TV's and the computer's top bar and the phone's glass bar: which
/// destinations are on offer (on the bar, in «Más» and in «Tú»), the
/// libraries, the signed-in person and the counts on the avatar. Each bar
/// owns one.
class KostvMenuController extends ChangeNotifier {
  KostvMenuController() {
    _prefs.addListener(_onPrefsChanged);
    _viewsRepo.addListener(_scheduleLibrariesReload);
    _pluginSync?.addListener(_onPrefsChanged);
    _stremfin?.addListener(notifyListeners);
    // Of the tray the menu only shows its news and whether something is
    // under way, while a download makes it notify every few seconds.
    _inboxState = _readInbox();
    _stremfin?.inbox.addListener(_onInboxChanged);
    _favoritesNews?.addListener(notifyListeners);
    _messages?.addListener(notifyListeners);
    _achievements?.addListener(notifyListeners);
    _savedMedia?.addListener(notifyListeners);
    _userSub = _userRepo.currentUserStream.listen((_) {
      _loadUser();
      notifyListeners();
    });
    _signature = _prefsSignature();
    _multiServer = _prefs.get(UserPreferences.enableMultiServerLibraries);
    _loadUser();
    _loadLibraries();
  }

  final _prefs = GetIt.instance<UserPreferences>();
  final _userRepo = GetIt.instance<UserRepository>();
  final _viewsRepo = GetIt.instance<UserViewsRepository>();
  final PluginSyncService? _pluginSync = _maybe<PluginSyncService>();
  final ServerMessagesService? _messages = _maybe<ServerMessagesService>();
  final AchievementsService? _achievements = _maybe<AchievementsService>();
  final SavedMediaPresence? _savedMedia = _maybe<SavedMediaPresence>();
  final StremfinService? _stremfin = _maybe<StremfinService>();
  final KostvFavoritesNewsService? _favoritesNews =
      _maybe<KostvFavoritesNewsService>();

  static T? _maybe<T extends Object>() =>
      GetIt.instance.isRegistered<T>() ? GetIt.instance<T>() : null;

  StreamSubscription? _userSub;
  Timer? _librariesReloadDebounce;
  String _signature = '';
  (int, bool, bool) _inboxState = (0, false, false);
  late bool _multiServer;
  bool _disposed = false;

  // The last libraries the menu had for this person, so the Live TV and
  // Libraries entries are in place from the menu's first frame (see
  // NavLibrariesMemory).
  List<AggregatedLibrary> _libraries = NavLibrariesMemory.forActiveUser();
  String? _userImageUrl;
  String _userName = '';

  String? get userImageUrl => _userImageUrl;
  String get userName => _userName;

  bool get kidsMode => _prefs.get(UserPreferences.kidsModeEnabled);

  BottomNavTabGates get gates => BottomNavTabGates.fromPreferences(
    _prefs,
    calendarAvailable: _pluginSync?.calendarAvailable ?? false,
    kostvDiscoverAvailable: _stremfin?.isAllowed ?? false,
  );

  bool get _hasLiveTvLibrary => _libraries.any(isLiveTvLibrary);

  /// The libraries behind Bibliotecas. Live TV drops out of the list once it
  /// has an entry of its own.
  List<AggregatedLibrary> get navLibraries => librariesForNav(
    _libraries,
    gates.offers(BottomNavTab.liveTv) && _hasLiveTvLibrary,
    hideLiveTv: kidsMode,
  );

  /// Offered is decided by settings alone, available also needs the data.
  bool isAvailable(BottomNavTab tab) => switch (tab) {
    BottomNavTab.libraries => navLibraries.isNotEmpty,
    BottomNavTab.liveTv => _hasLiveTvLibrary,
    _ => true,
  };

  /// Whether [tab] is on offer and has what it needs.
  bool shows(BottomNavTab tab) => gates.offers(tab) && isAvailable(tab);

  /// The glass bar's tabs: Inicio, two destinations and Tú.
  List<BottomNavBarItem> barItems() =>
      resolveBarItems(gates, isAvailable: isAvailable);

  /// Whether the libraries are each a tab of their own on the top bar
  /// («Mostrar las bibliotecas por separado»).
  bool get librariesIndividually =>
      _prefs.get(UserPreferences.showLibrariesIndividually);

  /// «Ver juntos»: the person turned watch parties and their button on.
  bool get showSyncPlay =>
      !kidsMode &&
      _prefs.get(UserPreferences.syncPlayEnabled) &&
      _prefs.get(UserPreferences.showSyncPlayButton);

  /// The TV's apps, on a TV with apps to list (only on the TV).
  bool get showApps => PlatformDetection.isTV && showKostvAppsButton(_prefs);

  /// Saved downloads, while there is something saved.
  bool get savedVisible =>
      DownloadsNavSlot.isOffered() && DownloadsNavSlot.hasSavedMedia();

  /// Whether the active server approves other devices' sign-in codes.
  bool get quickConnectVisible {
    final client = _maybe<MediaServerClient>();
    return client != null && client.features.supportsQuickConnect;
  }

  /// Whether the active server is Silo, whose words for Quick Connect differ
  /// ("Approve a sign-in").
  static bool get activeServerIsSilo =>
      _maybe<MediaServerClient>()?.serverType == ServerType.silo;

  bool get remoteControlVisible =>
      activeServerSupports((f) => f.supportsRemoteControl);

  /// Whether the menu lists server messages: the person turned the button
  /// on and the server has something to say.
  bool get messagesVisible =>
      _prefs.get(UserPreferences.showServerMessagesButton) &&
      (_messages?.messages.isNotEmpty ?? false);

  int get unreadMessages => messagesVisible ? (_messages?.unreadCount ?? 0) : 0;

  /// Whether the menu lists Friends: the person left the button on and the
  /// server's Achievement Badges plugin has friends turned on.
  bool get friendsVisible =>
      FriendsNavSlot.isOffered() && (_achievements?.socialAvailable ?? false);

  int get friendsBadge =>
      friendsVisible ? (_achievements?.socialBadgeCount ?? 0) : 0;

  /// Whether «Tú» lists the requests tray: the requests service lets the
  /// person in, outside kids mode.
  bool get requestsVisible => kostvRequestsTrayAvailable();

  /// News in the requests tray the person hasn't seen.
  int get requestsNews => requestsVisible ? _inboxState.$1 : 0;

  /// Something asked for is on its way (the avatar's ring turns while it
  /// comes down).
  bool get requestsActive => requestsVisible && _inboxState.$2;
  bool get requestsWorking => requestsVisible && _inboxState.$3;

  /// Favourite series with news not seen yet.
  int get favoritesNews => _favoritesNews?.unseen ?? 0;

  /// What the avatar counts: the news behind «Tú».
  int get youBadge => requestsNews + favoritesNews;

  /// What «Más» counts: unread messages and friends' news.
  int get moreBadge => unreadMessages + friendsBadge;

  // Rebuilding the menu on every preference write in the app would be
  // wasted work, so only the settings the menu reads are compared.
  String _prefsSignature() => [
    _prefs.get(UserPreferences.kidsModeEnabled),
    _prefs.get(UserPreferences.showLibrariesInToolbar),
    _prefs.get(UserPreferences.showLibrariesIndividually),
    _prefs.get(UserPreferences.showFavoritesButton),
    _prefs.get(UserPreferences.showGenresButton),
    _prefs.get(UserPreferences.showLiveTvButton),
    _prefs.get(UserPreferences.showCalendarButton),
    _prefs.get(UserPreferences.syncPlayEnabled),
    _prefs.get(UserPreferences.showSyncPlayButton),
    _prefs.get(UserPreferences.showServerMessagesButton),
    _prefs.get(UserPreferences.showFriendsButton),
    _prefs.get(UserPreferences.showDownloadsButton),
    _prefs.get(UserPreferences.enableMultiServerLibraries),
    _prefs.get(UserPreferences.showDiscoverButton),
    _prefs.get(UserPreferences.kostvShowMusicButton),
    _prefs.get(UserPreferences.kostvMyListAvailable),
    _prefs.get(UserPreferences.use24HourClock),
    _prefs.get(UserPreferences.clockBehavior),
    showKostvAppsButton(_prefs),
    _pluginSync?.calendarAvailable ?? false,
  ].join('|');

  (int, bool, bool) _readInbox() {
    final inbox = _stremfin?.inbox;
    if (inbox == null) return (0, false, false);
    return (inbox.newsCount, inbox.hasActive, inbox.isWorking);
  }

  /// The tray changed. Only a change to what the menu shows reaches it.
  void _onInboxChanged() {
    final state = _readInbox();
    if (state == _inboxState) return;
    _inboxState = state;
    notifyListeners();
  }

  void _onPrefsChanged() {
    final next = _prefsSignature();
    if (next == _signature) return;
    _signature = next;
    // Only the multi-server switch changes where the libraries come from.
    final multiServer = _prefs.get(UserPreferences.enableMultiServerLibraries);
    if (multiServer != _multiServer) {
      _multiServer = multiServer;
      _scheduleLibrariesReload();
    }
    notifyListeners();
  }

  // Collapses a burst of change notifications, like the settings sync
  // applying a whole profile, into a single library reload.
  void _scheduleLibrariesReload() {
    _librariesReloadDebounce?.cancel();
    _librariesReloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!_disposed) _loadLibraries();
    });
  }

  void _loadUser() {
    final user = _userRepo.currentUser;
    _userName = user?.name ?? '';
    if (user == null) {
      _userImageUrl = null;
      return;
    }
    try {
      _userImageUrl = userAvatarUrl(
        GetIt.instance<MediaServerClient>(),
        userId: user.id,
        imageTag: user.imageTag,
      );
    } catch (_) {
      _userImageUrl = null;
    }
  }

  Future<void> _loadLibraries() async {
    final userId = NavLibrariesMemory.activeUserId();
    try {
      final useMultiServer = _prefs.get(
        UserPreferences.enableMultiServerLibraries,
      );
      final libs = useMultiServer
          ? await GetIt.instance<MultiServerRepository>()
                .getAggregatedLibraries()
          : await _viewsRepo.getUserViews();

      if (GetIt.instance.isRegistered<GameLibraryRegistry>()) {
        unawaited(GetIt.instance<GameLibraryRegistry>().refresh());
      }

      final filtered = useMultiServer
          ? await GetIt.instance<LibraryScopeService>().withoutHiddenLibraries(
              libs,
            )
          : libs;

      NavLibrariesMemory.remember(userId, filtered);
      if (_disposed || _sameLibraries(_libraries, filtered)) return;
      _libraries = filtered;
      notifyListeners();
    } catch (_) {}
  }

  static bool _sameLibraries(
    List<AggregatedLibrary> a,
    List<AggregatedLibrary> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _prefs.removeListener(_onPrefsChanged);
    try {
      _viewsRepo.removeListener(_scheduleLibrariesReload);
      _pluginSync?.removeListener(_onPrefsChanged);
      _messages?.removeListener(notifyListeners);
      _achievements?.removeListener(notifyListeners);
      _savedMedia?.removeListener(notifyListeners);
      _stremfin?.removeListener(notifyListeners);
      _stremfin?.inbox.removeListener(_onInboxChanged);
      _favoritesNews?.removeListener(notifyListeners);
    } catch (_) {}
    _userSub?.cancel();
    _librariesReloadDebounce?.cancel();
    super.dispose();
  }
}
