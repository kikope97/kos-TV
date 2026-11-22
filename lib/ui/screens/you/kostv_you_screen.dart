import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/bottom_nav_tabs.dart';
import '../../navigation/destinations.dart';
import '../../navigation/kostv_menu_controller.dart';
import '../../widgets/bottom_nav/bottom_nav_destinations.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/kostv_menu/kostv_glass.dart';
import '../../widgets/kostv_menu/kostv_menu_entries.dart';
import '../../widgets/kostv_menu/kostv_more_sheet.dart';
import '../../widgets/kostv_menu/kostv_nav_avatar.dart';
import '../../widgets/music/design/kostv_music_tokens.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/settings/settings_panel.dart';
import '../../widgets/user_menu_dialog.dart';
import '../discover/kostv_requests_tray.dart';
import '../downloads/downloads_panel.dart';
import '../settings/settings_side_panel.dart';

/// Kos TV: «Tú», the page of what is each person's, on phones and tablets
/// (docs/diseno-menu): who is signed in, with «Cambiar»; their requests;
/// Quiero verlo, Mis favoritos and Descargas; then «En casa» (Bibliotecas,
/// Géneros, TV en directo, Calendario) and the rest. Ajustes is the cog at
/// the top. On a TV and a computer the avatar's menu holds the same.
class KostvYouScreen extends StatefulWidget {
  const KostvYouScreen({super.key});

  @override
  State<KostvYouScreen> createState() => _KostvYouScreenState();
}

class _KostvYouScreenState extends State<KostvYouScreen> {
  final _menu = KostvMenuController();

  @override
  void initState() {
    super.initState();
    _menu.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _menu
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _open(String route) => openBottomNavPage(context, route);

  void _settings() =>
      unawaited(SettingsPanel.open(context, const SettingsSidePanel()));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = _menu;
    final more = kostvPhoneMoreEntries(l10n, menu, openPage: openBottomNavPage);
    // What «En casa» and the quick tiles don't already show.
    const shownHere = {
      'libraries',
      'genres',
      'liveTv',
      'calendar',
      'myList',
      'requests',
      'favorites',
      'saved',
      'discover',
      'music',
    };
    final extras = [
      for (final e in more.tiles)
        if (!shownHere.contains(e.id)) e,
    ];
    final atHome = <KostvMenuEntry>[
      if (menu.shows(BottomNavTab.libraries))
        KostvMenuEntry(
          id: 'libraries',
          label: l10n.libraries,
          iconBuilder: (size, color) => Image.asset(
            'assets/icons/clapperboard.png',
            width: size,
            height: size,
            color: color,
          ),
          detail: '${menu.navLibraries.length}',
          onSelected: (_) => _open(Destinations.kostvLibraries),
        ),
      if (menu.shows(BottomNavTab.genres))
        KostvMenuEntry(
          id: 'genres',
          label: l10n.genres,
          iconBuilder: (size, color) => Image.asset(
            'assets/icons/genres.png',
            width: size,
            height: size,
            color: color,
          ),
          onSelected: (_) => _open(Destinations.allGenres),
        ),
      if (menu.shows(BottomNavTab.liveTv))
        KostvMenuEntry(
          id: 'liveTv',
          label: l10n.liveTv,
          icon: Icons.live_tv_rounded,
          onSelected: (_) => _open(Destinations.liveTvGuide),
        ),
      if (menu.shows(BottomNavTab.calendar))
        KostvMenuEntry(
          id: 'calendar',
          label: l10n.calendar,
          icon: Icons.calendar_month_rounded,
          onSelected: (_) => _open(Destinations.calendar),
        ),
      // A destination the bar can't hold today (Discover or Music turned
      // off makes room for another).
      for (final e in more.tiles)
        if (e.id == 'discover' || e.id == 'music') e,
    ];

    return Scaffold(
      backgroundColor: KostvMusicTokens.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvYou,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _YouBackdrop(),
            SafeArea(
              bottom: false,
              child: BottomNavPadded(
                fallback: 24,
                builder: (context, bottom) => ListView(
                  key: const ValueKey('kostvYouList'),
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.navYou,
                            style: KostvMusicType.title(34),
                          ),
                        ),
                        _GlassCircle(
                          key: const ValueKey('kostvYouSettings'),
                          icon: Icons.settings_rounded,
                          label: l10n.settings,
                          onTap: _settings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PersonRow(menu: menu),
                    if (menu.requestsVisible) ...[
                      const SizedBox(height: 20),
                      _RequestsCard(menu: menu),
                    ],
                    const SizedBox(height: 12),
                    _QuickTiles(menu: menu, open: _open),
                    if (atHome.isNotEmpty) ...[
                      _Heading(l10n.kostvMenuAtHome),
                      _Group(entries: atHome),
                    ],
                    if (extras.isNotEmpty) ...[
                      _Heading(l10n.more),
                      _Group(entries: extras),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouBackdrop extends StatelessWidget {
  const _YouBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -1.0),
              radius: 0.9,
              colors: [Color(0x8CFF8C78), Color(0x00FF8C78)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.0, -0.4),
              radius: 0.8,
              colors: [Color(0x738F6BFF), Color(0x008F6BFF)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.0, 0.5),
              radius: 0.9,
              colors: [Color(0x474FD8FF), Color(0x004FD8FF)],
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.menu});

  final KostvMenuController menu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        KostvNavAvatar(
          size: 66,
          imageUrl: menu.userImageUrl,
          name: menu.userName,
          ring: true,
          spinning: menu.requestsWorking,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                menu.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KostvMusicType.title(24),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.kostvMenuFamilyProfile,
                style: TextStyle(
                  color: KostvMusicTokens.ink.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: l10n.kostvMenuSwitchPerson,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('kostvYouSwitch'),
            onTap: () => showUserMenu(context),
            child: KostvGlass(
              shadow: false,
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.swap_vert_rounded,
                        size: 16,
                        color: KostvMusicTokens.ink,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.kostvMenuChange,
                        style: const TextStyle(
                          color: KostvMusicTokens.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestsCard extends StatelessWidget {
  const _RequestsCard({required this.menu});

  final KostvMenuController menu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final news = menu.requestsNews;
    final subtitle = [
      if (news > 0) l10n.kostvMenuNews(news),
      if (menu.requestsActive) l10n.kostvMenuOnItsWay,
    ].join(' · ');
    return Semantics(
      button: true,
      label: l10n.kostvMenuMyRequests,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('kostvYouRequests'),
        onTap: () => unawaited(showKostvRequestsTray(context)),
        child: KostvGlass(
          radius: 22,
          tint: LinearGradient(
            begin: const Alignment(-1, -0.4),
            end: const Alignment(1, 0.4),
            colors: [
              KostvMusicTokens.cyan.withValues(alpha: 0.22),
              KostvMusicTokens.violet.withValues(alpha: 0.20),
              KostvMusicTokens.pink.withValues(alpha: 0.22),
            ],
            stops: const [0, 0.55, 1],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  child: const Icon(
                    Icons.inbox_rounded,
                    size: 20,
                    color: KostvMusicTokens.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.kostvMenuMyRequests,
                        style: const TextStyle(
                          color: KostvMusicTokens.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: KostvMusicTokens.ink.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (news > 0) KostvMenuCount(count: news, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickTiles extends StatelessWidget {
  const _QuickTiles({required this.menu, required this.open});

  final KostvMenuController menu;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = <Widget>[
      if (menu.gates.offers(BottomNavTab.myList))
        _QuickTile(
          key: const ValueKey('kostvYouMyList'),
          icon: Icons.bookmark_rounded,
          label: l10n.kostvMyList,
          onTap: () => open(Destinations.myList),
        ),
      _QuickTile(
        key: const ValueKey('kostvYouFavorites'),
        icon: Icons.favorite_rounded,
        iconColor: KostvMusicTokens.pink,
        label: l10n.kostvMyFavorites,
        detail: menu.favoritesNews > 0
            ? l10n.kostvMenuNews(menu.favoritesNews)
            : null,
        onTap: () => open(Destinations.allFavorites),
      ),
      if (menu.savedVisible)
        _QuickTile(
          key: const ValueKey('kostvYouSaved'),
          icon: Icons.download_rounded,
          label: l10n.savedMedia,
          onTap: () => showDownloadsDialog(context),
        ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = KostvMusicTokens.ink,
    this.detail,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: KostvGlass(
          radius: 20,
          shadow: false,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KostvMusicTokens.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: TextStyle(
                      color: KostvMusicTokens.ink.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: KostvMusicTokens.ink.withValues(alpha: 0.6),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.entries});

  final List<KostvMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    return KostvGlass(
      radius: 22,
      shadow: false,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++)
              KostvGlassRow(
                key: ValueKey('kostvYou-${entries[i].id}'),
                entry: entries[i],
                divider: i > 0,
                onTap: () => entries[i].onSelected(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: KostvGlass(
              child: Center(
                child: Icon(icon, size: 20, color: KostvMusicTokens.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
