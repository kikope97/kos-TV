import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/kostv_menu_controller.dart';
import '../../screens/discover/kostv_requests_tray.dart';
import '../../screens/settings/settings_side_panel.dart';
import '../bottom_nav/bottom_nav_metrics.dart';
import '../music/design/kostv_music_tokens.dart';
import '../remote_control_dialog.dart';
import '../settings/settings_panel.dart';
import 'kostv_glass.dart';

/// What sits at the right of a page's header.
enum KostvPageHeaderActions {
  /// «Enviar a la tele» and the requests tray with its count (Inicio,
  /// Descubrir, Música).
  castAndInbox,

  /// Ajustes («Tú»).
  settings,
}

/// Kos TV: the large header of the pages the glass bar leads to, on phones
/// and tablets (docs/diseno-menu, `header()` and `headerSmall()`): the
/// page's name big, in Outfit, with round glass buttons on the right. As the
/// page scrolls down it goes with it and, past its own height, the small
/// header takes its place: the name small and centred over a soft blurred
/// edge, with the same buttons a little smaller.
class KostvPageHeader extends StatefulWidget {
  const KostvPageHeader({
    super.key,
    required this.title,
    required this.offset,
    this.actions = KostvPageHeaderActions.castAndInbox,
  });

  final String title;

  /// How far the page is scrolled down.
  final ValueListenable<double> offset;
  final KostvPageHeaderActions actions;

  /// Whether the window is a tablet's (a larger header).
  static bool isTablet(BuildContext context) =>
      BottomNavMetrics.isTablet(MediaQuery.sizeOf(context));

  /// Where the header's row starts under the status bar: 8 px on a phone
  /// (52 in the mockup with its 44 px status bar), 34 on a tablet.
  static double rowTop(BuildContext context) =>
      MediaQuery.paddingOf(context).top + (isTablet(context) ? 34 : 8);

  /// The room a page leaves at its top for the large header: where the first
  /// thing under it starts (the chips of Música, 112 in the phone mockup).
  static double room(BuildContext context) =>
      MediaQuery.paddingOf(context).top + (isTablet(context) ? 104 : 68);

  @override
  State<KostvPageHeader> createState() => _KostvPageHeaderState();
}

class _KostvPageHeaderState extends State<KostvPageHeader> {
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

  /// Whether a button's service is there; a server that can't say yet has
  /// none.
  static bool _offered(bool Function() check) {
    try {
      return check();
    } catch (_) {
      return false;
    }
  }

  List<Widget> _buttons(
    AppLocalizations l10n, {
    required double size,
    required double icon,
    required double count,
  }) {
    Widget round(
      Key key,
      IconData glyph,
      String label,
      VoidCallback onTap, {
      int badge = 0,
    }) => KostvGlassRoundButton(
      key: key,
      size: size,
      label: label,
      count: badge,
      countSize: count,
      onTap: onTap,
      child: Icon(glyph, size: icon, color: Colors.white),
    );

    switch (widget.actions) {
      case KostvPageHeaderActions.settings:
        return [
          round(
            const ValueKey('kostvHeaderSettings'),
            Icons.settings_rounded,
            l10n.settings,
            () => unawaited(
              SettingsPanel.open(context, const SettingsSidePanel()),
            ),
          ),
        ];
      case KostvPageHeaderActions.castAndInbox:
        return [
          if (_offered(() => _menu.remoteControlVisible))
            round(
              const ValueKey('kostvHeaderCast'),
              Icons.cast_rounded,
              l10n.kostvMenuSendToTv,
              () => showRemoteControlDialog(context),
            ),
          if (_offered(() => _menu.requestsVisible))
            round(
              const ValueKey('kostvHeaderInbox'),
              Icons.inbox_rounded,
              l10n.kostvMenuMyRequests,
              () => unawaited(showKostvRequestsTray(context)),
              badge: _menu.requestsNews,
            ),
        ];
    }
  }

  Widget _row(List<Widget> buttons, double gap) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        buttons[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tablet = KostvPageHeader.isTablet(context);
    final top = MediaQuery.paddingOf(context).top;
    final side = tablet ? 32.0 : 16.0;
    final rowTop = KostvPageHeader.rowTop(context);
    final big = _buttons(
      l10n,
      size: tablet ? 46 : 42,
      icon: tablet ? 20 : 19,
      count: 19,
    );
    final small = _buttons(l10n, size: 38, icon: 17, count: 17);
    final titleStyle = KostvMusicType.title(tablet ? 40 : 34).copyWith(
      height: 1.26,
      shadows: const [
        Shadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 2)),
      ],
    );
    final edge = top + 74;

    return ValueListenableBuilder<double>(
      valueListenable: widget.offset,
      builder: (context, offset, _) {
        // The large header goes up with the page and fades as it goes; the
        // small one comes in once it is nearly gone.
        final shown = (1 - offset / 48).clamp(0.0, 1.0);
        final gathered = ((offset - 36) / 24).clamp(0.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (shown > 0)
              Positioned(
                top: rowTop - offset,
                left: side,
                right: side,
                child: Opacity(
                  opacity: shown,
                  child: Row(
                    key: const ValueKey('kostvPageHeaderLarge'),
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      _row(big, tablet ? 12 : 10),
                    ],
                  ),
                ),
              ),
            if (gathered > 0) ...[
              // .edge: the page passes under a soft blurred edge.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: edge,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: gathered,
                    child: _BlurredEdge(blurs: kostvGlassBlurs),
                  ),
                ),
              ),
              Positioned(
                top: top + 6,
                left: side,
                right: side,
                child: Opacity(
                  opacity: gathered,
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      key: const ValueKey('kostvPageHeaderSmall'),
                      children: [
                        const SizedBox(width: 86),
                        Expanded(
                          child: Center(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KostvMusicType.title(17),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 86,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _row(small, 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// `.edge`: blur(14px) saturate(1.4), masked from solid at 55 % to nothing,
/// over a shade from 55 % through 15 % (at 70 %) to nothing.
class _BlurredEdge extends StatelessWidget {
  const _BlurredEdge({required this.blurs});

  final bool blurs;

  /// saturate(1.4).
  static const _saturate = <double>[
    1.3150, -0.2861, -0.0289, 0, 0, //
    -0.0850, 1.1139, -0.0289, 0, 0, //
    -0.0850, -0.2861, 1.3711, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final shade = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: blurs
              ? const [Color(0x8C08080C), Color(0x2608080C), Color(0x0008080C)]
              : const [Color(0xE008080C), Color(0x8008080C), Color(0x0008080C)],
          stops: const [0, 0.7, 1],
        ),
      ),
    );
    if (!blurs) return shade;
    // The blur, whole down to 62 % and lighter over the next part (two
    // bands, as a mask of the blur itself would cost a layer more).
    Widget band(double sigma) => ClipRect(
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          inner: const ColorFilter.matrix(_saturate),
        ),
        child: const SizedBox.expand(),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(flex: 62, child: band(14)),
            Expanded(flex: 18, child: band(5)),
            const Spacer(flex: 20),
          ],
        ),
        shade,
      ],
    );
  }
}
