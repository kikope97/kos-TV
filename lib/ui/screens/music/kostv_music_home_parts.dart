import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: the tabs of Music's home (`docs/diseno-musica/README.md`): «Para
/// ti», the person's playlists, and the artists and albums at home.
enum KostvMusicTab { forYou, lists, artists, albums }

/// Kos TV: the label of [tab].
String kostvMusicTabLabel(AppLocalizations l10n, KostvMusicTab tab) =>
    switch (tab) {
      KostvMusicTab.forYou => l10n.kostvMusicTabForYou,
      KostvMusicTab.lists => l10n.kostvMusicPlaylists,
      KostvMusicTab.artists => l10n.kostvMusicArtists,
      KostvMusicTab.albums => l10n.kostvMusicTabAlbums,
    };

/// Kos TV: what the search shows («Todo» or one kind).
enum KostvMusicFilter { all, songs, albums, artists, lists }

String kostvMusicFilterLabel(AppLocalizations l10n, KostvMusicFilter f) =>
    switch (f) {
      KostvMusicFilter.all => l10n.kostvMusicFilterAll,
      KostvMusicFilter.songs => l10n.kostvMusicSongs,
      KostvMusicFilter.albums => l10n.kostvMusicTabAlbums,
      KostvMusicFilter.artists => l10n.kostvMusicArtists,
      KostvMusicFilter.lists => l10n.kostvMusicFilterLists,
    };

/// Kos TV: the accesses of «Sigue escuchando», in the design's order: the
/// albums played lately with, between them, the favourites (second), a mix
/// (fourth) and a playlist (seventh); what is missing leaves its place to
/// the next album. [count] at most (8 on the TV and the web, 6 on the
/// phone). Also says how many of [albums] it took, for «Escuchado hace
/// poco» to show the rest.
({List<T> picks, int albumsUsed}) kostvKeepListening<T>({
  required List<T> albums,
  T? favorites,
  T? mix,
  T? playlist,
  int count = 8,
}) {
  final picks = <T>[];
  var next = 0;
  void album() {
    if (next < albums.length) picks.add(albums[next++]);
  }

  for (final slot in const ['a', 'f', 'a', 'm', 'a', 'a', 'p', 'a']) {
    if (picks.length >= count) break;
    switch (slot) {
      case 'f':
        if (favorites != null) picks.add(favorites);
      case 'm':
        if (mix != null) picks.add(mix);
      case 'p':
        if (playlist != null) picks.add(playlist);
      default:
        album();
    }
  }
  while (picks.length < count && next < albums.length) {
    album();
  }
  return (picks: picks, albumsUsed: next);
}

/// Kos TV: [all] with those of [recent] first, in [recent]'s order (only
/// those [all] has), and then the rest in [all]'s own order (A–Z).
List<T> kostvRecentFirst<T>(
  List<String> recent,
  List<T> all,
  String Function(T item) idOf,
) {
  final byId = {for (final item in all) idOf(item): item};
  final first = <T>[];
  final seen = <String>{};
  for (final id in recent) {
    final item = byId[id];
    if (item != null && seen.add(id)) first.add(item);
  }
  return [
    ...first,
    for (final item in all)
      if (!seen.contains(idOf(item))) item,
  ];
}

/// Kos TV: what a search's «Lo mejor» can be.
enum KostvTopKind { artist, album, song, list }

/// Kos TV: one candidate for «Lo mejor».
class KostvTopCandidate<T> {
  const KostvTopCandidate(this.kind, this.name, this.item);

  final KostvTopKind kind;
  final String name;
  final T item;
}

/// Kos TV: «Lo mejor» of a search for [query]: the first whose name is the
/// query itself (accents and case aside), an artist before an album, an
/// album before a song; otherwise the first of [candidates] (in the order
/// given: what is at home first).
KostvTopCandidate<T>? kostvTopResult<T>(
  String query,
  List<KostvTopCandidate<T>> candidates,
) {
  if (candidates.isEmpty) return null;
  final wanted = kostvFold(query);
  for (final kind in const [
    KostvTopKind.artist,
    KostvTopKind.album,
    KostvTopKind.list,
    KostvTopKind.song,
  ]) {
    for (final c in candidates) {
      if (c.kind == kind && kostvFold(c.name) == wanted) return c;
    }
  }
  return candidates.first;
}

/// Kos TV: [text] lower-cased, without accents or spaces at the ends.
String kostvFold(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final rune in text.trim().toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at < 0 ? char : to[at]);
  }
  return buffer.toString();
}

/// Kos TV: a row of pills that pick one of them: the home's tabs and the
/// search's filters (and the order of the artists and albums). With the
/// remote, OK picks the one with the focus; the arrows move between them
/// and [onKey] sees them first (the row's edges).
class KostvMusicChoiceRow<T> extends StatelessWidget {
  const KostvMusicChoiceRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.nodes,
    this.onKey,
    this.solid = false,
    this.size = KostvPillSize.s,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelect;

  /// Each pill's focus node, when the page moves the remote to them.
  final Map<T, FocusNode>? nodes;
  final KeyEventResult Function(T value, KeyEvent event)? onKey;

  /// The one picked in white (the search's filters); otherwise with a thin
  /// edge (the tabs), so the remote's white focus stands apart from it.
  final bool solid;
  final KostvPillSize size;

  @override
  Widget build(BuildContext context) {
    final gap = PlatformDetection.useMobileUi ? 8.0 : 10.0;
    return FocusTraversalGroup(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final (i, value) in values.indexed) ...[
              if (i > 0) SizedBox(width: gap),
              Semantics(
                selected: value == selected,
                button: true,
                child: KostvMusicPressable(
                  key: ValueKey('kostv-choice-$value'),
                  focusNode: nodes?[value],
                  centerVertically: false,
                  onTap: () => onSelect(value),
                  onKey: onKey == null ? null : (event) => onKey!(value, event),
                  builder: (context, lit) => _ChoicePill(
                    label: label(value),
                    picked: value == selected,
                    lit: lit,
                    solid: solid,
                    size: size,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.picked,
    required this.lit,
    required this.solid,
    required this.size,
  });

  final String label;
  final bool picked;
  final bool lit;
  final bool solid;
  final KostvPillSize size;

  @override
  Widget build(BuildContext context) {
    if (solid && picked && !lit) {
      final (height, pad, font) = switch (size) {
        KostvPillSize.s => (32.0, 14.0, 13.0),
        KostvPillSize.m => (40.0, 18.0, 15.0),
        KostvPillSize.l => (52.0, 24.0, 18.0),
      };
      return Container(
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KostvMusicTokens.ink,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: KostvMusicTokens.background,
            fontSize: font,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return KostvMusicPill(
      label: label,
      size: size,
      lit: lit,
      kind: picked ? KostvPillKind.ghost : KostvPillKind.quiet,
    );
  }
}

/// Kos TV: the art of «Tus favoritas» in «Sigue escuchando»: a heart on the
/// brand's violet and pink.
class KostvFavoritesArt extends StatelessWidget {
  const KostvFavoritesArt({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [KostvMusicTokens.violet, KostvMusicTokens.pink],
      ),
    ),
    child: Icon(Icons.favorite_rounded, color: Colors.white, size: size * 0.5),
  );
}

/// Kos TV: the art of «Descubrimiento semanal»: the brand's gradient with
/// «Cada lunes» and its name, as the design draws it.
class KostvDiscoveryArt extends StatelessWidget {
  const KostvDiscoveryArt({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final words = l10n.kostvMusicDiscovery.split(' ');
    return MediaQuery.withNoTextScaling(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KostvMusicTokens.radiusCover),
        child: Container(
          width: size,
          height: size,
          padding: EdgeInsets.fromLTRB(
            size * 0.09,
            size * 0.09,
            size * 0.09,
            size * 0.12,
          ),
          alignment: Alignment.bottomLeft,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1, -0.7),
              end: Alignment(1, 0.7),
              colors: [
                KostvMusicTokens.cyan,
                KostvMusicTokens.violet,
                KostvMusicTokens.pink,
              ],
              stops: [0, 0.5, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.kostvMusicDiscoveryKicker.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KostvMusicType.titleFamily,
                  fontWeight: FontWeight.w300,
                  fontSize: size * 0.07,
                  letterSpacing: size * 0.012,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              SizedBox(height: size * 0.025),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  [
                    words.first,
                    if (words.length > 1) words.skip(1).join(' '),
                  ].join('\n'),
                  style: KostvMusicType.title(
                    size * 0.13,
                    color: Colors.white,
                  ).copyWith(height: 1.02),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kos TV: a search's «Lo mejor»: a big card with its cover, its name in
/// the brand's letters and the play button. The card opens it ([onTap]);
/// the button plays it ([onPlay]). On the phone it lies down (cover at the
/// start, button at the end).
class KostvTopResultCard extends StatelessWidget {
  const KostvTopResultCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.cover,
    this.circle = false,
    this.onPlay,
    this.focusNode,
    this.onKey,
    this.onLongPress,
    this.playFocusNode,
    this.playOnKey,
  });

  final String title;
  final String? subtitle;
  final String? cover;
  final bool circle;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// The play button's own stop (the remote reaches it from the card).
  final FocusNode? playFocusNode;
  final KeyEventResult Function(KeyEvent event)? playOnKey;

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDetection.useMobileUi;
    final tv = PlatformDetection.isTV;
    final play = onPlay;
    final playButton = play == null
        ? null
        : KostvPlayButton(
            size: KostvPlaySize.card,
            diameter: phone ? 44 : 56,
            tooltip: AppLocalizations.of(context).play,
            focusNode: playFocusNode,
            onKey: playOnKey,
            onTap: play,
          );
    Widget text(double titleSize) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: phone ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: KostvMusicType.title(titleSize),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KostvMusicType.muted(phone ? 13 : 15),
          ),
        ],
      ],
    );
    final coverSize = phone ? 84.0 : (tv ? 110.0 : 120.0);
    final art = KostvMusicCover(
      url: cover,
      size: coverSize,
      circle: circle,
      radius: KostvMusicTokens.radiusCover,
      icon: circle ? Icons.person_rounded : Icons.album_rounded,
    );
    return KostvMusicPressable(
      focusNode: focusNode,
      onTap: onTap,
      onKey: onKey,
      onLongPress: onLongPress,
      builder: (context, lit) => KostvFocusFrame(
        lit: lit,
        radius: 14,
        scale: 1.03,
        child: AnimatedContainer(
          duration: KostvMusicTokens.focusDuration,
          padding: EdgeInsets.all(phone ? 12 : 22),
          decoration: BoxDecoration(
            color: KostvMusicTokens.glass(lit ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(phone ? 12 : 14),
          ),
          child: phone
              ? Row(
                  children: [
                    art,
                    const SizedBox(width: 14),
                    Expanded(child: text(24)),
                    if (playButton != null) ...[
                      const SizedBox(width: 10),
                      playButton,
                    ],
                  ],
                )
              : Stack(
                  children: [
                    // As wide as its place, the button at its right edge.
                    const SizedBox(width: double.infinity),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        art,
                        const SizedBox(height: 18),
                        Padding(
                          padding: EdgeInsets.only(
                            right: playButton == null ? 0 : 72,
                          ),
                          child: text(tv ? 34 : 36),
                        ),
                      ],
                    ),
                    if (playButton != null)
                      Positioned(right: 0, bottom: 0, child: playButton),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Kos TV: the card that makes a new playlist, first in «Tus listas»: a
/// glass square with «+» and «Nueva lista» under it, as big as the lists.
class KostvNewListCard extends StatelessWidget {
  const KostvNewListCard({
    super.key,
    required this.size,
    required this.onTap,
    this.focusNode,
    this.onKey,
  });

  final double size;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: size,
      child: KostvMusicPressable(
        focusNode: focusNode,
        onTap: onTap,
        onKey: onKey,
        builder: (context, lit) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            KostvFocusFrame(
              lit: lit,
              radius: KostvMusicTokens.radiusCover,
              alignment: const Alignment(0, -0.2),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: KostvMusicTokens.glass(lit ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(
                    KostvMusicTokens.radiusCover,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: size * 0.32,
                  height: size * 0.32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KostvMusicTokens.gradient,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: KostvMusicTokens.background,
                    size: size * 0.18,
                  ),
                ),
              ),
            ),
            SizedBox(height: lit ? 14 : 10),
            Text(
              l10n.kostvMusicNewList,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KostvMusicType.body(
                PlatformDetection.useMobileUi ? 14 : 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kos TV: asks the name of a new playlist of music and makes it, empty, on
/// the home server. Its id, or null when the person left or it failed (it
/// says so).
Future<String?> showKostvNewPlaylist(
  BuildContext context,
  MediaServerClient client,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NewPlaylistDialog(),
  );
  final wanted = name?.trim() ?? '';
  if (wanted.isEmpty) return null;
  try {
    final made = await client.itemsApi.createPlaylist(
      name: wanted,
      itemIds: const [],
      mediaType: 'Audio',
    );
    final id = made['Id']?.toString();
    if (id == null || id.isEmpty) throw StateError('no playlist');
    return id;
  } catch (_) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.playlistCreateFailed)));
    return null;
  }
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog();

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'kostvNewListName');
  final _createFocus = FocusNode(debugLabel: 'kostvNewListCreate');
  final _tvField = GlobalKey<CustomTVTextFieldState>();

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _createFocus.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tv = PlatformDetection.isTV;
    final fill = KostvMusicTokens.glass(0.08);
    final hint = TextStyle(color: KostvMusicTokens.dim, fontSize: 16);
    const ink = TextStyle(color: KostvMusicTokens.ink, fontSize: 16);
    final field = tv
        ? Focus(
            focusNode: _nameFocus,
            autofocus: true,
            onKeyEvent: (_, event) {
              if (!event.isActionable) return KeyEventResult.ignored;
              if (event.logicalKey.isSelectKey) {
                _tvField.currentState?.openKeyboard();
                return KeyEventResult.handled;
              }
              if (event.logicalKey.isDownKey) {
                _createFocus.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ListenableBuilder(
              listenable: _nameFocus,
              builder: (_, _) => CustomTVTextField(
                key: _tvField,
                controller: _name,
                isFocused: _nameFocus.hasFocus,
                inputPurpose: InputPurpose.text,
                keyboardType: KeyboardType.alphabetic,
                keyboardStyle: GetIt.instance<UserPreferences>().get(
                  UserPreferences.keyboardStyle,
                ),
                hint: l10n.playlistName,
                filled: true,
                fillColor: fill,
                hintStyle: hint,
                textStyle: ink,
                borderRadius: 12,
                borderColor: Colors.transparent,
                focusedBorderColor: Colors.white,
                borderWidth: 0,
                focusedBorderWidth: 3,
                popParentOnKeyboardClose: false,
              ),
            ),
          )
        : TextField(
            controller: _name,
            focusNode: _nameFocus,
            autofocus: true,
            style: ink,
            cursorColor: KostvMusicTokens.violet,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _done(),
            decoration: InputDecoration(
              hintText: l10n.playlistName,
              hintStyle: hint,
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          );
    Widget button(
      String label,
      VoidCallback onTap, {
      FocusNode? node,
      bool main = false,
    }) => KostvMusicPressable(
      focusNode: node,
      centerVertically: false,
      onTap: onTap,
      builder: (context, lit) => KostvMusicPill(
        label: label,
        lit: lit,
        icon: main ? Icons.add_rounded : null,
        kind: main ? KostvPillKind.ghost : KostvPillKind.quiet,
      ),
    );
    return Dialog(
      backgroundColor: const Color(0xFF17161D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.kostvMusicNewList, style: KostvMusicType.title(24)),
              const SizedBox(height: 18),
              SizedBox(height: tv ? 56 : null, child: field),
              const SizedBox(height: 20),
              FocusTraversalGroup(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    button(l10n.cancel, () => Navigator.of(context).pop()),
                    const SizedBox(width: 10),
                    button(
                      l10n.playlistCreate,
                      _done,
                      node: _createFocus,
                      main: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kos TV: the width of a column of songs on Music's home: three fit on the
/// TV's screen, as the design draws the charts.
double kostvMusicSongColumn(BuildContext context) {
  if (PlatformDetection.useMobileUi) {
    return MediaQuery.sizeOf(context).width * 0.84;
  }
  return PlatformDetection.isTV ? 352 : 400;
}

/// Kos TV: how many cards fit across a grid of [width] (the design's card
/// size, at least two) and how big each is so its columns fill it.
({int count, double size}) kostvGridOf(double width) {
  final want = KostvMusicTokens.card;
  final gap = KostvMusicTokens.shelfGap;
  final count = ((width + gap) / (want + gap)).floor().clamp(2, 12);
  return (count: count, size: (width - gap * (count - 1)) / count - 0.5);
}

/// Kos TV: a mix in «Sigue escuchando»: its colour with its first artist's
/// picture in a circle (the card's art, small).
class KostvMiniMixArt extends StatelessWidget {
  const KostvMiniMixArt({
    super.key,
    required this.size,
    required this.index,
    this.picture,
  });

  final double size;
  final int index;
  final String? picture;

  @override
  Widget build(BuildContext context) {
    final colors = kostvMixColors(index);
    final d = size * 0.68;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
          colors: colors,
        ),
      ),
      child: ClipOval(
        child: SizedBox.square(
          dimension: d,
          child: picture == null || picture!.isEmpty
              ? ColoredBox(
                  color: Colors.black.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: d * 0.55,
                  ),
                )
              : KostvMusicCover(url: picture, size: d, circle: true),
        ),
      ),
    );
  }
}
