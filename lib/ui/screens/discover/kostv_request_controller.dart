import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/stremfin/stremfin_client.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';

/// Kos TV: something to tell the person after asking for a title or taking a
/// request back. The page puts it into words.
@immutable
class KostvRequestNotice {
  const KostvRequestNotice.outcome(StremfinRequestResult this.result)
    : error = null,
      withdrawn = false;

  const KostvRequestNotice.error(StremfinException this.error)
    : result = null,
      withdrawn = false;

  const KostvRequestNotice.withdrawn()
    : result = null,
      error = null,
      withdrawn = true;

  final StremfinRequestResult? result;
  final StremfinException? error;
  final bool withdrawn;
}

/// Kos TV: the page of a title that isn't on the home server: what it is,
/// whether it can be asked for, and, once someone has, how the request
/// stands, asked again every few seconds while the page is in sight. When it
/// arrives, [arrivedItemId] says where it is on the home server.
abstract class KostvRequestController extends ChangeNotifier {
  KostvRequestController({
    required this.service,
    required this.tmdbId,
    this.seed,
    @visibleForTesting bool watchLifecycle = true,
  }) {
    if (watchLifecycle) {
      _lifecycle = AppLifecycleListener(
        onShow: () => _setForeground(true),
        onHide: () => _setForeground(false),
      );
    }
    service.addListener(onServiceChanged);
  }

  /// The service said something new of the person (their limit, say).
  @protected
  void onServiceChanged() => _notify();

  final StremfinService service;
  final int tmdbId;

  /// What the card it was opened from said of it, to show at once.
  final StremfinTitle? seed;

  StremfinTitleType get type;

  /// The title as it stands now.
  StremfinTitle? get title;

  /// While asking again, while it is under way and while it is on its way
  /// down.
  static const quickInterval = Duration(seconds: 5);

  /// While it waits for an answer, a version or the administrator.
  static const slowInterval = Duration(seconds: 15);

  /// After the service couldn't answer.
  static const backoffInterval = Duration(seconds: 30);

  AppLifecycleListener? _lifecycle;
  bool _visible = true;
  bool _foreground = true;
  Timer? _timer;
  bool _ticking = false;
  bool _disposed = false;
  DateTime? _lastTick;
  Duration? _backoff;

  /// The page is being read for the first time.
  bool loading = true;

  /// The page couldn't be read (shown with a way to try again).
  StremfinException? loadError;

  /// A request is being sent or taken back.
  bool sending = false;

  /// It has arrived: its item on the home server.
  String? arrivedItemId;

  /// It was on the home server before the page was shown, so the page gives
  /// way to it at once rather than with the change of colour.
  bool arrivedOnOpen = false;

  /// On the home server, but the home server is still adding it (its item
  /// shows up in a minute or two).
  bool arrivingSoon = false;

  /// Called with what to tell the person after asking or taking back.
  ValueChanged<KostvRequestNotice>? onNotice;

  /// Whether it is asking every few seconds: only while the page is in
  /// sight and the app in front.
  bool get isActive => _visible && _foreground;

  @visibleForTesting
  bool get isPolling => _timer?.isActive ?? false;

  /// The service lets the person ask for things now (their limit not
  /// reached).
  bool get atLimit => service.me?.atLimit ?? false;

  /// What they ask for waits for the administrator.
  bool get needsApproval => service.me?.needsApproval ?? false;

  Future<void> load() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      await read(initial: true);
    } on StremfinException catch (e) {
      loadError = e;
    }
    loading = false;
    _notify();
    _plan();
  }

  /// The page is on screen (or covered by another, or the app left).
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _plan(resume: visible);
  }

  void _setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _plan(resume: foreground);
  }

  /// Reads the page, and the requests for it.
  @protected
  Future<void> read({bool initial = false});

  /// How often to ask again now, or null for not at all.
  @protected
  Duration? get interval;

  /// Asks again how it stands.
  @protected
  Future<void> refresh();

  /// The page says it is on the home server: whether it is ready to open.
  @protected
  bool noteLibrary(StremfinLibrary library, {required bool initial}) {
    if (!library.inLibrary) {
      arrivingSoon = false;
      return false;
    }
    final itemId = library.itemId;
    if (itemId == null) {
      arrivingSoon = true;
      return false;
    }
    arrivingSoon = false;
    arrivedItemId = itemId;
    arrivedOnOpen = initial;
    return true;
  }

  void _plan({bool resume = false}) {
    _timer?.cancel();
    _timer = null;
    if (_disposed || loading || loadError != null) return;
    if (arrivedItemId != null || !isActive) return;
    final every = _backoff ?? interval;
    if (every == null) return;
    var wait = every;
    // Back on screen after a while: ask now rather than show stale news.
    final last = _lastTick;
    if (resume && last != null) {
      final since = clock.now().difference(last);
      wait = since >= every ? Duration.zero : every - since;
    }
    _timer = Timer(wait, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_ticking || _disposed) return;
    _ticking = true;
    _lastTick = clock.now();
    try {
      await refresh();
      _backoff = null;
    } on StremfinException catch (e) {
      _backoff = e.retryAfter ?? backoffInterval;
    } finally {
      _ticking = false;
    }
    _notify();
    _plan();
  }

  /// Reads the page again after asking: if that fails, the request was
  /// still made, and the next round of asking catches up.
  @protected
  Future<void> readQuietly(Future<void> Function() read) async {
    try {
      await read();
    } on StremfinException {
      _backoff = null;
    }
  }

  /// Runs [action] as the one request being sent, and reads afresh after.
  @protected
  Future<void> sendWith(Future<void> Function() action) async {
    if (sending) return;
    sending = true;
    _notify();
    try {
      await action();
    } on StremfinException catch (e) {
      onNotice?.call(KostvRequestNotice.error(e));
    } finally {
      sending = false;
      _lastTick = clock.now();
      _notify();
      _plan();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    service.removeListener(onServiceChanged);
    super.dispose();
  }
}

/// Kos TV: a film's request page.
class KostvMovieRequestController extends KostvRequestController {
  KostvMovieRequestController({
    required super.service,
    required super.tmdbId,
    super.seed,
    @visibleForTesting super.watchLifecycle,
  });

  @override
  StremfinTitleType get type => StremfinTitleType.movie;

  StremfinMovieDetail? detail;

  /// Whether it can be downloaded now and how fast; null until known.
  StremfinAvailability? availability;
  bool checkingAvailability = false;

  /// The open request for it, whoever asked.
  StremfinRequest? request;

  /// The last request for it the administrator turned down.
  StremfinRequest? rejected;

  @override
  StremfinTitle? get title => detail?.title ?? seed;

  @override
  Duration? get interval {
    // Finished: until the home server shows it.
    if (arrivingSoon || request?.status == StremfinRequestStatus.completed) {
      return KostvRequestController.slowInterval;
    }
    final open = request;
    if (open != null && open.status.isOpen) {
      final downloading =
          open.status == StremfinRequestStatus.approved &&
          open.progress?.state == StremfinProgressState.downloading;
      return downloading
          ? KostvRequestController.quickInterval
          : KostvRequestController.slowInterval;
    }
    // Downloading for someone else: how far it has got.
    if (detail?.download != null) return KostvRequestController.quickInterval;
    return null;
  }

  /// Whether it has been asked how fast it could be downloaded.
  bool _availabilityAsked = false;

  @override
  Future<void> read({bool initial = false}) async {
    if (!initial) return _readMovie();
    // Who the person is now (a quick call) along with the page: at their
    // limit, the costly check below isn't made.
    await Future.wait([service.refreshAccess(), _readMovie(initial: true)]);
    _maybeCheckAvailability();
  }

  @override
  void onServiceChanged() {
    // Their limit freed up meanwhile: the button can be offered now.
    _maybeCheckAvailability();
    super.onServiceChanged();
  }

  /// Whether and how fast it could be downloaded. The service looks for the
  /// file to answer, which takes seconds and costs it, so it is asked once
  /// and only when the answer is any use: nothing asked for or coming down
  /// yet, it can be asked for, and the person isn't at their limit.
  void _maybeCheckAvailability() {
    if (_availabilityAsked || _disposed || atLimit) return;
    final read = detail;
    if (read == null || arrivedItemId != null || request != null) return;
    if (read.title.library.inLibrary || read.download != null) return;
    final can = read.canRequest;
    if (!can.allowed || can.action != StremfinRequestAction.request) return;
    _availabilityAsked = true;
    checkingAvailability = true;
    _notify();
    unawaited(
      service
          .movieAvailability(tmdbId)
          .then<StremfinAvailability?>((a) => a, onError: (_) => null)
          .then((a) {
            availability = a;
            checkingAvailability = false;
            _notify();
          }),
    );
  }

  Future<void> _readMovie({bool initial = false}) async {
    final read = await service.movie(tmdbId);
    detail = read;
    if (noteLibrary(read.title.library, initial: initial)) {
      request = null;
      return;
    }
    final ref = read.title.request;
    if (ref == null) {
      // A title only carries open requests; a finished one stays until the
      // home server shows it.
      if (request?.status != StremfinRequestStatus.completed) request = null;
    } else if (request?.id != ref.id || initial) {
      await _readRequest(ref.id);
    }
    if (!initial) _maybeCheckAvailability();
  }

  Future<void> _readRequest(int id) async {
    final StremfinRequest read;
    try {
      read = await service.request(id);
    } on StremfinException catch (e) {
      // Taken back, or joined with another: the page says what is left.
      if (e.status == 404) {
        request = null;
        return;
      }
      rethrow;
    }
    _followRequest(read);
  }

  void _followRequest(StremfinRequest read) {
    if (read.status == StremfinRequestStatus.rejected) {
      rejected = read;
      request = null;
    } else {
      request = read;
      if (read.status.isOpen) rejected = null;
    }
  }

  @override
  Future<void> refresh() async {
    final open = request;
    if (open == null || arrivingSoon || !open.status.isOpen) {
      await _readMovie();
      return;
    }
    final before = open.status;
    try {
      _followRequest(await service.request(open.id));
    } on StremfinException catch (e) {
      if (e.status != 404) rethrow;
      request = null;
    }
    final now = request;
    if (now == null || now.status != before) {
      // Arrived, turned down, accepted or gone: the page as it stands, and
      // the card in Discover with it.
      await _readMovie();
    }
  }

  /// Asks for it (or, while it is on its way down already, to be told when
  /// it arrives).
  Future<void> ask() => sendWith(() async {
    final result = await service.createRequest(
      type: StremfinTitleType.movie,
      tmdbId: tmdbId,
    );
    onNotice?.call(KostvRequestNotice.outcome(result));
    final made = result.request;
    switch (result.outcome) {
      case StremfinOutcome.created ||
              StremfinOutcome.started ||
              StremfinOutcome.joined ||
              StremfinOutcome.watching ||
              StremfinOutcome.included ||
              StremfinOutcome.already
          when made != null:
        _followRequest(made);
        final current = title;
        if (current != null) {
          service.noteTitle(current.copyWith(request: () => made.asRef));
        }
      case StremfinOutcome.unavailable:
        availability = const StremfinAvailability(
          status: StremfinAvailabilityStatus.unavailable,
        );
        await readQuietly(_readMovie);
      case StremfinOutcome.limit:
        break;
      default:
        await readQuietly(_readMovie);
    }
  });

  /// Takes back their request while it waits for an answer.
  Future<void> withdraw() {
    final open = request;
    if (open == null || !open.canWithdraw) return Future.value();
    return sendWith(() async {
      try {
        await service.withdrawRequest(open.id);
        onNotice?.call(const KostvRequestNotice.withdrawn());
      } on StremfinException catch (e) {
        // Answered meanwhile: show how it stands.
        if (e.code != 'already_answered' && e.status != 404) rethrow;
      }
      await readQuietly(_readMovie);
    });
  }
}

/// Kos TV: a series' request page, season by season.
class KostvSeriesRequestController extends KostvRequestController {
  KostvSeriesRequestController({
    required super.service,
    required super.tmdbId,
    super.seed,
    @visibleForTesting super.watchLifecycle,
  });

  @override
  StremfinTitleType get type => StremfinTitleType.series;

  StremfinSeriesDetail? detail;

  /// The requests for it this page follows, by id: the one for all that's
  /// missing and each season's, whoever asked.
  final Map<int, StremfinRequest> requests = {};

  /// What is being asked for: a season, or 0 for all that is missing.
  int? sendingSeason;

  /// The series' page is asked again at most this often (it is one of the
  /// service's costly calls), unless a request changed.
  static const pageInterval = Duration(seconds: 60);
  DateTime? _pageReadAt;

  /// Whether a request this page followed has finished meanwhile.
  bool _sawCompletion = false;

  @override
  StremfinTitle? get title => detail?.title ?? seed;

  /// The request for all that is missing, if there is one.
  StremfinRequest? get wholeRequest {
    final id = detail?.title.request?.id;
    return id == null ? null : requests[id];
  }

  /// The request that covers [season] (its own, or the one for all that is
  /// missing).
  StremfinRequest? requestFor(StremfinSeason season) {
    final id = season.request?.id;
    return id == null ? null : requests[id];
  }

  @override
  Duration? get interval {
    if (arrivingSoon) return KostvRequestController.slowInterval;
    final open = requests.values.where((r) => r.status.isOpen);
    if (open.isEmpty) return null;
    final downloading = open.any(
      (r) =>
          r.status == StremfinRequestStatus.approved &&
          r.progress?.state == StremfinProgressState.downloading,
    );
    return downloading
        ? KostvRequestController.quickInterval
        : KostvRequestController.slowInterval;
  }

  @override
  Future<void> read({bool initial = false}) => _readSeries(initial: initial);

  Future<void> _readSeries({bool initial = false}) async {
    final read = await service.series(tmdbId);
    detail = read;
    _pageReadAt = clock.now();
    final ids = <int>{
      ?read.title.request?.id,
      for (final season in read.seasons) ?season.request?.id,
    };
    requests.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      if (requests.containsKey(id) && !initial) continue;
      try {
        requests[id] = await service.request(id);
      } on StremfinException catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    _checkArrival(initial: initial);
  }

  /// A series gives way to its page on the home server once what was asked
  /// for has arrived and nothing is still on its way.
  void _checkArrival({bool initial = false}) {
    final library = detail?.title.library;
    if (library == null) return;
    if (requests.values.any((r) => r.status.isOpen)) {
      arrivingSoon = false;
      return;
    }
    if (!_sawCompletion) {
      arrivingSoon = false;
      return;
    }
    noteLibrary(library, initial: initial);
  }

  @override
  Future<void> refresh() async {
    if (arrivingSoon) {
      await _readSeries();
      return;
    }
    var changed = false;
    for (final entry in requests.entries.toList()) {
      final before = entry.value;
      if (!before.status.isOpen) continue;
      try {
        final now = await service.request(entry.key);
        requests[entry.key] = now;
        if (now.status != before.status ||
            now.progress?.episodesDone != before.progress?.episodesDone) {
          changed = true;
        }
        if (now.status == StremfinRequestStatus.completed) {
          _sawCompletion = true;
        }
      } on StremfinException catch (e) {
        if (e.status != 404) rethrow;
        requests.remove(entry.key);
        changed = true;
      }
    }
    final readAt = _pageReadAt;
    final stale =
        readAt == null || clock.now().difference(readAt) >= pageInterval;
    if (changed || stale) await _readSeries();
  }

  /// Asks for [season], or for all that is missing when null.
  Future<void> ask({int? season}) {
    if (sending) return Future.value();
    sendingSeason = season ?? 0;
    return sendWith(() async {
      try {
        final result = await service.createRequest(
          type: StremfinTitleType.series,
          tmdbId: tmdbId,
          season: season,
        );
        onNotice?.call(KostvRequestNotice.outcome(result));
        final made = result.request;
        if (made != null) requests[made.id] = made;
        if (result.outcome != StremfinOutcome.limit) {
          await readQuietly(_readSeries);
        }
      } finally {
        sendingSeason = null;
      }
    });
  }

  /// Takes back one of their requests while it waits for an answer.
  Future<void> withdraw(StremfinRequest request) {
    if (!request.canWithdraw) return Future.value();
    return sendWith(() async {
      try {
        await service.withdrawRequest(request.id);
        onNotice?.call(const KostvRequestNotice.withdrawn());
      } on StremfinException catch (e) {
        if (e.code != 'already_answered' && e.status != 404) rethrow;
      }
      await readQuietly(_readSeries);
    });
  }
}
