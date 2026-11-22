import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../util/focus/row_focus_coordinator.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/book/book_navigation.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/focus/can_claim_initial_focus.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/settings/settings_preview_scope.dart';
import '../../widgets/top_toolbar.dart';

/// The app's navbar around a library page, which the settings preview draws
/// itself.
Widget libraryNavigation(
  BuildContext context, {
  required String activeRoute,
  required Widget child,
}) => inSettingsPreview(context)
    ? child
    : NavigationLayout(
        activeRoute: activeRoute,
        showBackButton: true,
        child: child,
      );

/// What every library page built from D-pad stops shares: the stops, the
/// sections they sit in and the app's chrome around them.
abstract class LibraryPageState<T extends StatefulWidget> extends State<T> {
  String get libraryId;

  /// Starts the debug label of every focus node the page makes.
  String get focusLabel;

  /// The route the navbar marks as the one showing.
  String get activeRoute;

  /// Shown in place of the page until it loads. Without one the content
  /// draws its own loading state.
  Widget? get loadingPlaceholder => null;

  bool get isLoading;

  final coordinator = RowFocusCoordinator();
  final scrollController = ScrollController();

  // Never attached. As the initial focus target it keeps RequestInitialFocus
  // from parking focus in the sidebar before the content loads, and
  // contentChanged lands focus on the content once it does.
  final initialFocusNode = FocusNode(debugLabel: 'libraryInitialContent');
  bool _landedOnContent = false;

  /// The coordinator index of the header. Focus first lands on the stop
  /// under it.
  int headerIndex = -1;

  final _nodes = <String, FocusNode>{};
  List<RowFocusEntry> _entries = [];
  List<Widget> _sections = [];
  final _rowKeys = <String, GlobalKey<LockedFocusRowState>>{};
  final _sectionKeys = <String, GlobalKey>{};

  bool get wide => !PlatformDetection.useMobileUi;

  /// Where the page's own header starts: below the top bar on a TV and a
  /// computer, below the status bar on phones (whose bar is at the bottom).
  double get topReserve =>
      MediaQuery.paddingOf(context).top +
      (NavigationLayout.usesBottomNavbar ? 56 : TopToolbar.heightFor(context));

  @override
  void dispose() {
    scrollController.dispose();
    initialFocusNode.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Rebuilds for new content, and lands focus on it once it first shows.
  void contentChanged() {
    if (!mounted) return;
    setState(() {});
    if (!wide || isLoading || inSettingsPreview(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          isLoading ||
          !canClaimInitialFocus(context) ||
          TopToolbar.isFocusedNotifier.value) {
        return;
      }
      // The first load lands under the header. After that, an update only
      // steps in when a rebuild took the focused stop away, never while the
      // viewer is somewhere on the page.
      if (_landedOnContent && !bookFocusIsLost) return;
      _landedOnContent = true;
      focusContent();
    });
  }

  /// Focuses the first stop under the header.
  void focusContent() {
    if (!coordinator.moveVertical(fromIndex: headerIndex, isUp: false)) {
      coordinator.focusFirst();
    }
  }

  FocusNode node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: '$focusLabel:$id'));

  GlobalKey<LockedFocusRowState> rowKey(String id) =>
      _rowKeys.putIfAbsent(id, GlobalKey<LockedFocusRowState>.new);

  GlobalKey sectionKey(String id) => _sectionKeys.putIfAbsent(id, GlobalKey.new);

  bool move(int fromIndex, bool isUp) =>
      moveBookFocus(coordinator, fromIndex, isUp);

  /// The page in the app's chrome, behind [loadingPlaceholder] until its
  /// content arrives.
  Widget buildPage(Widget Function() content) => RequestInitialFocus(
    targetNode: initialFocusNode,
    child: Scaffold(
      backgroundColor: AppColorScheme.background,
      body: libraryNavigation(
        context,
        activeRoute: activeRoute,
        child: isLoading && loadingPlaceholder != null
            ? loadingPlaceholder!
            : content(),
      ),
    ),
  );

  /// The sections [addSections] adds, in a list that pulls to refresh. A
  /// [header] stays above the list, and adds its stops before the list's.
  /// [body] places the list beside anything else the page shows, which
  /// keeps [bottom] clear for the bottom navbar too.
  Widget buildSections(
    VoidCallback addSections, {
    required Future<void> Function() onRefresh,
    Widget Function()? header,
    Widget Function(Widget list, double bottom)? body,
  }) => BottomNavPadded(
    fallback: 120,
    builder: (_, bottom) {
      _entries = [];
      _sections = [];
      final top = header?.call();
      addSections();
      coordinator.entries = _entries;
      Widget list = RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.only(bottom: bottom + 24),
          children: _sections,
        ),
      );
      if (body != null) list = body(list, bottom);
      if (top == null) return list;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [top, Expanded(child: list)],
      );
    },
  );

  /// Adds a D-pad stop to the page and returns its coordinator index.
  int addStop(RowFocusEntry entry) {
    _entries.add(entry);
    return _entries.length - 1;
  }

  void addSection(Widget section) => _sections.add(section);
}
