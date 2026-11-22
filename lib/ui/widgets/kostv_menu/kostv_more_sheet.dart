import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/kostv_menu_controller.dart';
import '../bottom_nav/bottom_nav_destinations.dart';
import '../music/design/kostv_music_tokens.dart';
import '../music/kostv_now_playing.dart';
import 'kostv_glass.dart';
import 'kostv_menu_entries.dart';
import 'kostv_nav_avatar.dart';

/// Kos TV: «Más» on phones and tablets, a glass sheet that opens with a long
/// press on «Tú»: every destination that isn't on the bar, as tiles, then
/// switching person and Ajustes. It floats off the screen's edges, with
/// round corners like the phone's.
Future<void> showKostvMoreSheet({
  required BuildContext context,
  required KostvMenuController menu,
}) async {
  KostvMenuEntry? picked;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (sheetContext) {
      // The bar's own mini player is under the sheet: the floating one
      // stays away (it would lift the sheet off the bottom too).
      KostvNowPlayingRouteObserver.instance.setBottomBar(
        ModalRoute.of(sheetContext),
        true,
      );
      return ListenableBuilder(
        listenable: menu,
        builder: (_, _) => KostvMoreSheet(
          menu: menu,
          onSelected: (entry) {
            picked = entry;
            Navigator.of(sheetContext).pop();
          },
        ),
      );
    },
  );
  final entry = picked;
  if (entry != null && context.mounted) entry.onSelected(context);
}

/// The sheet of [showKostvMoreSheet].
class KostvMoreSheet extends StatelessWidget {
  const KostvMoreSheet({
    super.key,
    required this.menu,
    required this.onSelected,
  });

  final KostvMenuController menu;
  final ValueChanged<KostvMenuEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final entries = kostvPhoneMoreEntries(
      l10n,
      menu,
      openPage: openBottomNavPage,
    );
    // movil_cristal_hoja: the places that aren't on the bar and the
    // requests; the rest of what is each person's is on the «Tú» page.
    const places = {
      'libraries',
      'genres',
      'liveTv',
      'calendar',
      'myList',
      'discover',
      'music',
      'requests',
    };
    final tiles = [
      for (final t in entries.tiles)
        if (places.contains(t.id)) t,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        8 + media.padding.left,
        0,
        8 + media.padding.right,
        8 + media.padding.bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: media.size.height - media.padding.top - 24,
          ),
          child: KostvGlass(
            heavy: true,
            radius: 36,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(l10n.more, style: KostvMusicType.title(24)),
                      ),
                      Semantics(
                        button: true,
                        label: l10n.close,
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: KostvGlass(
                              nested: true,
                              child: Center(
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: KostvMusicTokens.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (var row = 0; row < tiles.length; row += 3) ...[
                    if (row > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = row; i < row + 3; i++) ...[
                          if (i > row) const SizedBox(width: 10),
                          Expanded(
                            child: i < tiles.length
                                ? _Tile(
                                    entry: tiles[i],
                                    onTap: () => onSelected(tiles[i]),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  KostvGlass(
                    radius: 20,
                    shadow: false,
                    nested: true,
                    child: Column(
                      children: [
                        for (var i = 0; i < entries.rows.length; i++)
                          KostvGlassRow(
                            key: ValueKey('kostv-more-${entries.rows[i].id}'),
                            entry: entries.rows[i],
                            divider: i > 0,
                            onTap: () => onSelected(entries.rows[i]),
                          ),
                      ],
                    ),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.onTap});

  final KostvMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Capped so a large text setting can't stretch a two-line label's row
    // far past the others.
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.3);
    return Semantics(
      button: true,
      label: entry.label,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('kostv-more-${entry.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: KostvGlass(
          radius: 20,
          shadow: false,
          nested: true,
          child: SizedBox(
            height: 86,
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        entry.iconWidget(24, Colors.white),
                        const SizedBox(height: 6),
                        Text(
                          entry.id == 'requests'
                              ? AppLocalizations.of(context)
                                    .kostvMenuRequestsShort
                              : entry.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          textScaler: textScaler,
                          style: const TextStyle(
                            color: KostvMusicTokens.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entry.count > 0)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: KostvMenuCount(count: entry.count, size: 19),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kos TV: a row of a glass group (the «Más» sheet, the «Tú» page): icon,
/// name, a quiet detail and the chevron.
class KostvGlassRow extends StatelessWidget {
  const KostvGlassRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.divider = false,
  });

  final KostvMenuEntry entry;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: entry.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: divider
                ? Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              entry.iconWidget(21, KostvMusicTokens.ink.withValues(alpha: 0.9)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KostvMusicTokens.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (entry.detail != null)
                Text(
                  entry.detail!,
                  style: TextStyle(
                    color: KostvMusicTokens.ink.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                )
              else if (entry.count > 0)
                KostvMenuCount(count: entry.count, size: 19, outlined: false),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: KostvMusicTokens.ink.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
