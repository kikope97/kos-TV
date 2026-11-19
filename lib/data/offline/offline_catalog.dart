import 'dart:async';
import 'dart:convert';

import '../database/offline_database.dart';
import '../repositories/offline_repository.dart';
import 'download_people.dart';

/// One completed download with its parsed (and live-position-merged) server
/// metadata.
class OfflineEntry {
  final DownloadedItem row;

  /// The full server item JSON stored at download time, with `UserData`
  /// overridden from the row's live `playbackPositionTicks` (updated by the
  /// offline playback) so resume/played state is always current.
  final Map<String, dynamic> metadata;

  OfflineEntry(this.row, this.metadata);

  String get id => row.itemId;
  String get type => row.type;

  String? get sortName {
    final sort = metadata['SortName'] as String?;
    if (sort != null && sort.isNotEmpty) return sort;
    return metadata['Name'] as String? ?? row.name;
  }

  List<String> get genres =>
      ((metadata['Genres'] as List?) ?? const []).whereType<String>().toList();

  Map<String, dynamic>? get userData =>
      (metadata['UserData'] as Map?)?.cast<String, dynamic>();

  int? get runTimeTicks => (metadata['RunTimeTicks'] as num?)?.toInt();

  bool get isPlayed => userData?['Played'] == true;

  bool get isFavorite => userData?['IsFavorite'] == true;
}

/// In-memory snapshot of all completed downloads, shared by the offline API
/// implementations. Image URLs must resolve synchronously, so the catalog is
/// warmed once at startup and re-warmed (debounced) whenever the downloads
/// table changes.
class OfflineCatalog {
  final OfflineRepository _repo;

  /// Kos TV: who is signed in, whose progress the entries carry.
  final String? Function() _userId;

  /// Kos TV: whether Kids Mode is on, which leaves out what other people
  /// downloaded.
  final bool Function() _kidsMode;

  List<OfflineEntry> _entries = const [];
  Map<String, OfflineEntry> _byId = const {};
  StreamSubscription<void>? _sub;

  /// Kos TV: the rows and people of the last read, and who the entries were
  /// built for, so a switch of person rebuilds them without reading again.
  List<DownloadedItem> _rows = const [];
  DownloadPeople _people = DownloadPeople.empty;
  ({String user, bool kids})? _builtFor;

  /// Kos TV: each row's stored metadata as last decoded, keyed by item id.
  /// A rebuild decodes again only what changed: offline playback writes a
  /// row's position every few seconds, and decoding every download's
  /// metadata for that stalled the player on a large offline library.
  Map<String, ({String json, Map<String, dynamic> decoded})> _decoded =
      const {};
  Timer? _debounce;
  final _changes = StreamController<void>.broadcast();

  OfflineCatalog(
    this._repo, {
    String? Function()? userId,
    bool Function()? kidsMode,
  }) : _userId = userId ?? (() => null),
       _kidsMode = kidsMode ?? (() => false);

  List<OfflineEntry> get entries {
    _ensureBuiltForViewer();
    return _entries;
  }

  Stream<void> get changes => _changes.stream;

  OfflineEntry? byId(String itemId) {
    _ensureBuiltForViewer();
    return _byId[itemId];
  }

  Future<void> warm() async {
    await _rebuild();
    // Kos TV: told of the writes without reading the table; the rebuild
    // reads it once.
    _sub ??= _repo.watchChanges().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        _rebuild().then((_) => _changes.add(null));
      });
    });
  }

  Future<void> _rebuild() async {
    final rows = await _repo.getItems(onlyCompleted: true);
    final people = await _repo.getPeople();
    final decodedById =
        <String, ({String json, Map<String, dynamic> decoded})>{};
    for (final row in rows) {
      final cached = _decoded[row.itemId];
      if (cached != null && cached.json == row.metadataJson) {
        decodedById[row.itemId] = cached;
      } else {
        decodedById[row.itemId] = (
          json: row.metadataJson,
          decoded: _decode(row.metadataJson),
        );
      }
    }
    _rows = rows;
    _people = people;
    _decoded = decodedById;
    _build(_viewer());
  }

  ({String user, bool kids}) _viewer() =>
      (user: normalizeDownloadUserId(_userId()), kids: _kidsMode());

  void _ensureBuiltForViewer() {
    final viewer = _viewer();
    if (_builtFor != null && _builtFor != viewer) _build(viewer);
  }

  void _build(({String user, bool kids}) viewer) {
    final entries = <OfflineEntry>[];
    final byId = <String, OfflineEntry>{};
    final userId = viewer.user.isEmpty ? null : viewer.user;
    for (final row in _rows) {
      // Kos TV: in Kids Mode, what someone else downloaded stays out.
      if (viewer.kids &&
          _people.ownershipOf(row, userId) == DownloadOwnership.others) {
        continue;
      }
      final stored = _decoded[row.itemId]?.decoded ?? const {};
      // A copy per entry, as the position merge replaces its UserData.
      var metadata = Map<String, dynamic>.from(stored);
      if (metadata.isEmpty) {
        metadata = {'Id': row.itemId, 'Name': row.name, 'Type': row.type};
      }
      // Kos TV: the person's own progress where they have some, so one
      // person's watching never shows as another's.
      final personal = _people.personalUserData(row, metadata, userId);
      if (personal != null) {
        metadata['UserData'] = personal;
      } else {
        _mergeLivePosition(metadata, row);
      }
      final entry = OfflineEntry(row, metadata);
      entries.add(entry);
      byId[row.itemId] = entry;
    }
    _entries = entries;
    _byId = byId;
    _builtFor = viewer;
  }

  Map<String, dynamic> _decode(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// The metadata snapshot's UserData reflects download time, but the row's
  /// position column is what offline playback updates. Merging them means the
  /// UI, which reads UserData, always sees the live position.
  void _mergeLivePosition(Map<String, dynamic> metadata, DownloadedItem row) {
    final userData = <String, dynamic>{
      ...?(metadata['UserData'] as Map?)?.cast<String, dynamic>(),
    };
    final ticks = row.playbackPositionTicks;
    final runtime = (metadata['RunTimeTicks'] as num?)?.toInt();
    if (ticks > 0) {
      if (runtime != null && runtime > 0 && ticks >= runtime * 0.9) {
        userData['Played'] = true;
        userData['PlaybackPositionTicks'] = 0;
        userData.remove('PlayedPercentage');
      } else {
        userData['PlaybackPositionTicks'] = ticks;
        if (runtime != null && runtime > 0) {
          userData['PlayedPercentage'] = (ticks / runtime) * 100.0;
        }
      }
    }
    metadata['UserData'] = userData;
  }

  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _changes.close();
  }
}
