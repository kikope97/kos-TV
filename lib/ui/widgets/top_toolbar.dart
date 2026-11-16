import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../screens/music/kostv_music_widgets.dart' show kostvMusicColor;
import 'music/kostv_now_playing.dart';
import 'music/kostv_now_playing_capsule.dart' show KostvEqualizerBars;
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/app_localizations.dart';
import '../../auth/repositories/user_repository.dart';
import '../../data/services/installed_apps_service.dart';
import '../../data/services/stremfin/stremfin_service.dart';
import '../../data/models/aggregated_library.dart';
import '../../data/repositories/multi_server_repository.dart';
import '../../data/repositories/user_views_repository.dart';
import '../../data/services/achievements_service.dart';
import '../../data/services/library_scope_service.dart';
import '../../data/services/plugin_sync_service.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/audio_artwork_url.dart';
import '../../util/clock_format.dart';
import '../../util/game_library.dart';
import '../../util/live_tv_library.dart';
import '../../util/overlay_color_palette.dart';
import '../../util/platform_detection.dart';
import '../navigation/destinations.dart';
import '../navigation/menu_preview.dart';
import '../navigation/home_refresh_bus.dart';
import '../navigation/route_lifecycle_observer.dart';
import 'downloads_nav_slot.dart';
import 'kostv_favorites_shortcut.dart';
import 'nav_capsule.dart';
import 'friends_nav_slot.dart';
import 'expandable_icon_button.dart';
import 'marquee_text.dart';
import 'navigation_layout.dart';
import 'settings/settings_panel.dart';
import '../screens/discover/kostv_requests_tray.dart';
import '../screens/downloads/downloads_panel.dart';
import '../screens/settings/settings_side_panel.dart';
import '../screens/watch_party/watch_together_route.dart';
import 'server_messages_dialog.dart';
import 'server_messages_nav_slot.dart';
import 'user_menu_dialog.dart';

import 'offline_aware_image.dart';
import 'package:playback_core/playback_core.dart';
import '../../data/models/aggregated_item.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/services/kostv_favorites_news.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/input_mode_tracker.dart';
import '../navigation/app_router.dart';
import 'adaptive/sf_symbol.dart';
import 'kostv_requests_tray_button.dart';
import 'user_avatar_image.dart';

const _kToolbarHeightTV = 95.0;
const _kToolbarHeightDesktop = 80.0;
const _kToolbarHeightMobile = 60.0;
const _kOverscanH = 48.0;
const _kOverscanV = 27.0;
const _kNavbarBackdrop = Color(0x1AFFFFFF);
const _kAvatarSize = 40.0;
const _kPillRadius = 36.0;
const _kButtonSpacing = 12.0;
const _kButtonSpacingMobile = 8.0;
const _kButtonSpacingTV = 2.0;
const _kMusicBarTitleMaxWidth = 280.0;

class TopToolbar extends StatefulWidget {
  final String? activeRoute;
  final bool showBackButton;
  final FocusNode? contentFocusNode;

  /// True while focus is inside the toolbar, so screens can avoid stealing its
  /// d-pad keys. Mirrors [LeftSidebar.isFocusedNotifier].
  static final ValueNotifier<bool> isFocusedNotifier = ValueNotifier<bool>(
    false,
  );

  const TopToolbar({
    super.key,
    this.activeRoute,
    this.showBackButton = false,
    this.contentFocusNode,
  });

  /// Extra height the embedded music bar adds to the toolbar when audio is
  /// playing, or 0 when it is not. Single source of truth so the toolbar's own
  /// layout and the content inset stay in sync.
  ///
  /// Kos TV: none. The music lives in the floating player
  /// (kostv_now_playing_capsule.dart), not under the menu.
  static double musicBarExtraHeight() => 0.0;

  /// Base height of the toolbar for the current platform (excluding music bar).
  static double baseHeightFor(BuildContext context) {
    return PlatformDetection.useLeanbackUi
        ? _kToolbarHeightTV
        : PlatformDetection.useMobileUi
        ? _kToolbarHeightMobile
        : _kToolbarHeightDesktop;
  }

  /// Total laid-out height of the toolbar for the current platform.
  static double heightFor(BuildContext context) {
    return baseHeightFor(context) + musicBarExtraHeight();
  }

  @override
  State<TopToolbar> createState() => _TopToolbarState();
}

class _TopToolbarState extends State<TopToolbar> with RouteAware {
  final _userRepo = GetIt.instance<UserRepository>();
  final _prefs = GetIt.instance<UserPreferences>();
  final _viewsRepo = GetIt.instance<UserViewsRepository>();

  final _avatarFocus = FocusNode();

  /// Kos TV: the requests tray beside the avatar, and whether the pointer is
  /// over them (which brings it out, as the focus does).
  final _trayFocus = FocusNode(debugLabel: 'kostvRequestsTray');
  final _favoritesFocus = FocusNode(debugLabel: 'kostvMyFavorites');

  /// Kos TV: the news of the favourite series, for the heart's count.
  final KostvFavoritesNewsService? _favoritesNews =
      GetIt.instance.isRegistered<KostvFavoritesNewsService>()
      ? GetIt.instance<KostvFavoritesNewsService>()
      : null;
  static final _neverChanges = ValueNotifier<int>(0);
  bool _startHovered = false;
  final _homeFocus = FocusNode(debugLabel: 'TopToolbarHome');
  final _settingsFocus = FocusNode(debugLabel: 'TopToolbarSettings');
  final _serverMessagesFocus = FocusNode(
    debugLabel: 'TopToolbarServerMessages',
  );
  final _friendsFocus = FocusNode(debugLabel: 'TopToolbarFriends');
  final _toolbarScopeNode = FocusNode(
    debugLabel: 'TopToolbarScope',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _musicBarFocusNode = FocusNode(debugLabel: 'TopMusicBar');
  late final VoidCallback _focusNavbarCallback;
  late final VoidCallback _focusAvatarCallback;
  VoidCallback? _previousFocusNavbarCallback;
  VoidCallback? _previousFocusAvatarCallback;
  FocusNode? _previousFocus;
  // Tracked per instance so only the toolbar that actually held focus
  // clears the shared isFocusedNotifier on dispose.
  bool _toolbarHadFocus = false;
  bool _friendsAvailable = FriendsNavSlot.isAvailable();
  // Kos TV: starts from the libraries the last toolbar had, so a page the
  // menu brings in has the same buttons as the one it covers from its first
  // frame. The load below corrects it if they changed.
  static List<AggregatedLibrary> _lastLibraries = const [];
  List<AggregatedLibrary> _libraries = List.of(_lastLibraries);
  Timer? _clockTimer;
  Timer? _librariesReloadDebounce;
  late final ValueNotifier<String> _currentTime;
  StreamSubscription? _userSub;
  String? _userImageUrl;

  @override
  void initState() {
    super.initState();
    _currentTime = ValueNotifier<String>('');
    // Guarded so a stale registration from a torn-down toolbar is a safe
    // no-op instead of focusing a disposed node.
    _focusNavbarCallback = () {
      if (!mounted) return;
      // Kos TV: up into the menu lands on the page's own button, so resting
      // there shows nothing new.
      final route = widget.activeRoute;
      final own = route != null && Destinations.isMenuPage(route)
          ? _menuNode(route)
          : null;
      if (own != null && own.context != null && own.canRequestFocus) {
        own.requestFocus();
        return;
      }
      if (_homeFocus.context == null) return;
      _homeFocus.requestFocus();
    };
    MenuPreview.track();
    _focusAvatarCallback = () {
      if (!mounted || _avatarFocus.context == null) return;
      _avatarFocus.requestFocus();
    };
    _previousFocusNavbarCallback = NavigationLayout.focusNavbarNotifier.value;
    _previousFocusAvatarCallback =
        NavigationLayout.focusNavbarAvatarNotifier.value;
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    NavigationLayout.chromeFocusRoots.add(_toolbarScopeNode);
    _avatarFocus.addListener(_onAvatarFocusChanged);
    _trayFocus.addListener(_onAvatarFocusChanged);
    _favoritesFocus.addListener(_onAvatarFocusChanged);
    FocusManager.instance.addListener(_trackPreviousFocus);
    MenuPreview.arriving.addListener(_onMenuArriving);
    _onMenuArriving();
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateClock(),
    );
    _loadUserImage();
    _userSub = _userRepo.currentUserStream.listen((_) => _loadUserImage());
    _prefs.addListener(_onPrefsChanged);
    _viewsRepo.addListener(_onUserViewsChanged);
    GetIt.instance<PluginSyncService>().addListener(_onPrefsChanged);
    if (GetIt.instance.isRegistered<StremfinService>()) {
      GetIt.instance<StremfinService>().addListener(_onPrefsChanged);
    }
    if (GetIt.instance.isRegistered<AchievementsService>()) {
      GetIt.instance<AchievementsService>().addListener(_onAchievementsChanged);
    }
    _loadLibraries();
  }

  ModalRoute<dynamic>? _observedRoute;

  /// Kos TV: whether this page was the one in front last time it looked.
  bool? _wasCurrent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // In front again, however the page above went (Back, or a page taken
    // away by going Home, which never tells didPopNext).
    final current = route?.isCurrent ?? true;
    if (current && _wasCurrent == false) _backInFront();
    _wasCurrent = current;
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
    }
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Our route is current again. An out of order route teardown can leave
    // the focus bridge pointing at a torn-down chrome instance, so re-assert
    // that it targets this live one.
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    _backInFront();
  }

  /// Kos TV: back on this page, the focus comes back where it was in it,
  /// which can be another page's button in this menu (the one taken to
  /// leave). Resting there would open that page again: the menu's focus
  /// goes to this page's own button. Once now, and again when the page
  /// above has finished leaving (the focus can come back at the end of its
  /// animation).
  void _backInFront() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusOwnButton());
    _stopWatchingReturn();
    final back = ModalRoute.of(context)?.secondaryAnimation;
    if (back != null && !back.isDismissed) {
      _returning = back..addStatusListener(_onReturnStatus);
    }
  }

  Animation<double>? _returning;

  void _onReturnStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _stopWatchingReturn();
    _focusOwnButton();
  }

  void _stopWatchingReturn() {
    _returning?.removeStatusListener(_onReturnStatus);
    _returning = null;
  }

  void _focusOwnButton() {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    final route = widget.activeRoute;
    if (route == null || !Destinations.isMenuPage(route)) return;
    final focused = FocusManager.instance.primaryFocus;
    final own = _menuNode(route);
    if (focused == null || focused == own) return;
    final inMenu =
        focused == _homeFocus || _menuFocus.values.contains(focused);
    if (!inMenu || own.context == null || !own.canRequestFocus) return;
    _restTimer?.cancel();
    own.requestFocus();
  }

  @override
  void dispose() {
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
      _observedRoute = null;
    }
    if (identical(
      NavigationLayout.focusNavbarNotifier.value,
      _focusNavbarCallback,
    )) {
      NavigationLayout.focusNavbarNotifier.value = _previousFocusNavbarCallback;
    }
    if (identical(
      NavigationLayout.focusNavbarAvatarNotifier.value,
      _focusAvatarCallback,
    )) {
      NavigationLayout.focusNavbarAvatarNotifier.value =
          _previousFocusAvatarCallback;
    }
    _clockTimer?.cancel();
    _librariesReloadDebounce?.cancel();
    // Only clear the shared flag if this instance held focus, so a torn-down
    // route's toolbar can't wipe the state of the one the user is on.
    if (_toolbarHadFocus) {
      TopToolbar.isFocusedNotifier.value = false;
    }
    NavigationLayout.chromeFocusRoots.remove(_toolbarScopeNode);
    _avatarFocus.removeListener(_onAvatarFocusChanged);
    _trayFocus.removeListener(_onAvatarFocusChanged);
    _favoritesFocus.removeListener(_onAvatarFocusChanged);
    _favoritesFocus.dispose();
    FocusManager.instance.removeListener(_trackPreviousFocus);
    MenuPreview.arriving.removeListener(_onMenuArriving);
    _stopWatchingReturn();
    _restTimer?.cancel();
    for (final node in _menuFocus.values) {
      node.dispose();
    }
    _toolbarScopeNode.dispose();
    _avatarFocus.dispose();
    _trayFocus.dispose();
    _homeFocus.dispose();
    _settingsFocus.dispose();
    _serverMessagesFocus.dispose();
    _friendsFocus.dispose();
    _musicBarFocusNode.dispose();
    _userSub?.cancel();
    try {
      _viewsRepo.removeListener(_onUserViewsChanged);
    } catch (_) {}
    try {
      GetIt.instance<PluginSyncService>().removeListener(_onPrefsChanged);
      if (GetIt.instance.isRegistered<StremfinService>()) {
        GetIt.instance<StremfinService>().removeListener(_onPrefsChanged);
      }
    } catch (_) {}
    try {
      GetIt.instance<AchievementsService>().removeListener(
        _onAchievementsChanged,
      );
    } catch (_) {}
    _prefs.removeListener(_onPrefsChanged);
    _currentTime.dispose();
    super.dispose();
  }

  Color _overlayColor() {
    return OverlayColorPalette.resolveColor(
      _prefs.get(UserPreferences.navbarColor),
    );
  }

  double _overlayOpacity() {
    return _prefs.get(UserPreferences.navbarOpacity) / 100.0;
  }

  Color _toolbarSurfaceColor() {
    if (ThemeRegistry.active.transparentNavbarSurface) {
      return Colors.transparent;
    }
    return _overlayColor().withValues(alpha: _overlayOpacity());
  }

  void _onPrefsChanged() {
    if (!mounted) return;
    _updateClock();
    _scheduleLibrariesReload();
    setState(() {});
  }

  void _onUserViewsChanged() {
    if (!mounted) return;
    _scheduleLibrariesReload();
  }

  /// The service also notifies on every badge refresh, which the slot redraws
  /// by itself, so the bar only rebuilds when the button comes or goes.
  void _onAchievementsChanged() {
    final available = FriendsNavSlot.isAvailable();
    if (!mounted || available == _friendsAvailable) return;
    setState(() => _friendsAvailable = available);
  }

  // Collapses a burst of change notifications, like the settings sync
  // applying a whole profile, into a single library reload.
  void _scheduleLibrariesReload() {
    _librariesReloadDebounce?.cancel();
    _librariesReloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadLibraries();
    });
  }

  /// Kos TV: left and right among the avatar, the requests tray and «Mis
  /// favoritos»; right from the last goes on to the menu as before.
  KeyEventResult _besideAvatarKey(
    KeyEvent event, {
    FocusNode? left,
    FocusNode? right,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final target = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? left
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? right
        : null;
    if (target == null || target.context == null) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    return KeyEventResult.handled;
  }

  void _onAvatarFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _updateClock() {
    final newTime = formatClockTime(
      DateTime.now(),
      use24Hour: _prefs.get(UserPreferences.use24HourClock),
    );
    if (mounted && _currentTime.value != newTime) {
      _currentTime.value = newTime;
    }
  }

  void _loadUserImage() {
    final user = _userRepo.currentUser;
    if (user == null) {
      setState(() => _userImageUrl = null);
      return;
    }
    try {
      final client = GetIt.instance<MediaServerClient>();
      setState(() => _userImageUrl = client.imageApi.getUserImageUrl(user.id));
    } catch (_) {
      setState(() => _userImageUrl = null);
    }
  }

  Future<void> _loadLibraries() async {
    try {
      final useMultiServer = _prefs.get(
        UserPreferences.enableMultiServerLibraries,
      );
      final libs = useMultiServer
          ? await GetIt.instance<MultiServerRepository>()
                .getAggregatedLibraries()
          : await _viewsRepo.getUserViews();

      unawaited(GetIt.instance<GameLibraryRegistry>().refresh());

      final filtered = useMultiServer
          ? await GetIt.instance<LibraryScopeService>().withoutHiddenLibraries(
              libs,
            )
          : libs;

      _lastLibraries = filtered;
      if (mounted && !_librariesEqual(_libraries, filtered)) {
        setState(() => _libraries = filtered);
      }
    } catch (_) {}
  }

  bool _librariesEqual(List<AggregatedLibrary> a, List<AggregatedLibrary> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  // Kids Mode sends /live-tv back to home, so the guide button would only be a
  // dead end.
  bool get _showLiveTvButton =>
      !_kidsMode &&
      _prefs.get(UserPreferences.showLiveTvButton) &&
      _libraries.any(isLiveTvLibrary);

  List<AggregatedLibrary> get _navLibraries =>
      librariesForNav(_libraries, _showLiveTvButton, hideLiveTv: _kidsMode);

  bool get _kidsMode => _prefs.get(UserPreferences.kidsModeEnabled);

  void _trackPreviousFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    // A whole page or route holding the focus for a moment (while a page
    // arrives) is no place to go back to: focusing it again hands the focus
    // to whatever it last had, the menu button included.
    if (primary.skipTraversal || primary is FocusScopeNode) return;
    if (_isInsideToolbar(primary)) return;
    // Kos TV: only this page's own content: not another page's menu nor a
    // page under or over this one, which go away and leave the focus
    // nowhere.
    if (MenuPreview.isMenu(primary)) return;
    final there = primary.context;
    if (there == null || !mounted) return;
    if (!(ModalRoute.isCurrentOf(there) ?? true)) return;
    _previousFocus = primary;
  }

  bool _isInsideToolbar(FocusNode node) {
    FocusNode? current = node;
    while (current != null) {
      if (identical(current, _toolbarScopeNode)) return true;
      current = current.parent;
    }
    return false;
  }

  bool _isDescendantOf(FocusNode? child, FocusNode parent) {
    FocusNode? current = child;
    while (current != null) {
      if (identical(current, parent)) return true;
      current = current.parent;
    }
    return false;
  }

  bool _isUsableOutsideToolbar(FocusNode? node) {
    if (node == null) return false;
    if (node.skipTraversal) return false;
    if (_isInsideToolbar(node)) return false;
    if (!_isLaidOutFocusNode(node)) return false;
    // Kos TV: not a page under or going away under the one on screen.
    return ModalRoute.isCurrentOf(node.context!) ?? true;
  }

  void _restoreFocusBelowToolbar() {
    // Kos TV: going down into the page, the menu lets go first. Still
    // holding, Home refused the focus it was being handed and the focus
    // went nowhere: neither Down nor OK did anything after resting on
    // Inicio.
    MenuPreview.stopHolding();
    if (NavigationLayout.focusDetailsPlayButton()) return;
    final focusContent = NavigationLayout.focusContentFromNavbarNotifier.value;
    if (focusContent != null && widget.activeRoute == Destinations.home) {
      focusContent();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null || _isInsideToolbar(primary)) {
          _restoreFocusBelowToolbarFallback();
        }
      });
      return;
    }

    _restoreFocusBelowToolbarFallback();
  }

  void _restoreFocusBelowToolbarFallback() {
    final previous = _previousFocus;
    if (previous != null && _isUsableOutsideToolbar(previous)) {
      previous.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (_isUsableOutsideToolbar(primary)) {
          return;
        }
        _previousFocus = null;
        _moveFocusDown();
      });
      return;
    }
    _previousFocus = null;
    _moveFocusDown();
  }

  /// A node can only take focus once its box exists and has been laid out.
  /// Asking earlier throws out of the focus machinery.
  bool _isReadyForFocus(FocusNode node) {
    final render = node.context?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize;
  }

  void _moveFocusDown({int attempt = 0}) {
    if (!mounted) return;
    final scope = FocusScope.of(context);
    // Directional traversal measures every candidate it walks, so one node
    // still waiting on layout takes the whole call down. The manual paths below
    // cover the same ground, so a failure here isn't worth surfacing.
    try {
      if (scope.focusInDirection(TraversalDirection.down)) {
        final primary = FocusManager.instance.primaryFocus;
        if (_isUsableOutsideToolbar(primary)) return;
      }
    } catch (_) {}

    final firstBelow = _findFirstFocusableBelowToolbar(scope);
    if (firstBelow != null && _isReadyForFocus(firstBelow)) {
      firstBelow.requestFocus();
      return;
    }
    final fallback = widget.contentFocusNode;
    if (fallback != null && fallback.context != null) {
      final firstContent = _firstFocusableDescendant(fallback);
      if (firstContent != null) {
        if (_isReadyForFocus(firstContent)) {
          firstContent.requestFocus();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final primary = FocusManager.instance.primaryFocus;
          if (_isUsableOutsideToolbar(primary)) return;
          if (attempt < 3) {
            _moveFocusDown(attempt: attempt + 1);
          }
        });
      } else if (attempt < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _moveFocusDown(attempt: attempt + 1);
        });
      }
      return;
    }
    if (attempt < 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveFocusDown(attempt: attempt + 1);
      });
    }
  }

  /// Renders nothing while there is nothing saved.
  Widget _buildDownloadsButton({
    required Color? navColor,
    required bool alwaysExpanded,
    required String label,
  }) {
    return DownloadsNavSlot(
      builder: (context) => ExpandableIconButton(
        key: const ValueKey('toolbar-downloads'),
        forceExpanded: alwaysExpanded,
        icon: Icons.download_for_offline,
        label: label,
        baseColor: navColor,
        onPressed: () => showDownloadsDialog(context),
      ),
    );
  }

  /// Moves focus one button along the toolbar, in painted order.
  ///
  /// [from] names where to step from when focus hasn't landed there yet. A
  /// request applies a microtask later, so a caller that has just moved focus
  /// can't rely on the primary node having caught up.
  bool _moveWithinToolbar(TraversalDirection direction, {FocusNode? from}) {
    final primary = from ?? FocusManager.instance.primaryFocus;
    if (primary == null || !_isInsideToolbar(primary)) return false;

    final insideMusicBar = _isDescendantOf(primary, _musicBarFocusNode);

    final nodes =
        _toolbarScopeNode.descendants
            .where((n) => !n.skipTraversal && _isLaidOutFocusNode(n))
            .where((n) {
              final isMusicNode = _isDescendantOf(n, _musicBarFocusNode);
              return insideMusicBar == isMusicNode;
            })
            .map((n) {
              final box = n.context!.findRenderObject() as RenderBox?;
              final pos = box?.localToGlobal(Offset.zero);
              return (node: n, x: pos?.dx ?? -1.0);
            })
            .where((item) => item.x > 0)
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));

    final index = nodes.indexWhere((e) => e.node == primary);
    if (index < 0) return false;
    final nextIndex = direction == TraversalDirection.right
        ? index + 1
        : index - 1;
    if (nextIndex < 0 || nextIndex >= nodes.length) return false;
    nodes[nextIndex].node.requestFocus();
    return true;
  }

  FocusNode? _findFirstFocusableBelowToolbar(FocusScopeNode scope) {
    for (final node in scope.traversalDescendants) {
      if (node.skipTraversal) continue;
      if (!_isLaidOutFocusNode(node)) continue;
      if (_isInsideToolbar(node)) continue;
      return node;
    }
    return null;
  }

  FocusNode? _firstFocusableDescendant(FocusNode node) {
    for (final child in node.children) {
      if (!child.skipTraversal && _isLaidOutFocusNode(child)) {
        return child;
      }
      final found = _firstFocusableDescendant(child);
      if (found != null) return found;
    }
    return null;
  }

  bool _isLaidOutFocusNode(FocusNode node) {
    if (!node.canRequestFocus) {
      return false;
    }
    final context = node.context;
    if (context == null) {
      return false;
    }
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize;
  }

  bool _isActive(String route) => widget.activeRoute == route;

  /// Kos TV: the buttons of the pages the menu shows by resting on them.
  final _menuFocus = <String, FocusNode>{};
  Timer? _restTimer;

  FocusNode _menuNode(String route) => route == Destinations.home
      ? _homeFocus
      : _menuFocus.putIfAbsent(
          route,
          () => FocusNode(debugLabel: 'TopToolbarMenu $route'),
        );

  /// Shows [route]'s page once the focus has rested on its button for a
  /// moment, with a remote or keys.
  void _restOn(String route, bool focused) {
    _restTimer?.cancel();
    if (!focused || !MenuPreview.supported || _isActive(route)) return;
    if (!InputModeTracker.showFocusVisuals(context, true)) return;
    // Only moving along the menu, not coming up into it from the page.
    if (!MenuPreview.movedAlong(Axis.horizontal)) return;
    _restTimer = Timer(MenuPreview.restDelay, () {
      if (!mounted || !_menuNode(route).hasFocus) return;
      if (!(ModalRoute.isCurrentOf(context) ?? true)) return;
      MenuPreview.show(context, route);
    });
  }

  /// OK on a menu button: its page opens as resting on it would, or, when
  /// it's the page already on screen, the focus goes into it.
  void _openFromMenu(String route) {
    if (MenuPreview.open(context, route) && _isActive(route)) {
      _restoreFocusBelowToolbar();
    }
  }

  /// OK on the button of the page already showing goes into the page, as
  /// Down does.
  bool _enterShownPage(String route) {
    if (!_isActive(route) || !MenuPreview.holding) return false;
    MenuPreview.stopHolding();
    _restoreFocusBelowToolbar();
    return true;
  }

  /// The page the menu is showing is this toolbar's: its button takes the
  /// focus, so the person goes on along the menu.
  void _onMenuArriving() {
    final route = MenuPreview.arriving.value;
    if (route == null || route != widget.activeRoute) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeArrival(route, 0));
  }

  void _takeArrival(String route, int attempt) {
    if (!mounted || MenuPreview.arriving.value != route) return;
    final node = _menuNode(route);
    if ((ModalRoute.isCurrentOf(context) ?? true) &&
        node.context != null &&
        node.canRequestFocus) {
      NavCapsule.snapNextFrame();
      node.requestFocus();
      MenuPreview.landed(node);
      return;
    }
    if (attempt >= 20) {
      MenuPreview.gaveUp(route);
      return;
    }
    Timer(
      const Duration(milliseconds: 50),
      () => _takeArrival(route, attempt + 1),
    );
  }

  /// Phones keep the avatar on home only, so other routes leave the back
  /// arrow on its own.
  bool get _showAvatar =>
      !PlatformDetection.useMobileUi || _isActive(Destinations.home);

  bool get _showBackArrow => widget.showBackButton && !PlatformDetection.isTV;

  @override
  void didUpdateWidget(covariant TopToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRoute != widget.activeRoute) {
      _previousFocus = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformDetection.useLeanbackUi;
    final isMobile = PlatformDetection.useMobileUi;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final hPad = isTV
        ? _kOverscanH
        : isMobile
        ? 12.0
        : 32.0;
    final vPad = isTV
        ? _kOverscanV
        : isMobile
        ? 8.0
        : 10.0;
    final clockBehavior = _prefs.get(UserPreferences.clockBehavior);
    final showClock =
        clockBehavior == ClockBehavior.always ||
        clockBehavior == ClockBehavior.inMenus;
    final hasEndSection = !isMobile && showClock;
    final startReservedWidth = switch ((_showAvatar, _showBackArrow)) {
      (true, true) => 96.0,
      (false, false) => 0.0,
      _ => 44.0,
    };
    final endReservedWidth = hasEndSection ? 96.0 : 0.0;
    final centerSidePadding =
        math.max(startReservedWidth, endReservedWidth) + 14.0;
    final toolbarHeight = isTV
        ? _kToolbarHeightTV
        : isMobile
        ? _kToolbarHeightMobile
        : _kToolbarHeightDesktop;

    // Kos TV: the music bar under the menu gave way to the floating player.
    final totalHeight = toolbarHeight + TopToolbar.musicBarExtraHeight();

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: totalHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Focus(
            focusNode: _toolbarScopeNode,
            onFocusChange: (hasFocus) {
              _toolbarHadFocus = hasFocus;
              TopToolbar.isFocusedNotifier.value = hasFocus;
            },
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                final primary = FocusManager.instance.primaryFocus;
                if (primary != null) {
                  if (widget.activeRoute != Destinations.home &&
                      NavigationLayout.focusDetailsPlayButtonNotifier.value ==
                          null) {
                    final success = primary.focusInDirection(
                      TraversalDirection.down,
                    );
                    if (success) {
                      final newFocus = FocusManager.instance.primaryFocus;
                      if (newFocus != null && _isInsideToolbar(newFocus)) {
                        return KeyEventResult.handled;
                      }
                    }
                  }
                }
                _restoreFocusBelowToolbar();
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                final primary = FocusManager.instance.primaryFocus;
                if (primary != null) {
                  final insideMusicBar = _isDescendantOf(
                    primary,
                    _musicBarFocusNode,
                  );
                  if (insideMusicBar) {
                    if (_homeFocus.canRequestFocus) {
                      _homeFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    FocusNode? targetNode;
                    for (final n in _toolbarScopeNode.descendants) {
                      if (!n.skipTraversal &&
                          _isLaidOutFocusNode(n) &&
                          !_isDescendantOf(n, _musicBarFocusNode)) {
                        final box =
                            n.context!.findRenderObject() as RenderBox?;
                        final pos = box?.localToGlobal(Offset.zero);
                        if (pos != null && pos.dx > 0) {
                          targetNode = n;
                          break;
                        }
                      }
                    }
                    if (targetNode != null) {
                      targetNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                }
              }
              if ((PlatformDetection.isTV || PlatformDetection.isDesktop) &&
                  event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                      event.logicalKey == LogicalKeyboardKey.arrowRight)) {
                final direction =
                    event.logicalKey == LogicalKeyboardKey.arrowLeft
                    ? TraversalDirection.left
                    : TraversalDirection.right;
                _moveWithinToolbar(direction);
                // Always consume so the key can't escape sideways into content.
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: isLandscape
                      ? SizedBox(
                          height: toolbarHeight - (vPad * 2),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: centerSidePadding,
                                  ),
                                  child: _buildCenter(),
                                ),
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _buildStart(),
                              ),
                              if (!isMobile)
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: _buildEnd(),
                                ),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: toolbarHeight - (vPad * 2),
                          child: Row(
                            children: [
                              _buildStart(),
                              const SizedBox(width: 12),
                              Expanded(child: _buildCenter()),
                              if (!isMobile) ...[
                                const SizedBox(width: 12),
                                _buildEnd(),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStart() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showAvatar)
            MouseRegion(
              onEnter: (_) => setState(() => _startHovered = true),
              onExit: (_) => setState(() => _startHovered = false),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kos TV: on phones the heart has no room beside the
                  // avatar, so the news of favourite series is counted on
                  // the avatar itself (its menu opens «Mis favoritos»).
                  if (PlatformDetection.useMobileUi)
                    ListenableBuilder(
                      listenable: _favoritesNews ?? _neverChanges,
                      builder: (context, _) {
                        final news = _favoritesNews?.unseen ?? 0;
                        final avatar = _buildAvatar();
                        if (news == 0) return avatar;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            avatar,
                            Positioned(
                              top: -3,
                              right: -3,
                              child: IgnorePointer(
                                child: KostvCountBadge(
                                  count: news,
                                  size: _kAvatarSize * 0.42,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    _buildAvatar(),
                  // Kos TV: the requests tray, out while there is news or
                  // something under way, or while on the avatar.
                  KostvRequestsTraySlot(
                    revealed:
                        _avatarFocus.hasFocus ||
                        _trayFocus.hasFocus ||
                        _favoritesFocus.hasFocus ||
                        _startHovered,
                    builder: (context) => Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, event) => _besideAvatarKey(
                          event,
                          left: _avatarFocus,
                          right: _favoritesFocus,
                        ),
                        child: KostvRequestsTrayButton(
                        size: _kAvatarSize,
                        focusNode: _trayFocus,
                        background: _toolbarSurfaceColor(),
                        onPressed: () => showKostvRequestsTray(context),
                        onDown:
                            PlatformDetection.isTV || PlatformDetection.isDesktop
                            ? _restoreFocusBelowToolbar
                            : null,
                      ),
                      ),
                    ),
                  ),
                  // Kos TV: «Mis favoritos», out with the tray while on the
                  // profile (on phones it is in the You menu).
                  if (!PlatformDetection.useMobileUi)
                    ListenableBuilder(
                      listenable: _favoritesNews ?? _neverChanges,
                      builder: (context, _) => KostvFavoritesSlot(
                      revealed:
                          (_favoritesNews?.unseen ?? 0) > 0 ||
                          _avatarFocus.hasFocus ||
                          _trayFocus.hasFocus ||
                          _favoritesFocus.hasFocus ||
                          _startHovered,
                      builder: (context) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (_, event) => _besideAvatarKey(
                            event,
                            left: _trayFocus.context != null
                                ? _trayFocus
                                : _avatarFocus,
                          ),
                          child: KostvFavoritesButton(
                          size: _kAvatarSize,
                          focusNode: _favoritesFocus,
                          background: _toolbarSurfaceColor(),
                          onPressed: () {
                            _openFromMenu(Destinations.allFavorites);
                          },
                          badgeCount: _favoritesNews?.unseen ?? 0,
                          onDown:
                              PlatformDetection.isTV ||
                                  PlatformDetection.isDesktop
                              ? _restoreFocusBelowToolbar
                              : null,
                        ),
                        ),
                      ),
                    ),
                    ),
                ],
              ),
            ),
          if (_showBackArrow) ...[
            if (_showAvatar) const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.popOrHome(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _toolbarSurfaceColor(),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const avatarSize = _kAvatarSize;
    final avatarFocusVisible = InputModeTracker.showFocusVisuals(
      context,
      _avatarFocus.hasFocus,
    );
    // Kos TV: on a TV the focused avatar turns white like the buttons beside
    // it, so its letter goes dark (white on white vanished) and a picture
    // keeps a white ring round it (it covered the white up).
    final tvFocused = avatarFocusVisible && PlatformDetection.isTV;

    return Focus(
      focusNode: _avatarFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _showUserMenu();
          return KeyEventResult.handled;
        }
        if ((PlatformDetection.isTV || PlatformDetection.isDesktop) &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _restoreFocusBelowToolbar();
          return KeyEventResult.handled;
        }
        // Kos TV: on to the requests tray and «Mis favoritos» beside it.
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final next = _trayFocus.context != null
              ? _trayFocus
              : _favoritesFocus.context != null
              ? _favoritesFocus
              : null;
          if (next != null) {
            next.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showUserMenu,
        child: AnimatedScale(
          scale: avatarFocusVisible ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: avatarSize,
            height: avatarSize,
            padding: EdgeInsets.all(tvFocused ? 3 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: (avatarFocusVisible && !PlatformDetection.isTV)
                  ? Border.fromBorderSide(
                      ThemeRegistry.active.borders.focusBorder,
                    )
                  : null,
              color: (avatarFocusVisible && PlatformDetection.isTV)
                  ? Colors.white
                  : null,
            ),
            child: ClipOval(
              child: UserAvatarImage(
                url: _userImageUrl,
                size: avatarSize,
                fallback: _avatarFallback(onWhite: tvFocused),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback({bool onWhite = false}) {
    final user = _userRepo.currentUser;
    final initial = (user?.name.isNotEmpty == true)
        ? user!.name[0].toUpperCase()
        : '?';
    final isMobile = PlatformDetection.useMobileUi;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onWhite ? Colors.white : _kNavbarBackdrop,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: onWhite ? Colors.black87 : Colors.white,
          fontSize: isMobile ? 18 : 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showUserMenu() {
    showUserMenu(context);
  }

  Widget _buildCenter() {
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    final showGenres = _prefs.get(UserPreferences.showGenresButton);
    // Checked alongside the show* preferences, never written into them, since
    // those sync and would follow the account to the parent's other devices.
    final kidsMode = _kidsMode;
    final showLiveTv = _showLiveTvButton;
    final navLibraries = _navLibraries;
    final showLibraries =
        !kidsMode && _prefs.get(UserPreferences.showLibrariesInToolbar);
    final showLibrariesIndividually =
        _prefs.get(UserPreferences.showLibrariesIndividually);
    final alwaysExpanded = _prefs.get(UserPreferences.navbarAlwaysExpanded);
    final showSyncPlay =
        !kidsMode &&
        _prefs.get(UserPreferences.syncPlayEnabled) &&
        _prefs.get(UserPreferences.showSyncPlayButton);
    final showCalendar =
        !kidsMode &&
        _prefs.get(UserPreferences.showCalendarButton) &&
        GetIt.instance<PluginSyncService>().calendarAvailable;
    // Kos TV: the TV's apps (All apps screen), on a TV with apps to list.
    final showApps = showKostvAppsButton(_prefs);
    final l10n = AppLocalizations.of(context);

    int order = 1;
    var navSlot = 0;
    Color? nextNavColor() {
      final c = AppColorScheme.navColorForSlot(navSlot);
      if (c != null) navSlot += 1;
      return c;
    }

    return _anchorPill(
      // What changes how many buttons there are, so the bar's width at rest
      // is measured again.
      [
        showGenres,
        showLiveTv,
        showLibraries,
        showLibrariesIndividually,
        alwaysExpanded,
        showSyncPlay,
        showCalendar,
        showApps,
        kidsMode,
        _prefs.get(UserPreferences.kostvMyListAvailable),
        _prefs.get(UserPreferences.kostvShowMusicButton),
        showKostvDiscoverButton(_prefs, kidsMode: kidsMode),
        navLibraries.length,
        l10n.localeName,
      ].join(','),
      _wrapPill(
        isNeon: isNeon,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _withCapsule(Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _orderButton(
                order: (order++).toDouble(),
                child: ExpandableIconButton(
                  key: const ValueKey('toolbar_home'),
                  forceExpanded: alwaysExpanded,
                  icon: Icons.home_rounded,
                  label: l10n.home,
                  baseColor: nextNavColor(),
                  focusNode: _homeFocus,
                  onFocusChanged: (f) => _restOn(Destinations.home, f),
                  onPressed: () {
                    if (_enterShownPage(Destinations.home)) return;
                    if (_isActive(Destinations.home)) {
                      homeRefreshBus.request(newMediaBar: true);
                      return;
                    }
                    homeRefreshBus.requestAfterNavigation();
                    MenuPreview.open(context, Destinations.home);
                  },
                ),
              ),
              _gap(),
              _orderButton(
                order: (order++).toDouble(),
                child: ExpandableIconButton(
                  key: const ValueKey('toolbar_search'),
                  focusNode: _menuNode(Destinations.search),
                  onFocusChanged: (f) => _restOn(Destinations.search, f),
                  forceExpanded: alwaysExpanded,
                  icon: Icons.search_rounded,
                  label: l10n.search,
                  baseColor: nextNavColor(),
                  onPressed: () {
                    if (_enterShownPage(Destinations.search)) return;
                    _openFromMenu(Destinations.search);
                  },
                ),
              ),
              // Kos TV: what's on the streaming platforms.
              if (showKostvDiscoverButton(_prefs, kidsMode: kidsMode)) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_kostv_discover'),
                    focusNode: _menuNode(Destinations.kostvDiscover),
                    onFocusChanged: (f) => _restOn(Destinations.kostvDiscover, f),
                    forceExpanded: alwaysExpanded,
                    icon: Icons.explore_rounded,
                    label: l10n.kostvDiscover,
                    baseColor: nextNavColor(),
                    onPressed: () {
                      if (_enterShownPage(Destinations.kostvDiscover)) return;
                      _openFromMenu(Destinations.kostvDiscover);
                    },
                  ),
                ),
              ],
              if (showGenres) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_genres'),
                    focusNode: _menuNode(Destinations.allGenres),
                    onFocusChanged: (f) => _restOn(Destinations.allGenres, f),
                    forceExpanded: alwaysExpanded,
                    baseColor: nextNavColor(),
                    iconBuilder: (size, color) => Image.asset(
                      'assets/icons/genres.png',
                      width: size,
                      height: size,
                      color: color,
                      fit: BoxFit.contain,
                    ),
                    label: l10n.genres,
                    onPressed: () {
                      _openFromMenu(Destinations.allGenres);
                    },
                  ),
                ),
              ],
              // Kos TV: the person's list. Favourites is on the profile.
              if (_prefs.get(UserPreferences.kostvMyListAvailable)) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_my_list'),
                    focusNode: _menuNode(Destinations.myList),
                    onFocusChanged: (f) => _restOn(Destinations.myList, f),
                    forceExpanded: alwaysExpanded,
                    icon: Icons.bookmark_rounded,
                    label: l10n.kostvMyList,
                    baseColor: nextNavColor(),
                    onPressed: () {
                      if (_enterShownPage(Destinations.myList)) return;
                      _openFromMenu(Destinations.myList);
                    },
                  ),
                ),
              ],
              // Kos TV: Music, the page of its own.
              if (_prefs.get(UserPreferences.kostvShowMusicButton)) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_music'),
                    focusNode: _menuNode(Destinations.kostvMusic),
                    onFocusChanged: (f) => _restOn(Destinations.kostvMusic, f),
                    forceExpanded: alwaysExpanded,
                    icon: Icons.music_note_rounded,
                    label: l10n.kostvMusic,
                    baseColor: nextNavColor(),
                    onPressed: () {
                      if (_enterShownPage(Destinations.kostvMusic)) return;
                      _openFromMenu(Destinations.kostvMusic);
                    },
                  ),
                ),
              ],
              // Kos TV: while music sounds, «Reproduciendo» opens its player.
              _nowPlayingButton(
                order: (order++).toDouble(),
                alwaysExpanded: alwaysExpanded,
                color: nextNavColor(),
              ),
              if (showLiveTv) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_livetv'),
                    focusNode: _menuNode(Destinations.liveTvGuide),
                    onFocusChanged: (f) => _restOn(Destinations.liveTvGuide, f),
                    forceExpanded: alwaysExpanded,
                    icon: Icons.live_tv_rounded,
                    label: l10n.liveTv,
                    baseColor: nextNavColor(),
                    onPressed: () {
                      _openFromMenu(Destinations.liveTvGuide);
                    },
                  ),
                ),
              ],
              if (showSyncPlay) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_syncplay'),
                    forceExpanded: alwaysExpanded,
                    icon: Icons.groups_rounded,
                    label: l10n.watchParties,
                    baseColor: nextNavColor(),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => watchTogetherScreen(),
                      ),
                    ),
                  ),
                ),
              ],
              if (showCalendar) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_calendar'),
                    focusNode: _menuNode(Destinations.calendar),
                    onFocusChanged: (f) => _restOn(Destinations.calendar, f),
                    forceExpanded: alwaysExpanded,
                    baseColor: nextNavColor(),
                    icon: Icons.calendar_month_rounded,
                    label: l10n.calendar,
                    onPressed: () {
                      if (_enterShownPage(Destinations.calendar)) return;
                      _openFromMenu(Destinations.calendar);
                    },
                  ),
                ),
              ],
              if (showApps) ...[
                _gap(),
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_apps'),
                    focusNode: _menuNode(Destinations.apps),
                    onFocusChanged: (f) => _restOn(Destinations.apps, f),
                    forceExpanded: alwaysExpanded,
                    baseColor: nextNavColor(),
                    icon: Icons.apps_rounded,
                    label: l10n.kostvAppsRow,
                    onPressed: () {
                      if (_enterShownPage(Destinations.apps)) return;
                      _openFromMenu(Destinations.apps);
                    },
                  ),
                ),
              ],
              if (showLibraries && showLibrariesIndividually)
                for (final lib in navLibraries) ...[
                  _gap(),
                  _orderButton(
                    order: (order++).toDouble(),
                    child: ExpandableIconButton(
                      // Two servers can share a library id, so the key is the
                      // library itself.
                      key: ObjectKey(lib),
                      forceExpanded: alwaysExpanded,
                      icon: libraryIcon(lib),
                      label: lib.name,
                      baseColor: nextNavColor(),
                      onPressed: () => _openLibrary(lib),
                    ),
                  ),
                ]
              else if (showLibraries && navLibraries.isNotEmpty) ...[
                _gap(),
                // Kos TV: one of the menu's pages, the libraries on it,
                // instead of a list unfolding from the button.
                _orderButton(
                  order: (order++).toDouble(),
                  child: ExpandableIconButton(
                    key: const ValueKey('toolbar_libraries'),
                    focusNode: _menuNode(Destinations.kostvLibraries),
                    onFocusChanged: (f) =>
                        _restOn(Destinations.kostvLibraries, f),
                    forceExpanded: alwaysExpanded,
                    baseColor: nextNavColor(),
                    iconBuilder: (size, color) => Image.asset(
                      'assets/icons/clapperboard.png',
                      width: size,
                      height: size,
                      color: color,
                      fit: BoxFit.contain,
                    ),
                    label: l10n.libraries,
                    onPressed: () {
                      _openFromMenu(Destinations.kostvLibraries);
                    },
                  ),
                ),
              ],
              _gap(),
              if (DownloadsNavSlot.isOffered())
                _orderButton(
                  order: 97,
                  // The slot is taken here rather than inside the builder, so
                  // the icons after it keep their colour whether or not
                  // anything is saved to show.
                  child: _buildDownloadsButton(
                    navColor: nextNavColor(),
                    alwaysExpanded: alwaysExpanded,
                    label: l10n.savedMedia,
                  ),
                ),
              if (FriendsNavSlot.isOffered() && _friendsAvailable)
                _orderButton(
                  order: 97.5,
                  // Only taken where the plugin has friends on, so on every
                  // other server the icons after it keep their color.
                  child: _buildFriendsButton(
                    navColor: nextNavColor(),
                    alwaysExpanded: alwaysExpanded,
                    label: l10n.friends,
                  ),
                ),
              if (_prefs.get(UserPreferences.showServerMessagesButton))
                _orderButton(
                  order: 98,
                  // The slot is taken here rather than inside the builder, so the
                  // settings icon keeps its colour whether or not there are any
                  // messages to show.
                  child: _buildServerMessagesButton(
                    navColor: nextNavColor(),
                    alwaysExpanded: alwaysExpanded,
                    label: l10n.serverMessages,
                  ),
                ),
              _orderButton(
                order: 99,
                child: ExpandableIconButton(
                  key: const ValueKey('toolbar_settings'),
                  forceExpanded: alwaysExpanded,
                  icon: Icons.settings_rounded,
                  label: l10n.settings,
                  baseColor: nextNavColor(),
                  focusNode: _settingsFocus,
                  onKeyEvent: (_, event) {
                    final isRtl =
                        Directionality.of(context) == TextDirection.rtl;
                    final outwardKey = isRtl
                        ? LogicalKeyboardKey.arrowLeft
                        : LogicalKeyboardKey.arrowRight;
                    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                        PlatformDetection.isTV &&
                        event.logicalKey == outwardKey) {
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  onPressed: () async {
                    await SettingsPanel.open(
                      context,
                      const SettingsSidePanel(),
                    );
                    if (mounted) _settingsFocus.requestFocus();
                  },
                ),
              ),
            ],
          )),
        ),
      ),
    );
  }

  /// Kos TV: the menu's glass capsule behind the buttons, with a remote, a
  /// keyboard or a mouse. Touch screens keep each button's own look.
  Widget _withCapsule(Widget buttons) => PlatformDetection.useMobileUi
      ? buttons
      : NavCapsule(
          key: _capsuleKey,
          color: AppColorScheme.onSurface,
          child: buttons,
        );

  final _capsuleKey = GlobalKey<NavCapsuleState>();

  /// The bar's width with no label open, for [_PillAnchor], by what sets
  /// its buttons: shared by every toolbar, so a page the menu brings in
  /// places its bar exactly where the one it covers was.
  static final _restWidths = <String, double>{};
  String _pillRestSignature = '';

  double? get _pillRestWidth => _restWidths[_pillRestSignature];
  set _pillRestWidth(double? width) {
    if (width == null) {
      _restWidths.remove(_pillRestSignature);
    } else {
      _restWidths[_pillRestSignature] = width;
    }
  }

  /// Kos TV: the bar sits centred, but while the menu is in use it keeps its
  /// left edge where it was, so opening labels push the buttons after them
  /// instead of swaying the whole bar.
  Widget _anchorPill(String signature, Widget pill) {
    if (PlatformDetection.useMobileUi) return Center(child: pill);
    _pillRestSignature = signature;
    return CustomSingleChildLayout(
      delegate: _PillAnchor(this),
      child: pill,
    );
  }

  Widget _wrapPill({required bool isNeon, required Widget child}) {
    if (AppColorScheme.isGlass) {
      return GlassSurface(
        cornerRadius: _kPillRadius,
        fallbackColor: Colors.transparent,
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: AppRadius.circular(_kPillRadius),
      child: Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _toolbarSurfaceColor(),
          borderRadius: AppRadius.circular(_kPillRadius),
          border: isNeon
              ? Border.fromBorderSide(
                  ThemeRegistry.active.borders.chipBorder.copyWith(
                    color: AppColorScheme.accent,
                    width: 1.0,
                  ),
                )
              : null,
          boxShadow: isNeon
              ? const [BoxShadow(color: Color(0x33FF2E92), blurRadius: 6)]
              : null,
        ),
        child: child,
      ),
    );
  }

  void _openLibrary(AggregatedLibrary lib) {
    context.navigateTopLevel(
      libraryRoute(
        lib.id,
        lib.collectionType,
        lib.name,
        serverId: lib.serverId,
      ),
    );
  }

  /// The messages button, or nothing when there is nothing to show. The nav
  /// colour is passed in so the caller decides which palette slot it takes.
  /// The gap to the next button travels with it, so it only takes up room when
  /// the button is there.
  Widget _buildServerMessagesButton({
    required Color? navColor,
    required bool alwaysExpanded,
    required String label,
  }) {
    return ServerMessagesNavSlot(
      builder: (context, unread) => Row(
        mainAxisSize: MainAxisSize.min,
        // Stretch like the bare buttons, or the hover pill stops short of the
        // bar's height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpandableIconButton(
            key: const ValueKey('toolbar_server_messages'),
            forceExpanded: alwaysExpanded,
            icon: Icons.info_outline_rounded,
            label: label,
            baseColor: navColor,
            badgeCount: unread,
            focusNode: _serverMessagesFocus,
            onPressed: () async {
              await showServerMessagesDialog(context);
              if (mounted) _serverMessagesFocus.requestFocus();
            },
          ),
          _gap(),
        ],
      ),
    );
  }

  /// The friends button, or nothing when the server has no friends feature.
  /// The gap to the next button travels with it, like the messages button.
  Widget _buildFriendsButton({
    required Color? navColor,
    required bool alwaysExpanded,
    required String label,
  }) {
    return FriendsNavSlot(
      builder: (context, badge) => Row(
        mainAxisSize: MainAxisSize.min,
        // Stretch like the bare buttons, or the hover pill stops short of the
        // bar's height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpandableIconButton(
            key: const ValueKey('toolbar_friends'),
            forceExpanded: alwaysExpanded,
            icon: Icons.people_alt_rounded,
            label: label,
            baseColor: navColor,
            badgeCount: badge,
            focusNode: _friendsFocus,
            onPressed: () async {
              await FriendsNavSlot.open(context);
              if (mounted) _friendsFocus.requestFocus();
            },
          ),
          _gap(),
        ],
      ),
    );
  }

  Widget _buildEnd() {
    final clockBehavior = _prefs.get(UserPreferences.clockBehavior);
    final showClock =
        clockBehavior == ClockBehavior.always ||
        clockBehavior == ClockBehavior.inMenus;
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;

    if (!showClock) return const SizedBox.shrink();

    return ValueListenableBuilder<String>(
      valueListenable: _currentTime,
      builder: (context, time, _) {
        return Text(
          time,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: isNeon
                ? AppColorScheme.onSurface
                : Colors.white.withValues(alpha: 0.9),
            fontSize: 22,
            fontWeight: FontWeight.w500,
            shadows: isNeon
                ? const [Shadow(color: Color(0x6600E5FF), blurRadius: 8)]
                : null,
          ),
        );
      },
    );
  }

  Widget _nowPlayingButton({
    required double order,
    required bool alwaysExpanded,
    required Color? color,
  }) => ListenableBuilder(
    listenable: KostvNowPlaying.instance..ensureStarted(),
    builder: (context, _) {
      final music = KostvNowPlaying.instance;
      if (music.item == null) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _gap(),
          _orderButton(
            order: order,
            child: ExpandableIconButton(
              key: const ValueKey('toolbar_now_playing'),
              focusNode: _menuNode(Destinations.audioPlayer),
              forceExpanded: alwaysExpanded,
              iconBuilder: (size, color) => KostvEqualizerBars(
                playing: music.playing,
                size: size * 0.8,
                color: kostvMusicColor,
              ),
              label: AppLocalizations.of(context).kostvNowPlaying,
              baseColor: color,
              onPressed: () => context.push(Destinations.audioPlayer),
            ),
          ),
        ],
      );
    },
  );

  Widget _gap() => SizedBox(
    width: PlatformDetection.useLeanbackUi
        ? _kButtonSpacingTV
        : PlatformDetection.useMobileUi
        ? _kButtonSpacingMobile
        : _kButtonSpacing,
  );

  Widget _orderButton({required double order, required Widget child}) {
    return FocusTraversalOrder(order: NumericFocusOrder(order), child: child);
  }
}

class TopMusicBar extends StatefulWidget {
  final FocusNode? focusNode;
  const TopMusicBar({super.key, this.focusNode});

  @override
  State<TopMusicBar> createState() => _TopMusicBarState();
}

class _TopMusicBarState extends State<TopMusicBar> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _clientFactory = GetIt.instance<MediaServerClientFactory>();
  StreamSubscription? _playSub;
  StreamSubscription? _queueSub;

  @override
  void initState() {
    super.initState();
    _playSub = _manager.state.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
    _queueSub = _manager.queueService.queueChangedStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _playSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  AggregatedItem? get _currentItem {
    final raw = _manager.queueService.currentItem;
    return raw is AggregatedItem ? raw : null;
  }

  String? _artUrl(AggregatedItem item) =>
      audioArtUrl(item, clientFactory: _clientFactory, maxHeight: 120);

  Widget _buildBarButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (isActivateKey(event)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = InputModeTracker.showFocusVisuals(
            context,
            Focus.of(context).hasFocus,
          );
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused ? AppColorScheme.onSurface : Colors.transparent,
              ),
              child: AdaptiveIcon(
                icon,
                size: 20,
                color: focused
                    ? AppColorScheme.surface
                    : AppColorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _wrapPill({required bool isNeon, required Widget child}) {
    final border = isNeon
        ? Border.all(
            color: const Color(0xFF00F0FF), // cyan outline for Neon Pulse!
            width: 1.5,
          )
        : Border.all(
            color: AppColorScheme.onSurface.withValues(alpha: 0.15),
            width: 1.0,
          );
    if (AppColorScheme.isGlass) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.circular(24),
          border: border,
        ),
        child: GlassSurface(
          cornerRadius: 24,
          reinforced: true,
          fallbackColor: Colors.transparent,
          child: child,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color:
            OverlayColorPalette.resolveColor(
              GetIt.instance<UserPreferences>().get(
                UserPreferences.navbarColor,
              ),
            ).withValues(
              alpha:
                  GetIt.instance<UserPreferences>().get(
                    UserPreferences.navbarOpacity,
                  ) /
                  100.0,
            ),
        borderRadius: AppRadius.circular(24),
        border: border,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    if (item == null || !item.isAudioLike) {
      return const SizedBox.shrink();
    }

    final isPlaying = _manager.state.isPlaying;
    final artUrl = _artUrl(item);
    final artist = item.artists.isNotEmpty
        ? item.artists.join(', ')
        : item.albumArtist ?? '';
    final displayText = artist.isNotEmpty
        ? '${item.name} - $artist'
        : item.name;
    final titleStyle = TextStyle(
      color: AppColorScheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    // The text already grows with the UI scale, so the cap on it does too.
    final titleMaxWidth =
        _kMusicBarTitleMaxWidth *
        GetIt.instance<UserPreferences>()
            .get(UserPreferences.desktopUiScale)
            .scaleFactor;
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;

    return Center(
      child: _wrapPill(
        isNeon: isNeon,
        child: Focus(
          focusNode: widget.focusNode,
          canRequestFocus: false,
          child: FocusTraversalGroup(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.circular(6),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: artUrl != null
                          ? OfflineAwareImage(
                              imageUrl: artUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColorScheme.onSurface.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                Icons.music_note,
                                size: 16,
                                color: AppColorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Focusable, not just tappable: a remote cannot tap, and
                  // this title is the only way back to the player. Same focus
                  // treatment as the transport buttons beside it.
                  Flexible(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (isActivateKey(event)) {
                          appRouter.push(Destinations.audioPlayer);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final focused = InputModeTracker.showFocusVisuals(
                            context,
                            Focus.of(context).hasFocus,
                          );
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () =>
                                  appRouter.push(Destinations.audioPlayer),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.circular(12),
                                  color: focused
                                      ? AppColorScheme.onSurface.withValues(
                                          alpha: 0.22,
                                        )
                                      : Colors.transparent,
                                ),
                                child: PlatformDetection.useMobileUi
                                    ? Text(
                                        displayText,
                                        style: titleStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: titleMaxWidth,
                                        ),
                                        child: MarqueeText(
                                          text: displayText,
                                          style: titleStyle,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  _buildBarButton(
                    icon: Icons.skip_previous,
                    onPressed: _manager.previous,
                  ),
                  const SizedBox(width: 4),
                  _buildBarButton(
                    icon: isPlaying ? Icons.pause : Icons.play_arrow,
                    onPressed: isPlaying ? _manager.pause : _manager.resume,
                  ),
                  const SizedBox(width: 4),
                  _buildBarButton(
                    icon: Icons.skip_next,
                    onPressed: _manager.next,
                  ),
                  const SizedBox(width: 4),
                  _buildBarButton(
                    icon: Icons.stop,
                    onPressed: () =>
                        unawaited(_manager.stop(userInitiated: true)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kos TV: places the menu's bar: centred at rest, and while the menu is in
/// use (or its labels are still folding away) with its left edge where it
/// was at rest, as far as it fits.
class _PillAnchor extends SingleChildLayoutDelegate {
  _PillAnchor(this.toolbar);

  final _TopToolbarState toolbar;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = (size.height - childSize.height) / 2;
    final engaged = toolbar._capsuleKey.currentState?.engaged ?? false;
    final rest = toolbar._pillRestWidth;
    if (!engaged && (rest == null || childSize.width <= rest + 0.5)) {
      toolbar._pillRestWidth = childSize.width;
      return Offset((size.width - childSize.width) / 2, top);
    }
    final restWidth = rest ?? childSize.width;
    toolbar._pillRestWidth = restWidth;
    final room = math.max(0.0, size.width - childSize.width);
    final left = ((size.width - restWidth) / 2).clamp(0.0, room).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PillAnchor old) => true;
}
