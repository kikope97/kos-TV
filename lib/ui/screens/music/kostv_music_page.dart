import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_now_playing.dart' show KostvCoverColors;
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: how an album's or an artist's page is laid out
/// (`docs/diseno-musica`, phase 2): the TV's (two columns of songs), a
/// computer's (a table) or a phone's (one under the other).
enum KostvPageForm { tv, wide, phone }

/// Kos TV: the form of the page for [context]'s screen.
KostvPageForm kostvPageForm(BuildContext context) {
  if (PlatformDetection.isTV) return KostvPageForm.tv;
  if (PlatformDetection.useMobileUi) return KostvPageForm.phone;
  return MediaQuery.sizeOf(context).width < 760
      ? KostvPageForm.phone
      : KostvPageForm.wide;
}

/// Kos TV: the page's margins, the design's (64 on the TV, 56 on the web,
/// 16 on the phone) or more where the menu takes room.
EdgeInsets kostvPageInsets(BuildContext context) {
  final chrome = calendarChromeInsets(context);
  final phone = kostvPageForm(context) == KostvPageForm.phone;
  final margin = phone ? 16.0 : KostvMusicTokens.margin;
  return EdgeInsets.fromLTRB(
    math.max(chrome.left, margin),
    chrome.top,
    math.max(chrome.right, margin),
    0,
  );
}

/// Kos TV: the room the page leaves under its end (the bar at the bottom).
double kostvPageBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom +
    (PlatformDetection.useMobileUi && NavigationLayout.usesBottomNavbar
        ? 110
        : 48);

/// Kos TV: Music's dark page, washed from the top with the colour of [url]'s
/// picture (worked out once per picture, off the remote's moves: see
/// [KostvArtworkColors]); plain dark until it is known.
class KostvArtworkWash extends StatefulWidget {
  const KostvArtworkWash({
    super.key,
    required this.url,
    required this.child,
    this.strength = 0.5,
    this.at = const Alignment(-0.8, -1.1),
  });

  final String? url;
  final Widget child;
  final double strength;
  final Alignment at;

  @override
  State<KostvArtworkWash> createState() => _KostvArtworkWashState();
}

class _KostvArtworkWashState extends State<KostvArtworkWash> {
  Color? _color;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(KostvArtworkWash old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _read();
  }

  static Color _of(KostvCoverColors colors) =>
      Color.lerp(colors.top, colors.accent, 0.55)!;

  void _read() {
    final url = widget.url;
    if (url == null) {
      _color = null;
      return;
    }
    final kept = KostvArtworkColors.cached(url);
    if (kept != null) {
      _color = _of(kept);
      return;
    }
    unawaited(
      KostvArtworkColors.of(url).then((colors) {
        if (!mounted || widget.url != url) return;
        if (identical(colors, KostvCoverColors.fallback)) return;
        setState(() => _color = _of(colors));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: KostvMusicTokens.background),
        // Its own layer, drawn once: the list scrolling over it doesn't
        // paint it again.
        RepaintBoundary(
          child: AnimatedOpacity(
            opacity: color == null ? 0 : 1,
            duration: const Duration(milliseconds: 450),
            child: color == null
                ? const SizedBox.expand()
                : DecoratedBox(
                    decoration: KostvArtworkColors.wash(
                      color,
                      strength: widget.strength,
                      at: widget.at,
                    ),
                  ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Kos TV: a round glass button of an album's or artist's header (shuffle,
/// ♥, «⋯»), with its own stop for the remote, the mouse and touch.
class KostvRoundButton extends StatelessWidget {
  const KostvRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.diameter = 44,
    this.color = KostvMusicTokens.ink,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
  });

  final IconData icon;
  final String tooltip;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final VoidCallback onTap;
  final double diameter;
  final Color color;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    excludeSemantics: true,
    child: Tooltip(
      message: tooltip,
      child: KostvMusicPressable(
        focusNode: focusNode,
        autofocus: autofocus,
        revealFromTop: true,
        onKey: onKey,
        onTap: onTap,
        builder: (context, lit) => KostvRoundIcon(
          icon: icon,
          diameter: diameter,
          lit: lit,
          color: color,
        ),
      ),
    ),
  );
}

/// Kos TV: a secondary pill of a page («Pedir el álbum», «Crear emisora»,
/// a request's state), with its own stop.
class KostvPillButton extends StatelessWidget {
  const KostvPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = KostvPillKind.ghost,
    this.size = KostvPillSize.m,
    this.busy = false,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final KostvPillKind kind;
  final KostvPillSize size;
  final bool busy;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => KostvMusicPressable(
    focusNode: focusNode,
    autofocus: autofocus,
    revealFromTop: true,
    onTap: busy ? () {} : onTap,
    builder: (context, lit) => KostvMusicPill(
      label: label,
      icon: icon,
      kind: kind,
      size: size,
      lit: lit,
      busy: busy,
    ),
  );
}

/// Kos TV: the calm note of an album that isn't (all) at home: what
/// happens, in two tones, and what can be done ([action], «Pedir el álbum»
/// or how its request stands). [compact] (the phone) puts it in a card,
/// the action under the words.
class KostvAwayNote extends StatelessWidget {
  const KostvAwayNote({
    super.key,
    required this.lead,
    this.rest,
    this.extra,
    this.action,
    this.compact = false,
    this.fontSize = 15,
  });

  /// What stands out («Este disco no está en casa: suena en streaming.»).
  final String lead;
  final String? rest;

  /// A line more, quieter («Tienes 3 de 10 canciones»).
  final String? extra;
  final Widget? action;
  final bool compact;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: rest == null ? lead : '$lead ',
                style: const TextStyle(
                  color: KostvMusicTokens.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (rest != null) TextSpan(text: rest),
            ],
          ),
          style: TextStyle(
            color: KostvMusicTokens.muted,
            fontSize: fontSize,
            height: 1.35,
          ),
        ),
        if (extra != null) ...[
          const SizedBox(height: 4),
          Text(
            extra!,
            style: TextStyle(
              color: KostvMusicTokens.dim,
              fontSize: fontSize - 1,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 10),
          child: Icon(
            Icons.graphic_eq_rounded,
            size: fontSize + 3,
            color: KostvMusicTokens.dim,
          ),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: words,
          ),
        ),
      ],
    );
    final action = this.action;
    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: KostvMusicTokens.glass(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        if (action != null) ...[const SizedBox(width: 24), action],
      ],
    );
  }
}

/// Kos TV: the artist under an album's title: their small picture, their
/// name ([name], which may open their page) and, quieter, [meta].
class KostvAlbumArtistLine extends StatelessWidget {
  const KostvAlbumArtistLine({
    super.key,
    required this.name,
    this.picture,
    this.meta,
    this.form = KostvPageForm.wide,
  });

  /// Told the style the name goes in.
  final Widget Function(TextStyle style) name;
  final String? picture;
  final String? meta;
  final KostvPageForm form;

  @override
  Widget build(BuildContext context) {
    final (avatar, size, metaSize) = switch (form) {
      KostvPageForm.tv => (30.0, 19.0, 16.0),
      KostvPageForm.wide => (28.0, 17.0, 15.0),
      KostvPageForm.phone => (22.0, 15.0, 13.0),
    };
    final style = TextStyle(
      color: KostvMusicTokens.ink,
      fontSize: size,
      fontWeight: FontWeight.w500,
    );
    final meta = this.meta;
    return Row(
      children: [
        KostvMusicCover(
          url: picture,
          size: avatar,
          circle: true,
          icon: Icons.person_rounded,
        ),
        const SizedBox(width: 6),
        Flexible(child: name(style)),
        if (meta != null && meta.isNotEmpty)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '· $meta',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KostvMusicTokens.muted,
                  fontSize: metaSize,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kos TV: an album's page, the same for one at home and one that isn't
/// (`docs/diseno-musica`): the colour of its cover behind, the big cover,
/// «ÁLBUM · 2026», its title in the brand's letters, the artist and what it
/// has, the one play button with round ones after it, the calm [note] of
/// one not at home and its songs (two columns on the TV, a table on a
/// computer, one under the other on a phone).
class KostvAlbumPage extends StatelessWidget {
  const KostvAlbumPage({
    super.key,
    required this.cover,
    required this.kicker,
    required this.title,
    required this.tracks,
    this.artist,
    this.phoneMeta,
    this.play,
    this.shuffle,
    this.like,
    this.more,
    this.extras = const [],
    this.note,
    this.under,
    this.body,
  });

  /// The cover's address: the picture and the page's colour.
  final String? cover;

  /// «Álbum · 2026».
  final String kicker;
  final String title;

  /// [KostvAlbumArtistLine] for the form it is told.
  final Widget Function(KostvPageForm form)? artist;

  /// On the phone, the line under the artist («Álbum · 2026 · 10
  /// canciones · 33 min»).
  final String? phoneMeta;

  /// The gradient play button, for the diameter it is told.
  final Widget Function(double diameter)? play;
  final Widget Function(double diameter)? shuffle;
  final Widget Function(double diameter)? like;
  final Widget Function(double diameter)? more;

  /// After the round buttons (the 30 seconds of a song, the ask of an album
  /// that doesn't play).
  final List<Widget> extras;

  /// The note of one that isn't at home, told whether it is [compact].
  final Widget Function(bool compact)? note;

  /// Under the header, before the songs (why the whole album is asked).
  final Widget? under;

  /// The songs' rows, in order.
  final List<Widget> tracks;

  /// Instead of [tracks] (loading, failed).
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final form = kostvPageForm(context);
    final insets = kostvPageInsets(context);
    final l10n = AppLocalizations.of(context);
    // The rows reach 12 out of the margin (their frame and hover have
    // room, their text lines up with the header's): the rest goes 12 in.
    Widget inset(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
    final children = <Widget>[
      inset(
        form == KostvPageForm.phone
            ? _phoneHeader(context)
            : _sideHeader(context, form),
      ),
      if (form == KostvPageForm.wide && note != null) ...[
        const SizedBox(height: 22),
        inset(Align(alignment: Alignment.centerLeft, child: note!(false))),
      ],
      if (under != null) ...[const SizedBox(height: 14), inset(under!)],
      SizedBox(height: form == KostvPageForm.phone ? 12 : 26),
      if (body != null)
        inset(body!)
      else if (form == KostvPageForm.tv && tracks.length >= 6)
        _columns()
      else ...[
        if (form == KostvPageForm.wide && tracks.isNotEmpty) _tableHead(l10n),
        ...tracks,
      ],
    ];
    return KostvArtworkWash(
      url: cover,
      strength: form == KostvPageForm.phone ? 0.55 : 0.45,
      at: form == KostvPageForm.phone
          ? const Alignment(0, -1.1)
          : const Alignment(-0.8, -1.1),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          insets.left - 12,
          insets.top + (form == KostvPageForm.phone ? 4 : 12),
          insets.right - 12,
          kostvPageBottom(context),
        ),
        children: children,
      ),
    );
  }

  Widget _coverBox(double size) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 60,
          offset: Offset(0, 24),
        ),
      ],
    ),
    child: KostvMusicCover(url: cover, size: size, radius: 12),
  );

  Widget _title(double size) => Text(
    title,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: KostvMusicType.title(title.length > 26 ? size * 0.7 : size)
        .copyWith(height: 1.05),
  );

  Text _kicker(double size) => Text(
    kicker.toUpperCase(),
    style: TextStyle(
      color: KostvMusicTokens.muted,
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.08 * size,
    ),
  );

  Widget _sideHeader(BuildContext context, KostvPageForm form) {
    final tv = form == KostvPageForm.tv;
    final coverSize = tv ? 296.0 : 280.0;
    final round = tv ? 50.0 : 44.0;
    final gap = tv ? 18.0 : 16.0;
    final buttons = Wrap(
      spacing: gap,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (play != null) play!(tv ? 68 : 60),
        if (shuffle != null) shuffle!(round),
        if (like != null) like!(round),
        if (more != null) more!(round),
        ...extras,
      ],
    );
    final note = this.note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _coverBox(coverSize),
        SizedBox(width: tv ? 44 : 40),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kicker(13),
              const SizedBox(height: 6),
              _title(tv ? 64 : 68),
              if (artist != null) ...[
                SizedBox(height: tv ? 12 : 10),
                artist!(form),
              ],
              SizedBox(height: tv ? 22 : 20),
              buttons,
              if (tv && note != null) ...[
                const SizedBox(height: 16),
                note(false),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _phoneHeader(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = math.min(width * 0.64, 320.0);
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Center(child: _coverBox(coverSize)),
        const SizedBox(height: 22),
        _title(30),
        if (artist != null) ...[
          const SizedBox(height: 8),
          artist!(KostvPageForm.phone),
        ],
        if (phoneMeta != null) ...[
          const SizedBox(height: 6),
          Text(
            phoneMeta!,
            style: const TextStyle(color: KostvMusicTokens.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (like != null) like!(40),
            if (like != null && more != null) const SizedBox(width: 6),
            if (more != null) more!(40),
            const Spacer(),
            if (shuffle != null) ...[shuffle!(40), const SizedBox(width: 14)],
            if (play != null) play!(56),
          ],
        ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: extras),
        ],
        if (note != null) ...[const SizedBox(height: 12), note(true)],
      ],
    );
  }

  Widget _tableHead(AppLocalizations l10n) {
    const style = TextStyle(
      color: KostvMusicTokens.dim,
      fontSize: 12,
      letterSpacing: 0.96,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 0, 52, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            child: Center(child: Text('#', style: style)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l10n.kostvMusicColumnTitle.toUpperCase(), style: style),
          ),
          Text(l10n.kostvMusicColumnLength.toUpperCase(), style: style),
        ],
      ),
    );
  }

  Widget _columns() => KostvTwoColumns(rows: tracks);
}

/// Kos TV: song rows in two columns, the TV's: down the first, then the
/// second (the remote goes down a column, and across to the other).
class KostvTwoColumns extends StatelessWidget {
  const KostvTwoColumns({super.key, required this.rows, this.gap = 28});

  final List<Widget> rows;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final half = (rows.length + 1) ~/ 2;
    Widget column(Iterable<Widget> rows) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...rows],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column(rows.take(half)),
        SizedBox(width: gap),
        column(rows.skip(half)),
      ],
    );
  }
}

/// Kos TV: an artist's page's top (`docs/diseno-musica`): their picture
/// big behind, fading into the page, «ARTISTA», their name in the brand's
/// letters, what they have and the buttons: the one play button, a pill
/// («Crear emisora») and round ones.
class KostvArtistHero extends StatelessWidget {
  const KostvArtistHero({
    super.key,
    required this.name,
    required this.kicker,
    this.picture,
    this.meta,
    this.play,
    this.pill,
    this.round = const [],
  });

  final String name;
  final String kicker;
  final String? picture;
  final String? meta;
  final Widget Function(double diameter)? play;

  /// The pill after the play button, for its size.
  final Widget Function(KostvPillSize size)? pill;

  /// Round buttons, for their diameter.
  final List<Widget Function(double diameter)> round;

  /// How high the top is, picture and all.
  static double heightFor(KostvPageForm form) => switch (form) {
    KostvPageForm.tv => 400,
    KostvPageForm.wide => 430,
    KostvPageForm.phone => 380,
  };

  @override
  Widget build(BuildContext context) {
    final form = kostvPageForm(context);
    final insets = kostvPageInsets(context);
    final width = MediaQuery.sizeOf(context).width;
    final phone = form == KostvPageForm.phone;
    final height = heightFor(form) + (phone ? 0 : insets.top - 80).clamp(0, 60);
    final nameSize = switch (form) {
      KostvPageForm.tv => 84.0,
      KostvPageForm.wide => 92.0,
      KostvPageForm.phone => 46.0,
    };
    final shown = name.length > 18 ? nameSize * 0.7 : nameSize;
    final picture = this.picture;
    final photoWidth = (phone ? width : math.min(width * 0.62, height * 1.5))
        .roundToDouble();
    final buttons = <Widget>[
      if (pill != null) pill!(phone ? KostvPillSize.s : KostvPillSize.l),
      for (final button in round)
        button(phone ? 36 : (form == KostvPageForm.tv ? 52 : 44)),
    ];
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!phone) ...[
          Text(
            kicker.toUpperCase(),
            style: const TextStyle(
              color: KostvMusicTokens.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.04,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: KostvMusicType.title(shown).copyWith(height: 1.0),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          SizedBox(height: phone ? 8 : 10),
          Text(
            meta!,
            style: TextStyle(
              color: KostvMusicTokens.muted,
              fontSize: phone ? 13 : (form == KostvPageForm.tv ? 16 : 15),
            ),
          ),
        ],
        SizedBox(height: phone ? 12 : 22),
        if (phone)
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: buttons,
                ),
              ),
              if (play != null) play!(56),
            ],
          )
        else
          Wrap(
            spacing: form == KostvPageForm.tv ? 18 : 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (play != null) play!(form == KostvPageForm.tv ? 64 : 60),
              ...buttons,
            ],
          ),
      ],
    );
    return Stack(
      children: [
        if (picture != null)
          Positioned(
            top: 0,
            right: 0,
            width: photoWidth,
            height: height,
            child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: phone ? Alignment.topCenter : Alignment.centerLeft,
                  end: phone ? Alignment.bottomCenter : Alignment.centerRight,
                  colors: const [Color(0x00000000), Color(0xFF000000)],
                  stops: phone ? const [0, 0] : const [0.04, 0.45],
                ).createShader(rect),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x00000000), Color(0xFF000000)],
                    // Clear a little in from its end: no line where the
                    // picture stops, at any scroll.
                    stops: [0.04, 0.6],
                  ).createShader(rect),
                  // Nothing of it out of its box: a mask only clears what is
                  // inside, and the picture's last row would show as a line.
                  child: ClipRect(
                    child: BoundedNetworkImage(
                      imageUrl: picture,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.4),
                      maxWidth: 1000,
                      errorBuilder: (context, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            insets.left,
            phone ? height - 108 : 0,
            insets.right,
            0,
          ),
          child: phone
              ? words
              : ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: Padding(
                    padding: EdgeInsets.only(top: insets.top),
                    child: SizedBox(height: height - insets.top, child: words),
                  ),
                ),
        ),
      ],
    );
  }
}
