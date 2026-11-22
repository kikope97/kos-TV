import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/bottom_nav_tabs.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../navigation/kostv_menu_controller.dart';
import '../../screens/discover/kostv_requests_tray.dart';
import '../../screens/downloads/downloads_panel.dart';
import '../../screens/settings/settings_side_panel.dart';
import '../../screens/watch_party/watch_together_route.dart';
import '../friends_nav_slot.dart';
import '../music/design/kostv_music_tokens.dart';
import '../overlay_sheet.dart';
import '../remote_control_dialog.dart';
import '../server_messages_dialog.dart';
import '../settings/settings_panel.dart';
import '../user_menu_dialog.dart';
import 'kostv_nav_avatar.dart';

/// Kos TV: one thing the menu offers in «Más» or in «Tú».
class KostvMenuEntry {
  const KostvMenuEntry({
    required this.id,
    required this.label,
    required this.onSelected,
    this.icon,
    this.iconBuilder,
    this.count = 0,
    this.detail,
    this.separatorBefore = false,
  });

  final String id;
  final String label;
  final IconData? icon;

  /// For artwork icons (Genres, Libraries), drawn at a size in a colour.
  final Widget Function(double size, Color color)? iconBuilder;

  /// News behind it, as a pink count.
  final int count;

  /// A quiet word at the end of the row («3 novedades», «4»).
  final String? detail;

  /// A thin line above it, between groups.
  final bool separatorBefore;

  /// Run once whatever showed the entry has closed.
  final void Function(BuildContext context) onSelected;

  Widget iconWidget(double size, Color color) =>
      iconBuilder?.call(size, color) ?? Icon(icon, size: size, color: color);
}

Widget _genresIcon(double size, Color color) => Image.asset(
  'assets/icons/genres.png',
  width: size,
  height: size,
  color: color,
  fit: BoxFit.contain,
);

Widget _librariesIcon(double size, Color color) => Image.asset(
  'assets/icons/clapperboard.png',
  width: size,
  height: size,
  color: color,
  fit: BoxFit.contain,
);

/// Opens one of the menu's pages the way the bar in use does.
typedef KostvOpenPage = void Function(BuildContext context, String route);

/// Kos TV: what «Más» holds on a TV and a computer: Géneros, Calendario and
/// Aplicaciones (on the TV only), then whatever else the person turned on
/// (watching together, downloads, friends, the server's messages).
List<KostvMenuEntry> kostvMoreEntries(
  AppLocalizations l10n,
  KostvMenuController menu, {
  required KostvOpenPage openPage,
}) => [
  if (menu.shows(BottomNavTab.genres))
    KostvMenuEntry(
      id: 'genres',
      label: l10n.genres,
      iconBuilder: _genresIcon,
      onSelected: (c) => openPage(c, Destinations.allGenres),
    ),
  if (menu.shows(BottomNavTab.calendar))
    KostvMenuEntry(
      id: 'calendar',
      label: l10n.calendar,
      icon: Icons.calendar_month_rounded,
      onSelected: (c) => openPage(c, Destinations.calendar),
    ),
  if (menu.showApps)
    KostvMenuEntry(
      id: 'apps',
      label: l10n.kostvAppsRow,
      icon: Icons.apps_rounded,
      onSelected: (c) => openPage(c, Destinations.apps),
    ),
  ..._extras(l10n, menu),
];

List<KostvMenuEntry> _extras(
  AppLocalizations l10n,
  KostvMenuController menu,
) => [
  if (menu.showSyncPlay)
    KostvMenuEntry(
      id: 'watchParties',
      label: l10n.watchParties,
      icon: Icons.groups_rounded,
      onSelected: (c) => Navigator.of(c)
          .push(MaterialPageRoute<void>(builder: (_) => watchTogetherScreen())),
    ),
  if (menu.savedVisible)
    KostvMenuEntry(
      id: 'saved',
      label: l10n.savedMedia,
      icon: Icons.download_for_offline_rounded,
      onSelected: showDownloadsDialog,
    ),
  if (menu.friendsVisible)
    KostvMenuEntry(
      id: 'friends',
      label: l10n.friends,
      icon: Icons.people_alt_rounded,
      count: menu.friendsBadge,
      onSelected: FriendsNavSlot.open,
    ),
  if (menu.messagesVisible)
    KostvMenuEntry(
      id: 'messages',
      label: l10n.serverMessages,
      icon: Icons.info_outline_rounded,
      count: menu.unreadMessages,
      onSelected: showServerMessagesDialog,
    ),
];

KostvMenuEntry _requests(AppLocalizations l10n, KostvMenuController menu) =>
    KostvMenuEntry(
      id: 'requests',
      label: l10n.kostvMenuMyRequests,
      icon: Icons.inbox_rounded,
      count: menu.requestsNews,
      detail: menu.requestsNews > 0
          ? l10n.kostvMenuNews(menu.requestsNews)
          : null,
      onSelected: (c) => unawaited(showKostvRequestsTray(c)),
    );

KostvMenuEntry _favorites(
  AppLocalizations l10n,
  KostvMenuController menu,
  KostvOpenPage openPage,
) => KostvMenuEntry(
  id: 'favorites',
  label: l10n.kostvMyFavorites,
  icon: Icons.favorite_rounded,
  count: menu.favoritesNews,
  detail: menu.favoritesNews > 0
      ? l10n.kostvMenuNews(menu.favoritesNews)
      : null,
  onSelected: (c) => openPage(c, Destinations.allFavorites),
);

KostvMenuEntry _switchPerson(AppLocalizations l10n, {bool separator = false}) =>
    KostvMenuEntry(
      id: 'switchPerson',
      label: l10n.kostvMenuSwitchPerson,
      icon: Icons.swap_vert_rounded,
      separatorBefore: separator,
      onSelected: showUserMenu,
    );

KostvMenuEntry _settings(AppLocalizations l10n) => KostvMenuEntry(
  id: 'settings',
  label: l10n.settings,
  icon: Icons.settings_rounded,
  onSelected: (c) => SettingsPanel.open(c, const SettingsSidePanel()),
);

/// Kos TV: what «Tú» (the avatar) holds on a TV and a computer: the person's
/// requests and favourites, then switching person and Ajustes.
List<KostvMenuEntry> kostvYouEntries(
  AppLocalizations l10n,
  KostvMenuController menu, {
  required KostvOpenPage openPage,
}) => [
  if (menu.requestsVisible) _requests(l10n, menu),
  _favorites(l10n, menu, openPage),
  _switchPerson(l10n, separator: true),
  _settings(l10n),
];

/// Kos TV: what the phone's «Más» sheet holds (long press on «Tú»): every
/// destination that isn't on the bar, as tiles, then the person's rows.
({List<KostvMenuEntry> tiles, List<KostvMenuEntry> rows}) kostvPhoneMoreEntries(
  AppLocalizations l10n,
  KostvMenuController menu, {
  required KostvOpenPage openPage,
}) {
  final onBar = {
    for (final item in menu.barItems())
      if (item.tab != null) item.tab!,
  };
  KostvMenuEntry? tab(
    BottomNavTab tab,
    String id,
    String label,
    String route, {
    IconData? icon,
    Widget Function(double, Color)? iconBuilder,
  }) {
    if (onBar.contains(tab) || !menu.shows(tab)) return null;
    return KostvMenuEntry(
      id: id,
      label: label,
      icon: icon,
      iconBuilder: iconBuilder,
      onSelected: (c) => openPage(c, route),
    );
  }

  final tiles = <KostvMenuEntry?>[
    tab(
      BottomNavTab.libraries,
      'libraries',
      l10n.libraries,
      Destinations.kostvLibraries,
      iconBuilder: _librariesIcon,
    ),
    tab(
      BottomNavTab.genres,
      'genres',
      l10n.genres,
      Destinations.allGenres,
      iconBuilder: _genresIcon,
    ),
    tab(
      BottomNavTab.liveTv,
      'liveTv',
      l10n.liveTv,
      Destinations.liveTvGuide,
      icon: Icons.live_tv_rounded,
    ),
    tab(
      BottomNavTab.calendar,
      'calendar',
      l10n.calendar,
      Destinations.calendar,
      icon: Icons.calendar_month_rounded,
    ),
    tab(
      BottomNavTab.myList,
      'myList',
      l10n.kostvMyList,
      Destinations.myList,
      icon: Icons.bookmark_rounded,
    ),
    tab(
      BottomNavTab.kostvDiscover,
      'discover',
      l10n.kostvDiscover,
      Destinations.kostvDiscover,
      icon: Icons.explore_rounded,
    ),
    tab(
      BottomNavTab.kostvMusic,
      'music',
      l10n.kostvMusic,
      Destinations.kostvMusic,
      icon: Icons.music_note_rounded,
    ),
    if (menu.requestsVisible) _requests(l10n, menu),
    _favorites(l10n, menu, openPage),
    ..._extras(l10n, menu),
    if (menu.quickConnectVisible)
      KostvMenuEntry(
        id: 'quickConnect',
        label: KostvMenuController.activeServerIsSilo
            ? l10n.siloApproveSignIn
            : l10n.quickConnect,
        icon: Icons.devices_rounded,
        onSelected: showQuickConnectCodeDialog,
      ),
    if (menu.remoteControlVisible)
      KostvMenuEntry(
        id: 'remoteControl',
        label: l10n.remoteControl,
        icon: Icons.settings_remote_rounded,
        onSelected: showRemoteControlDialog,
      ),
  ];
  return (
    tiles: [for (final t in tiles) ?t],
    rows: [_switchPerson(l10n), _settings(l10n)],
  );
}

/// Kos TV: the card «Más» and «Tú» open in on a TV and a computer, under the
/// button that opened it, over the page dimmed. With a remote the first row
/// takes the focus; Back (or a click outside) closes it and the focus goes
/// back to the button.
Future<void> showKostvMenuPopup({
  required BuildContext context,
  required Rect anchor,
  required List<KostvMenuEntry> entries,
  Widget? header,
  double width = 300,
  bool alignEnd = false,
}) async {
  KostvMenuEntry? picked;
  await showFocusRestoringDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    useSafeArea: false,
    builder: (dialogContext) {
      final screen = MediaQuery.sizeOf(dialogContext);
      var left = alignEnd ? anchor.right - width : anchor.left - 8;
      left = left.clamp(16.0, screen.width - width - 16);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: anchor.bottom + 10,
            width: width,
            child: KostvMenuCard(
              header: header,
              entries: entries,
              onSelected: (entry) {
                picked = entry;
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
        ],
      );
    },
  );
  final entry = picked;
  if (entry != null && context.mounted) entry.onSelected(context);
}

/// The card of [showKostvMenuPopup].
class KostvMenuCard extends StatelessWidget {
  const KostvMenuCard({
    super.key,
    required this.entries,
    required this.onSelected,
    this.header,
  });

  final List<KostvMenuEntry> entries;
  final ValueChanged<KostvMenuEntry> onSelected;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xF01E1E26),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 60,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              for (var i = 0; i < entries.length; i++) ...[
                if (entries[i].separatorBefore)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                KostvMenuRow(
                  key: ValueKey('kostv-menu-${entries[i].id}'),
                  entry: entries[i],
                  autofocus: i == 0,
                  onPressed: () => onSelected(entries[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The person at the top of «Tú»'s card.
class KostvMenuYouHeader extends StatelessWidget {
  const KostvMenuYouHeader({super.key, required this.menu});

  final KostvMenuController menu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Row(
        children: [
          KostvNavAvatar(
            size: 52,
            imageUrl: menu.userImageUrl,
            name: menu.userName,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  menu.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KostvMusicType.title(22),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.kostvMenuFamilyProfile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KostvMusicType.muted(14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the menu's card: white with dark text while it has the
/// remote's focus, a soft light under the mouse.
class KostvMenuRow extends StatefulWidget {
  const KostvMenuRow({
    super.key,
    required this.entry,
    required this.onPressed,
    this.autofocus = false,
  });

  final KostvMenuEntry entry;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  State<KostvMenuRow> createState() => _KostvMenuRowState();
}

class _KostvMenuRowState extends State<KostvMenuRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final lit = InputModeTracker.showFocusVisuals(context, _focused);
    final fg = lit ? KostvMusicTokens.background : const Color(0xD9F3F5FA);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        autofocus: widget.autofocus && !PlatformDetection.useMobileUi,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          label: entry.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: lit
                    ? KostvMusicTokens.ink
                    : _hovered
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  entry.iconWidget(22, fg),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 17,
                        fontWeight: lit ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (entry.detail != null)
                    Text(
                      entry.detail!,
                      style: TextStyle(
                        color: lit
                            ? const Color(0xFF333333)
                            : KostvMusicTokens.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (entry.count > 0)
                    KostvMenuCount(count: entry.count, outlined: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
