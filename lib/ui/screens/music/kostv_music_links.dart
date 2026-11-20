import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: a name that opens its page, an artist's or an album's. Without
/// [onTap] it is only shown («Varios artistas», one the server gives no id
/// for).
@immutable
class KostvMusicLink {
  const KostvMusicLink(this.name, [this.onTap]);

  final String name;
  final VoidCallback? onTap;

  bool get opens => onTap != null;
}

/// The names that stand for many artists, which have no page of their own
/// worth opening.
bool kostvMusicIsVarious(String name) => const {
  'various artists',
  'various',
  'varios artistas',
  'varios',
  'va',
  'v.a.',
  'v/a',
}.contains(name.trim().toLowerCase());

/// The artists of one of the home server's songs, as its line shows them
/// (its own artists, or the album's when it has none), each opening its
/// page with [open] where the server gives its id. With [albumArtists], an
/// album's artists. [limit] keeps the first ones (a row has room for two).
List<KostvMusicLink> kostvHomeArtistLinks(
  AggregatedItem item, {
  required void Function(String location) open,
  bool albumArtists = false,
  int? limit,
}) {
  String? idIn(List<dynamic>? maps, String name) {
    if (maps == null) return null;
    final wanted = name.trim().toLowerCase();
    for (final map in maps) {
      if (map is! Map) continue;
      final mapName = map['Name']?.toString().trim().toLowerCase();
      final id = map['Id']?.toString();
      if (mapName == wanted && id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  final ownMaps = item.rawData['ArtistItems'] as List?;
  final albumMaps = item.rawData['AlbumArtists'] as List?;
  final named = <({String name, String? id})>[];
  if (albumArtists && albumMaps != null && albumMaps.isNotEmpty) {
    for (final map in albumMaps) {
      if (map is! Map) continue;
      final name = map['Name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      named.add((name: name, id: map['Id']?.toString()));
    }
  }
  if (named.isEmpty) {
    final names = albumArtists
        ? [
            if ((item.albumArtist ?? '').trim().isNotEmpty)
              item.albumArtist!.trim()
            else
              ...item.artists,
          ]
        : (item.artists.isNotEmpty
              ? item.artists
              : [
                  if ((item.albumArtist ?? '').trim().isNotEmpty)
                    item.albumArtist!.trim(),
                ]);
    for (final name in names) {
      if (name.trim().isEmpty) continue;
      named.add((
        name: name,
        id: albumArtists
            ? idIn(albumMaps, name) ?? idIn(ownMaps, name)
            : idIn(ownMaps, name) ?? idIn(albumMaps, name),
      ));
    }
  }
  final kept = limit == null ? named : named.take(limit);
  return [
    for (final artist in kept)
      KostvMusicLink(
        artist.name,
        artist.id == null ||
                artist.id!.isEmpty ||
                kostvMusicIsVarious(artist.name)
            ? null
            : () =>
                  open(Destinations.item(artist.id!, serverId: item.serverId)),
      ),
  ];
}

/// The album of one of the home server's songs, opening its page.
KostvMusicLink? kostvHomeAlbumLink(
  AggregatedItem item, {
  required void Function(String location) open,
}) {
  final name = item.album?.trim() ?? '';
  if (name.isEmpty) return null;
  final id = item.albumId;
  return KostvMusicLink(
    name,
    id == null || id.isEmpty
        ? null
        : () => open(Destinations.item(id, serverId: item.serverId)),
  );
}

/// An artist the requests service knows, opening their page there.
KostvMusicLink? kostvStremfinArtistLink(
  BuildContext context,
  String? name,
  String? deezerId,
) {
  final shown = name?.trim() ?? '';
  if (shown.isEmpty) return null;
  return KostvMusicLink(
    shown,
    deezerId == null || deezerId.isEmpty || kostvMusicIsVarious(shown)
        ? null
        : () => openKostvMusicArtist(
            context,
            StremfinArtist(deezerId: deezerId, name: shown),
          ),
  );
}

/// The album of a song the requests service knows: at home, its page
/// there; otherwise its page to ask for it.
KostvMusicLink? kostvStremfinAlbumLink(
  BuildContext context,
  StremfinSong song,
) {
  final album = song.album;
  final name = (album?.title ?? song.albumTitle)?.trim() ?? '';
  if (name.isEmpty) return null;
  VoidCallback? onTap;
  final atHome = song.albumJellyfinId ?? album?.jellyfinId;
  if (atHome != null) {
    onTap = () => unawaited(context.push(Destinations.item(atHome)));
  } else if (album != null) {
    onTap = () => unawaited(openKostvStremfinAlbum(context, album));
  } else if (song.albumDeezerId != null) {
    onTap = () => openKostvMusicAlbum(
      context,
      StremfinAlbum(
        title: name,
        deezerId: song.albumDeezerId,
        artist: song.artist,
        cover: song.cover,
      ),
    );
  }
  return KostvMusicLink(name, onTap);
}

/// The text of [groups] as one line: the names of a group joined by
/// commas, the groups by a middle dot.
String kostvMusicLinksText(
  List<List<KostvMusicLink>> groups, {
  String separator = ' · ',
}) => [
  for (final group in groups)
    if (group.isNotEmpty) group.map((link) => link.name).join(', '),
].join(separator);

/// Kos TV: the line under a song's title in a list, «Artista, Otra ·
/// Álbum», whose names open their pages with a tap or a click (the pointer
/// over one underlines it). On the TV it is only text: OK on the row plays
/// the song, and its menu has «Ir al álbum» and «Ir al artista».
///
/// On a phone the line is a little taller, for a finger to find the names.
class KostvMusicLinks extends StatefulWidget {
  const KostvMusicLinks({
    super.key,
    required this.groups,
    required this.style,
    this.after,
    this.separator = ' · ',
  });

  final List<List<KostvMusicLink>> groups;
  final TextStyle style;

  /// What goes between the groups.
  final String separator;

  /// Plain text after the names (« • 3:45»).
  final String? after;

  @override
  State<KostvMusicLinks> createState() => _KostvMusicLinksState();
}

class _KostvMusicLinksState extends State<KostvMusicLinks> {
  final _recognizers = <TapGestureRecognizer>[];
  // The place of the name the pointer is over.
  int? _hovered;

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final group in widget.groups)
        if (group.isNotEmpty) group,
    ];
    final after = widget.after ?? '';
    final anyLink = groups.any((group) => group.any((link) => link.opens));
    if (PlatformDetection.isTV || !anyLink) {
      return Text(
        kostvMusicLinksText(groups, separator: widget.separator) + after,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    _clear();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (g, group) in groups.indexed) {
      if (g > 0) spans.add(TextSpan(text: widget.separator));
      for (final (i, link) in group.indexed) {
        if (i > 0) spans.add(const TextSpan(text: ', '));
        final onTap = link.onTap;
        if (onTap == null) {
          spans.add(TextSpan(text: link.name));
          continue;
        }
        final place = at++;
        final recognizer = TapGestureRecognizer()..onTap = onTap;
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: link.name,
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = place),
            onExit: (_) {
              if (_hovered == place) setState(() => _hovered = null);
            },
            style: _hovered == place
                ? const TextStyle(decoration: TextDecoration.underline)
                : null,
          ),
        );
      }
    }
    if (after.isNotEmpty) spans.add(TextSpan(text: after));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: KostvMusicSizes.phone
          ? widget.style.copyWith(
              height: 1.7,
              leadingDistribution: TextLeadingDistribution.even,
            )
          : widget.style,
    );
  }
}

/// How the names of a page's header light up: on a Music page, white
/// with black words, as its buttons do; in the player, a soft light with
/// the music's colour round it on the TV, as its buttons do.
enum KostvMusicLinkLook { page, player }

/// Kos TV: the artists (and the album) under a header's title, «Artista,
/// Otra · Álbum», each a small text button of its own: a tap, a click or,
/// with the remote, a stop to land on and OK. [stop] makes the button (the
/// player has its own, which keeps the remote inside it); otherwise it is
/// one of the Music pages'.
///
/// With [oneLine], the names share one line and the long ones are cut
/// short; otherwise they go on to a second line when they don't fit.
class KostvMusicLinkButtons extends StatelessWidget {
  const KostvMusicLinkButtons({
    super.key,
    required this.groups,
    required this.style,
    this.centred = false,
    this.oneLine = false,
    this.look = KostvMusicLinkLook.page,
    this.stop,
  });

  final List<List<KostvMusicLink>> groups;
  final TextStyle style;
  final bool centred;
  final bool oneLine;
  final KostvMusicLinkLook look;
  final Widget Function(
    VoidCallback onTap,
    Widget Function(BuildContext context, bool lit) builder,
  )?
  stop;

  static const _padding = EdgeInsets.symmetric(horizontal: 6, vertical: 4);

  Widget _button(KostvMusicLink link) {
    Widget text(bool lit) => Text(
      link.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: lit && look == KostvMusicLinkLook.page
          ? style.copyWith(color: Colors.black)
          : style,
    );
    final onTap = link.onTap;
    if (onTap == null) {
      return Padding(padding: _padding, child: text(false));
    }
    Widget builder(BuildContext context, bool lit) => Semantics(
      link: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: _padding,
        decoration: BoxDecoration(
          borderRadius: AppRadius.circular(8),
          color: !lit
              ? Colors.transparent
              : look == KostvMusicLinkLook.page
              ? Colors.white
              : Colors.white.withValues(alpha: 0.18),
          border: look == KostvMusicLinkLook.player
              ? Border.all(
                  color: lit && PlatformDetection.isTV
                      ? kostvMusicColor
                      : Colors.transparent,
                  width: 2,
                )
              : null,
        ),
        child: text(lit),
      ),
    );
    final own = stop;
    if (own != null) return own(onTap, builder);
    return KostvMusicPressable(
      onTap: onTap,
      // A header's stop: the page goes back to its top rather than bringing
      // it to the middle.
      revealFromTop: true,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    final weights = <int?>[];
    var first = true;
    for (final group in groups) {
      if (group.isEmpty) continue;
      if (!first) {
        parts.add(Text(' · ', style: style));
        weights.add(null);
      }
      first = false;
      for (final (i, link) in group.indexed) {
        if (i > 0) {
          parts.add(Text(', ', style: style));
          weights.add(null);
        }
        parts.add(_button(link));
        weights.add(link.name.length.clamp(4, 60));
      }
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    final Widget line = oneLine
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, part) in parts.indexed)
                if (weights[i] == null)
                  part
                else
                  Flexible(flex: weights[i]!, child: part),
            ],
          )
        : Wrap(
            alignment: centred ? WrapAlignment.center : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: parts,
          );
    if (centred) return line;
    // Lined up with the title above: the buttons' own room sits out to the
    // left.
    return Transform.translate(offset: Offset(-_padding.left, 0), child: line);
  }
}
