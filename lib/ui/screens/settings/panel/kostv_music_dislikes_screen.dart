part of '../settings_side_panel.dart';

/// Kos TV: «Lo que no quieres oír», in Settings > Music: the songs and the
/// artists the person said no to («No me gusta», «No me pongas a este
/// artista»), each to take off, and a way to empty it all. It only changes
/// what plays by itself; it holds with «Aprender» off and «Borrar lo que he
/// escuchado» doesn't take it away, as the page says.
///
/// Taking one off gives a few seconds to put it back. Public for its tests.
class KostvMusicDislikesScreen extends StatefulWidget {
  const KostvMusicDislikesScreen({super.key});

  @override
  State<KostvMusicDislikesScreen> createState() =>
      _KostvMusicDislikesScreenState();
}

class _KostvMusicDislikesScreenState extends State<KostvMusicDislikesScreen> {
  final _store = KostvMusicDislikesStore.instance;
  bool _loading = true;
  bool _unanswered = false;

  /// The stops of the rows, by id, so the remote stays on the list when the
  /// one it was on goes.
  final _nodes = <String, FocusNode>{};
  final _clearNode = FocusNode(debugLabel: 'kostvMusicDislikesClear');

  MediaServerClient? get _client =>
      GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    unawaited(_read());
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    for (final node in _nodes.values) {
      node.dispose();
    }
    _clearNode.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _read() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _unanswered = false;
    });
    // Through the store, so the rest of the app sees the same.
    final answer = await _store.refresh(client);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _unanswered = answer.failed;
    });
  }

  FocusNode _nodeOf(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'dislike-$id'));

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _remove(KostvMusicDisliked entry, List<String> order) async {
    final client = _client;
    if (client == null) return;
    final l10n = AppLocalizations.of(context);
    final at = order.indexOf(entry.id);
    final hadFocus = _nodes[entry.id]?.hasFocus ?? false;
    final overlay = Overlay.of(context, rootOverlay: true);
    final remote = InputModeTracker.of(context) == InputMode.keyboard;
    final done = _store.remove(client, entry.id);
    // The remote goes to the row that takes its place.
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rest = [
          for (final id in order)
            if (id != entry.id) id,
        ];
        final next = rest.isEmpty
            ? null
            : _nodes[rest[at.clamp(0, rest.length - 1)]];
        (next ?? _clearNode).requestFocus();
      });
    }
    if (!await done) {
      if (mounted) _say(l10n.kostvMusicDislikeFailed);
      return;
    }
    if (!overlay.mounted) return;
    final before = FocusManager.instance.primaryFocus;
    showKostvUndoToastOn(
      overlay,
      message: l10n.kostvMusicUndisliked(entry.name),
      undoLabel: l10n.kostvUndo,
      duration: const Duration(seconds: 5),
      takeFocus: remote,
      onUndo: () {
        unawaited(() async {
          if (!await _store.restore(client, entry) && mounted) {
            _say(l10n.kostvMusicDislikeFailed);
          }
        }());
        if (remote) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _nodeOf(entry.id).requestFocus();
          });
        }
      },
      onLeave: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (before != null &&
              before.context != null &&
              before.canRequestFocus) {
            before.requestFocus();
          }
        });
      },
    );
  }

  Future<void> _clear() async {
    final client = _client;
    if (client == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(l10n.kostvMusicDislikesClearTitle),
        content: Text(l10n.kostvMusicDislikesClearBody),
        actions: [
          adaptiveDialogAction(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.kostvMusicDislikesClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await _store.clear(client);
    if (!mounted) return;
    _say(done ? l10n.kostvMusicDislikesCleared : l10n.kostvMusicDislikeFailed);
  }

  Widget _row(
    KostvMusicDisliked entry,
    List<String> order,
    AppLocalizations l10n,
  ) => _TvSettingsListTile(
    key: ValueKey('dislike-${entry.id}'),
    focusNode: _nodeOf(entry.id),
    leading: Icon(
      entry.artist ? Icons.person_off_outlined : Icons.music_off_outlined,
    ),
    title: Text(entry.name.isEmpty ? '—' : entry.name),
    // Kos TV: a song that isn't at home says so («Toda la música»).
    subtitle: entry.outOfHome
        ? Text(
            entry.artistName == null
                ? l10n.kostvStreamOutOfHome
                : l10n.kostvStreamDislikedOutOfHome(entry.artistName!),
          )
        : entry.artistName == null
        ? null
        : Text(entry.artistName!),
    trailing: Tooltip(
      message: l10n.kostvMusicDislikesRemove,
      child: const Icon(Icons.close_rounded),
    ),
    onTap: () => unawaited(_remove(entry, order)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = _store.of(_client);
    final order = [
      for (final s in list.songs) s.id,
      for (final a in list.artists) a.id,
    ];
    final explain = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        l10n.kostvMusicDislikesExplain,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.kostvMusicDislikes)),
      body: ListView(
        children: [
          explain,
          if (_loading && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_unanswered && list.isEmpty)
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  autofocus: true,
                  leading: const Icon(Icons.refresh_rounded),
                  title: Text(l10n.kostvMusicDislikes),
                  subtitle: Text(l10n.kostvMusicDislikesUnanswered),
                  onTap: () => unawaited(_read()),
                ),
              ],
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Focus(
                // Something for the remote to rest on.
                autofocus: true,
                child: Text(
                  l10n.kostvMusicDislikesEmptyHint,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            )
          else ...[
            if (list.songs.isNotEmpty) ...[
              _SectionHeader(l10n.kostvMusicDislikesSongsHeader),
              adaptiveListSection(
                children: [
                  for (final song in list.songs) _row(song, order, l10n),
                ],
              ),
            ],
            if (list.artists.isNotEmpty) ...[
              _SectionHeader(l10n.kostvMusicDislikesArtistsHeader),
              adaptiveListSection(
                children: [
                  for (final artist in list.artists) _row(artist, order, l10n),
                ],
              ),
            ],
            const SizedBox(height: 8),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  focusNode: _clearNode,
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.kostvMusicDislikesClear),
                  trailing: const SizedBox.shrink(),
                  onTap: () => unawaited(_clear()),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Kos TV: how much is in «Lo que no quieres oír»: «2 canciones · 1
/// artista», or «Nada por ahora».
String kostvMusicDislikesCount(AppLocalizations l10n, KostvMusicDislikes list) {
  if (list.isEmpty) return l10n.kostvMusicDislikesNone;
  return [
    if (list.songs.isNotEmpty) l10n.kostvMusicDislikesSongs(list.songs.length),
    if (list.artists.isNotEmpty)
      l10n.kostvMusicDislikesArtists(list.artists.length),
  ].join(' · ');
}
