import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/navigation_layout.dart';
import '../detail/detail_layout_metrics.dart';
import '../detail/frost/frost_detail_content.dart' show FrostStage;
import 'kostv_request_controller.dart';

/// Kos TV: the page of a film or series that isn't on the home server yet,
/// opened from Discover. It has the shape of a title's page, all in grey
/// but for its button: «Solicitar». Once asked for, the button says how the
/// request stands, asked again every few seconds while the page is in
/// sight, and when it arrives the page takes its colour and gives way to
/// its page on the home server.
class KostvRequestScreen extends StatefulWidget {
  const KostvRequestScreen({
    super.key,
    required this.type,
    required this.tmdbId,
    this.seed,
    @visibleForTesting this.controller,
  });

  final StremfinTitleType type;
  final int tmdbId;

  /// What the card said of it, to show while its page is read.
  final StremfinTitle? seed;

  /// Given by tests, already loaded.
  final KostvRequestController? controller;

  @override
  State<KostvRequestScreen> createState() => _KostvRequestScreenState();
}

/// How a main button looks.
enum _Tone { action, pending, progress, done, muted }

/// The page's main button: what pressing does, or how the request stands.
@immutable
class _Main {
  const _Main({
    required this.label,
    this.icon,
    this.tone = _Tone.action,
    this.onPressed,
    this.progress,
    this.fast = false,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final _Tone tone;
  final VoidCallback? onPressed;

  /// 0 to 1: how far the download has got, drawn inside the button.
  final double? progress;

  /// The ⚡: it would start at once.
  final bool fast;

  /// Waiting for an answer (a spinner instead of the icon).
  final bool busy;
}

/// A line of what the page knows.
@immutable
class _Note {
  const _Note(this.text, {this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;
}

/// A secondary button next to the main one.
@immutable
class _Extra {
  const _Extra(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// A figure on the data strip.
@immutable
class _Stat {
  const _Stat(
    this.label,
    this.value, {
    this.icon,
    this.color,
    this.busy = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  /// Still being worked out (a spinner before the value).
  final bool busy;
}

enum _StepState { done, current, upcoming, failed }

/// A step of the request's way.
@immutable
class _Step {
  const _Step(this.label, this.icon, this.state);

  final String label;
  final IconData icon;
  final _StepState state;
}

const _pendingColor = Color(0xFFF2A93B);

/// The bolt of a download that starts at once.
const _fastColor = Color(0xFFFFD54A);
const _doneColor = Color(0xFF2EAD5B);
const _alertColor = Color(0xFFE5675A);

class _KostvRequestScreenState extends State<KostvRequestScreen>
    with SingleTickerProviderStateMixin {
  late final KostvRequestController _c =
      widget.controller ??
      (widget.type == StremfinTitleType.movie
          ? KostvMovieRequestController(
              service: GetIt.instance<StremfinService>(),
              tmdbId: widget.tmdbId,
              seed: widget.seed,
            )
          : KostvSeriesRequestController(
              service: GetIt.instance<StremfinService>(),
              tmdbId: widget.tmdbId,
              seed: widget.seed,
            ));

  /// From grey (0) to colour (1), when it arrives.
  late final AnimationController _colour = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  final _mainNode = FocusNode(debugLabel: 'kostvRequestMain');
  final _extraNodes = <FocusNode>[];
  final _seasonNodes = <int, FocusNode>{};
  final _seasonScroll = ScrollController();
  int? _lastSeason;
  bool _leaving = false;

  /// The page has been on screen with what the service said of it.
  bool _sawPage = false;

  KostvMovieRequestController? get _movie =>
      _c is KostvMovieRequestController ? _c : null;
  KostvSeriesRequestController? get _series =>
      _c is KostvSeriesRequestController ? _c : null;

  UserPreferences get _prefs => GetIt.instance<UserPreferences>();

  bool get _navbarTop =>
      _prefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;

  @override
  void initState() {
    super.initState();
    _c.onNotice = _showNotice;
    _c.addListener(_onChange);
    if (widget.controller == null) {
      unawaited(_c.load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Asks again only while in sight: not under another page.
    _c.setVisible(ModalRoute.of(context)?.isCurrent ?? true);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.onNotice = null;
    if (widget.controller == null) _c.dispose();
    _colour.dispose();
    _mainNode.dispose();
    for (final node in _extraNodes) {
      node.dispose();
    }
    for (final node in _seasonNodes.values) {
      node.dispose();
    }
    _seasonScroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // A series already on the home server, missing some of it, is in colour;
    // one that gets there while the page is open turns to colour.
    final series = _series?.detail;
    if (series != null && series.title.isInLibrary && !_colour.isAnimating) {
      if (!_sawPage) {
        _colour.value = 1;
      } else if (_colour.value < 1) {
        unawaited(_colour.forward());
      }
    }
    if (_c.title != null && !_c.loading) _sawPage = true;
    final itemId = _c.arrivedItemId;
    if (itemId != null && !_leaving) {
      _leaving = true;
      if (_c.arrivedOnOpen) {
        // On the home server already: straight to its page.
        WidgetsBinding.instance.addPostFrameCallback((_) => _open(itemId));
      } else {
        // It has just arrived: the colour comes in, then its page.
        unawaited(
          _colour.forward().then((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 700));
            _open(itemId);
          }),
        );
      }
    }
    setState(() {});
  }

  void _open(String itemId) {
    if (!mounted) return;
    context.pushReplacement(Destinations.item(itemId));
  }

  void _showNotice(KostvRequestNotice notice) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final text = _noticeText(notice, l10n);
    if (text == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String? _noticeText(KostvRequestNotice notice, AppLocalizations l10n) {
    if (notice.withdrawn) return l10n.kostvRequestWithdrawn;
    final error = notice.error;
    if (error != null) {
      return error.status == 429
          ? l10n.kostvRequestTooFast
          : l10n.kostvRequestFailed;
    }
    final result = notice.result!;
    return switch (result.outcome) {
      StremfinOutcome.created => l10n.kostvRequestOutcomeCreated,
      StremfinOutcome.started => l10n.kostvRequestOutcomeStarted,
      StremfinOutcome.joined => l10n.kostvRequestOutcomeJoined,
      StremfinOutcome.watching => l10n.kostvRequestOutcomeWatching,
      StremfinOutcome.included => l10n.kostvRequestOutcomeIncluded,
      StremfinOutcome.already => l10n.kostvRequestOutcomeAlready,
      StremfinOutcome.have => l10n.kostvRequestOutcomeHave,
      StremfinOutcome.busy => l10n.kostvRequestOutcomeBusy,
      StremfinOutcome.unavailable => l10n.kostvRequestUnavailable,
      StremfinOutcome.limit => _limitText(l10n, daily: result.limit == 'daily'),
      StremfinOutcome.unknown => result.message,
    };
  }

  String _limitText(AppLocalizations l10n, {bool? daily}) {
    final me = _c.service.me;
    final isDaily = daily ?? me?.dailyLeft == 0;
    if (isDaily) return l10n.kostvRequestAtLimitDaily;
    final pending = me?.pending;
    final limit = me?.limit;
    if (pending != null && limit != null && limit > 0 && pending >= limit) {
      return l10n.kostvRequestAtLimitPending(pending);
    }
    return daily == false
        ? l10n.kostvRequestAtLimitPending(pending ?? limit ?? 1)
        : l10n.kostvRequestAtLimit;
  }

  // ---------------------------------------------------------------- texts

  String _duration(AppLocalizations l10n, int minutes) {
    if (minutes < 60) return l10n.minutesShort(minutes);
    return l10n.kostvHoursMinutes(minutes ~/ 60, minutes % 60);
  }

  /// Time left, short: «3 min», «1 h 20 min», «< 1 min».
  String _left(AppLocalizations l10n, int seconds) => seconds < 60
      ? l10n.kostvValueUnderAMinute
      : _duration(l10n, (seconds / 60).ceil());

  /// «9,0 GB».
  String _size(int bytes) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${NumberFormat('0.0', locale).format(gb)} GB';
    return '${NumberFormat('0', locale).format(bytes / (1024 * 1024))} MB';
  }

  String _speed(int bytesPerSecond) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final mb = bytesPerSecond / (1024 * 1024);
    if (mb >= 1) return '${NumberFormat('0.0', locale).format(mb)} MB/s';
    final kb = bytesPerSecond / 1024;
    return '${NumberFormat('0', locale).format(kb)} KB/s';
  }

  /// Who asked for it, from the person's point of view: «Tú», «Tú y Ana»,
  /// «Ana».
  String? _who(AppLocalizations l10n, StremfinRequest request) {
    final me = _c.service.me?.name;
    final others = [
      for (final name in request.requesters)
        if (name != me) name,
    ].join(', ');
    if (request.mine) {
      return others.isEmpty
          ? l10n.kostvValueYou
          : l10n.kostvValueYouAnd(others);
    }
    return others.isEmpty ? null : others;
  }

  /// The main button while a request is accepted: where its download is.
  _Main _progressMain(StremfinProgress? progress, AppLocalizations l10n) {
    final state = progress?.state ?? StremfinProgressState.accepted;
    final transfer = progress?.transfer ?? const StremfinTransfer();
    final percent = transfer.percent;
    switch (state) {
      case StremfinProgressState.accepted:
      case StremfinProgressState.unknown:
        return _Main(
          label: l10n.kostvRequestAccepted,
          icon: Icons.check_rounded,
          tone: _Tone.progress,
        );
      case StremfinProgressState.preparing:
        return _Main(
          label: l10n.kostvRequestLookingForEpisodes,
          icon: Icons.travel_explore_rounded,
          tone: _Tone.progress,
        );
      case StremfinProgressState.waitingVersion:
        return _Main(
          label: l10n.kostvRequestWaitingVersion,
          icon: Icons.hourglass_empty_rounded,
          tone: _Tone.pending,
        );
      case StremfinProgressState.attention:
        return _Main(
          label: l10n.kostvRequestUnderReview,
          icon: Icons.report_outlined,
          tone: _Tone.pending,
        );
      case StremfinProgressState.downloading:
        return _transferMain(transfer, l10n, percent: percent);
    }
  }

  _Main _transferMain(
    StremfinTransfer transfer,
    AppLocalizations l10n, {
    int? percent,
  }) {
    final fill = percent == null ? null : percent / 100;
    if (transfer.paused) {
      return _Main(
        label: l10n.kostvRequestPaused,
        icon: Icons.pause_rounded,
        tone: _Tone.progress,
        progress: fill,
      );
    }
    return switch (transfer.phase) {
      StremfinPhase.queued => _Main(
        label: l10n.kostvRequestQueued,
        icon: Icons.schedule_rounded,
        tone: _Tone.progress,
        progress: fill,
      ),
      StremfinPhase.preparing || null => _Main(
        label: l10n.kostvRequestPreparing,
        icon: Icons.downloading_rounded,
        tone: _Tone.progress,
        progress: fill,
      ),
      StremfinPhase.waitingFile => _Main(
        label: l10n.kostvRequestWaitingFile,
        icon: Icons.hourglass_top_rounded,
        tone: _Tone.progress,
        progress: fill,
      ),
      StremfinPhase.verifying => _Main(
        label: l10n.kostvRequestVerifying,
        icon: Icons.fact_check_outlined,
        tone: _Tone.progress,
        progress: 1,
      ),
      StremfinPhase.moving || StremfinPhase.completed => _Main(
        label: l10n.kostvRequestMoving,
        icon: Icons.drive_file_move_outline,
        tone: _Tone.progress,
        progress: 1,
      ),
      StremfinPhase.attention => _Main(
        label: l10n.kostvRequestUnderReview,
        icon: Icons.report_outlined,
        tone: _Tone.pending,
      ),
      StremfinPhase.downloading || StremfinPhase.unknown => _Main(
        label: percent == null
            ? l10n.kostvRequestDownloading
            : l10n.kostvRequestDownloadingPercent(percent),
        icon: Icons.download_rounded,
        tone: _Tone.progress,
        progress: fill,
      ),
    };
  }

  // ------------------------------------------------------ what's on show

  bool get _arrived => _c.arrivedItemId != null && !_c.arrivedOnOpen;

  _Main _mainFor(AppLocalizations l10n) {
    if (_arrived || _c.arrivingSoon) {
      return _Main(
        label: l10n.kostvRequestArrived,
        icon: Icons.check_circle_rounded,
        tone: _Tone.done,
      );
    }
    if (_c.loadError != null) {
      return _Main(
        label: l10n.retry,
        icon: Icons.refresh_rounded,
        onPressed: () => unawaited(_c.load()),
      );
    }
    final movie = _movie;
    if (movie != null) return _movieMain(movie, l10n);
    return _seriesMain(_series!, l10n);
  }

  _Main _requestMain(StremfinRequest request, AppLocalizations l10n) =>
      switch (request.status) {
        StremfinRequestStatus.pending => _Main(
          label: l10n.kostvRequestPending,
          icon: Icons.hourglass_top_rounded,
          tone: _Tone.pending,
        ),
        StremfinRequestStatus.completed => _Main(
          label: l10n.kostvRequestArrived,
          icon: Icons.check_circle_rounded,
          tone: _Tone.done,
        ),
        _ => _progressMain(request.progress, l10n),
      };

  _Main _movieMain(KostvMovieRequestController c, AppLocalizations l10n) {
    final request = c.request;
    if (request != null) return _requestMain(request, l10n);
    final detail = c.detail;
    final sending = c.sending;
    if (detail == null) {
      return _Main(
        label: l10n.kostvRequestAsk,
        icon: Icons.add_rounded,
        busy: true,
      );
    }
    final can = detail.canRequest;
    final download = detail.download;
    if (download != null && !can.allowed) {
      return _transferMain(
        download.transfer,
        l10n,
        percent: download.transfer.percent,
      );
    }
    if (!can.allowed) {
      return _Main(
        label: can.reason == 'already'
            ? l10n.kostvDiscoverRequested
            : l10n.kostvRequestUnavailable,
        icon: can.reason == 'already'
            ? Icons.check_rounded
            : Icons.block_rounded,
        tone: _Tone.muted,
      );
    }
    if (c.atLimit) return _limitMain(l10n);
    final onPressed = sending ? null : () => unawaited(c.ask());
    if (can.action == StremfinRequestAction.notify) {
      return _Main(
        label: l10n.kostvRequestNotifyMe,
        icon: Icons.notifications_active_outlined,
        onPressed: onPressed,
        busy: sending,
      );
    }
    final availability = c.availability;
    if (c.checkingAvailability) {
      return _Main(
        label: l10n.kostvRequestAsk,
        icon: Icons.add_rounded,
        busy: true,
      );
    }
    if (availability?.status == StremfinAvailabilityStatus.unavailable) {
      return _Main(
        label: l10n.kostvRequestUnavailable,
        icon: Icons.block_rounded,
        tone: _Tone.muted,
      );
    }
    if (availability?.status == StremfinAvailabilityStatus.waitingVersion) {
      return _Main(
        label: l10n.kostvRequestAskAndNotify,
        icon: Icons.notifications_active_outlined,
        onPressed: onPressed,
        busy: sending,
      );
    }
    return _Main(
      label: l10n.kostvRequestAsk,
      icon: (availability?.fast ?? false)
          ? Icons.bolt_rounded
          : Icons.add_rounded,
      fast: availability?.fast ?? false,
      onPressed: onPressed,
      busy: sending,
    );
  }

  /// The button, switched off, while the person can't ask for more.
  _Main _limitMain(AppLocalizations l10n) => _Main(
    label: l10n.kostvRequestLimitReached,
    icon: Icons.block_rounded,
    tone: _Tone.muted,
  );

  _Main _seriesMain(KostvSeriesRequestController c, AppLocalizations l10n) {
    final detail = c.detail;
    if (detail == null) {
      return _Main(
        label: l10n.kostvRequestAskAll,
        icon: Icons.add_rounded,
        busy: true,
      );
    }
    final whole = c.wholeRequest;
    if (whole != null && whole.status.isOpen) {
      return _requestMain(whole, l10n);
    }
    if (detail.canRequestAll) {
      if (c.atLimit) return _limitMain(l10n);
      return _Main(
        label: l10n.kostvRequestAskAll,
        icon: Icons.add_rounded,
        onPressed: c.sending ? null : () => unawaited(c.ask()),
        busy: c.sending && c.sendingSeason == 0,
      );
    }
    final itemId = detail.title.library.itemId;
    if (detail.title.isInLibrary && itemId != null) {
      return _Main(
        label: l10n.kostvRequestOpenInLibrary,
        icon: Icons.play_arrow_rounded,
        onPressed: () => context.push(Destinations.item(itemId)),
      );
    }
    final anyOpen = c.requests.values.any((r) => r.status.isOpen);
    return _Main(
      label: anyOpen
          ? l10n.kostvDiscoverRequested
          : l10n.kostvRequestUnavailable,
      icon: anyOpen ? Icons.check_rounded : Icons.block_rounded,
      tone: _Tone.muted,
    );
  }

  List<_Extra> _extrasFor(AppLocalizations l10n) {
    if (_arrived || _c.arrivingSoon) return const [];
    final extras = <_Extra>[];
    final movie = _movie;
    final series = _series;
    final StremfinRequest? own = movie?.request ?? series?.wholeRequest;
    if (own != null && own.canWithdraw) {
      extras.add(
        _Extra(l10n.kostvRequestWithdraw, Icons.undo_rounded, () {
          if (movie != null) {
            unawaited(movie.withdraw());
          } else {
            unawaited(series!.withdraw(own));
          }
        }),
      );
    }
    final detail = series?.detail;
    final itemId = detail?.title.library.itemId;
    if (detail != null &&
        detail.title.isInLibrary &&
        itemId != null &&
        (detail.canRequestAll || (own?.status.isOpen ?? false))) {
      extras.add(
        _Extra(
          l10n.kostvRequestOpenInLibrary,
          Icons.play_arrow_rounded,
          () => context.push(Destinations.item(itemId)),
        ),
      );
    }
    while (_extraNodes.length < extras.length) {
      _extraNodes.add(FocusNode(debugLabel: 'kostvRequestExtra'));
    }
    return extras;
  }

  /// The request this page follows as a whole: a film's, or a series' for
  /// all that is missing.
  StremfinRequest? get _request => _movie?.request ?? _series?.wholeRequest;

  /// A download under way: of the request, or of a film coming down for
  /// someone else.
  ({StremfinTransfer transfer, StremfinProgress? progress})? get _download {
    final request = _request;
    if (request != null) {
      final progress = request.progress;
      if (request.status == StremfinRequestStatus.approved &&
          progress != null &&
          progress.state == StremfinProgressState.downloading) {
        return (transfer: progress.transfer, progress: progress);
      }
      return null;
    }
    final download = _movie?.detail?.download;
    if (download == null) return null;
    return (transfer: download.transfer, progress: null);
  }

  /// Whether the page offers asking for something now.
  bool get _canAsk {
    final movie = _movie;
    if (movie != null) {
      return _request == null && (movie.detail?.canRequest.allowed ?? false);
    }
    final detail = _series?.detail;
    return (detail?.canRequestAll ?? false) ||
        (detail?.seasons.any((s) => s.canRequest) ?? false);
  }

  /// The data strip under the title, as on the home server's page: what it
  /// would bring before asking, how the request goes after.
  List<_Stat> _statsFor(AppLocalizations l10n) {
    if (_c.loadError != null || _arrived) return const [];
    final accent = AppColorScheme.accent;
    final availability = _movie?.availability;
    final download = _download;
    if (download != null) {
      final t = download.transfer;
      final total = download.progress?.episodesTotal;
      final size = t.totalBytes ?? availability?.sizeBytes;
      return [
        if (total != null && total > 0)
          _Stat(
            l10n.kostvStatEpisodes,
            l10n.kostvValueOf(download.progress?.episodesDone ?? 0, total),
          ),
        _Stat(
          l10n.kostvStatProgress,
          t.percent == null ? '—' : l10n.kostvPercent(t.percent!),
          color: accent,
        ),
        if (t.paused)
          _Stat(
            l10n.kostvStatStatus,
            l10n.kostvRequestPaused,
            color: _pendingColor,
          )
        else ...[
          if ((t.speed ?? 0) > 0) _Stat(l10n.kostvStatSpeed, _speed(t.speed!)),
          if (t.etaSeconds != null)
            _Stat(l10n.kostvStatTimeLeft, _left(l10n, t.etaSeconds!)),
        ],
        if (size != null && size > 0) _Stat(l10n.kostvStatSize, _size(size)),
      ].take(4).toList();
    }
    final request = _request;
    if (request != null && request.status.isOpen) {
      final pending = request.status == StremfinRequestStatus.pending;
      final who = _who(l10n, request);
      final missing = _series?.detail?.missing;
      return [
        _Stat(
          l10n.kostvStatStatus,
          pending ? l10n.kostvValuePending : l10n.kostvStepApproved,
          color: pending ? _pendingColor : accent,
        ),
        if (who != null) _Stat(l10n.kostvStatRequestedBy, who),
        if (missing != null && missing > 0)
          _Stat(l10n.kostvStatMissing, '$missing'),
        ..._versionStats(l10n, availability),
      ].take(4).toList();
    }
    final series = _series?.detail;
    if (series != null) {
      return [
        _Stat(l10n.seasons, '${series.seasons.length}'),
        _Stat(l10n.kostvStatEpisodes, '${series.aired}'),
        _Stat(l10n.kostvStatAtHome, '${series.have}'),
        _Stat(l10n.kostvStatMissing, '${series.missing}'),
      ];
    }
    final movie = _movie;
    if (movie == null || movie.detail == null) return const [];
    if (movie.checkingAvailability) {
      return [
        _Stat(l10n.kostvStatAvailability, l10n.kostvValueChecking, busy: true),
      ];
    }
    if (availability == null) return const [];
    switch (availability.status) {
      case StremfinAvailabilityStatus.ready:
        final version = _versionStats(l10n, availability);
        final summary = availability.summary;
        return [
          if (version.isNotEmpty)
            ...version
          else if (summary != null)
            _Stat(l10n.kostvStatVersion, summary),
          _Stat(
            l10n.kostvStatDownload,
            availability.fast ? l10n.kostvRequestFast : l10n.kostvValueNormal,
            icon: availability.fast ? Icons.bolt_rounded : null,
            color: availability.fast ? _fastColor : null,
          ),
        ];
      case StremfinAvailabilityStatus.waitingVersion:
        final release = availability.release ?? movie.detail?.release;
        final locale = Localizations.localeOf(context).toLanguageTag();
        final date = release?.date;
        return [
          if (availability.reason == 'not_released' && release != null)
            _Stat(
              l10n.kostvStatRelease,
              date != null
                  ? DateFormat.yMd(locale).format(date)
                  : (release.text ?? '—'),
            ),
          _Stat(
            l10n.kostvStatVersion,
            availability.reason == 'quality'
                ? l10n.kostvValueNoGoodOneYet
                : l10n.kostvValueNoneYet,
          ),
          if (availability.reason != 'not_released' &&
              availability.criterion != null)
            _Stat(l10n.kostvStatWanted, _capitalized(availability.criterion!)),
        ];
      case StremfinAvailabilityStatus.unavailable:
        return [
          _Stat(l10n.kostvStatAvailability, l10n.kostvRequestUnavailable),
        ];
      default:
        return const [];
    }
  }

  String _capitalized(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// The quality, language and size of the version it would bring.
  List<_Stat> _versionStats(AppLocalizations l10n, StremfinAvailability? a) {
    if (a == null || a.status != StremfinAvailabilityStatus.ready) {
      return const [];
    }
    final size = a.sizeBytes;
    return [
      if (a.resolution case final resolution?)
        _Stat(
          l10n.kostvStatQuality,
          a.hdr == null ? resolution : '$resolution ${a.hdr}',
        ),
      if (a.language case final language?)
        _Stat(l10n.kostvStatLanguage, language),
      if (size != null && size > 0) _Stat(l10n.kostvStatSize, _size(size)),
    ];
  }

  /// How far the download has got, for the strip's line.
  double? get _stripProgress {
    final percent = _download?.transfer.percent;
    return percent == null ? null : percent / 100;
  }

  /// The request's way, from asking to watching at home: where it is.
  List<_Step>? _journeyFor(AppLocalizations l10n) {
    if (_c.loadError != null || _c.loading) return null;
    final movie = _movie;
    final request = _request;
    final rejected = request == null ? movie?.rejected : null;
    final home =
        _arrived ||
        _c.arrivingSoon ||
        request?.status == StremfinRequestStatus.completed;
    final othersDownload = request == null && movie?.detail?.download != null;
    if (!home && request == null && !othersDownload) {
      if (_c.atLimit) return null;
      // Nothing under way: the way ahead, if it can be asked for.
      final series = _series;
      if (series != null) {
        if (!_canAsk || series.requests.values.any((r) => r.status.isOpen)) {
          return null;
        }
      } else if (!_canAsk && rejected == null) {
        return null;
      }
    }
    final review = request != null
        ? !request.direct
        : rejected != null ||
              (movie?.availability?.needsApproval ?? _c.needsApproval);
    // 0 nothing asked, 1 waiting for an answer, 2 coming down, 3 at home.
    final int stage;
    if (home) {
      stage = 3;
    } else if (request == null) {
      stage = othersDownload ? 2 : (rejected != null ? 1 : 0);
    } else {
      stage = request.status == StremfinRequestStatus.pending ? 1 : 2;
    }
    _StepState at(int step) => stage > step
        ? _StepState.done
        : (stage == step ? _StepState.current : _StepState.upcoming);
    return [
      _Step(
        stage >= 1 ? l10n.kostvStepAsked : l10n.kostvStepAsk,
        Icons.send_rounded,
        stage >= 1 ? _StepState.done : _StepState.upcoming,
      ),
      if (review)
        rejected != null
            ? _Step(
                l10n.kostvStepRejected,
                Icons.close_rounded,
                _StepState.failed,
              )
            : _Step(
                stage >= 2 ? l10n.kostvStepApproved : l10n.kostvStepApproval,
                Icons.how_to_reg_rounded,
                at(1),
              ),
      _Step(l10n.kostvStepDownload, Icons.download_rounded, at(2)),
      _Step(
        l10n.kostvStepHome,
        Icons.home_rounded,
        home ? _StepState.done : _StepState.upcoming,
      ),
    ];
  }

  /// The one thing worth saying besides the strip, if any.
  _Note? _noteFor(AppLocalizations l10n) {
    if (_arrived) return null;
    if (_c.loadError != null) {
      return _Note(
        l10n.kostvRequestLoadFailed,
        icon: Icons.cloud_off_rounded,
        color: _alertColor,
      );
    }
    if (_c.arrivingSoon) {
      return _Note(l10n.kostvRequestArrivingSoon, icon: Icons.schedule_rounded);
    }
    final movie = _movie;
    final request = _request;
    if (_canAsk && _c.atLimit) {
      return _Note(
        _limitText(l10n),
        icon: Icons.block_rounded,
        color: _alertColor,
      );
    }
    final rejected = request == null ? movie?.rejected : null;
    if (rejected != null) {
      return _Note(
        switch (rejected.reason) {
          'quality' => l10n.kostvRequestRejectedQuality,
          'later' => l10n.kostvRequestRejectedLater,
          _ => l10n.kostvRequestRejected,
        },
        icon: Icons.do_not_disturb_on_outlined,
        color: _alertColor,
      );
    }
    if (request != null) {
      if (request.status == StremfinRequestStatus.pending) {
        return _Note(
          l10n.kostvRequestUpdatesOnItsOwn,
          icon: Icons.autorenew_rounded,
        );
      }
      final progress = request.progress;
      final transfer = progress?.transfer;
      if (progress?.state == StremfinProgressState.attention ||
          transfer?.phase == StremfinPhase.attention) {
        return _Note(
          l10n.kostvRequestAttention,
          icon: Icons.report_outlined,
          color: _pendingColor,
        );
      }
      if (progress?.state == StremfinProgressState.waitingVersion) {
        return _Note(
          l10n.kostvRequestDownloadsWhenReady,
          icon: Icons.notifications_active_outlined,
        );
      }
      final since = transfer?.waitingSince;
      if (transfer?.phase == StremfinPhase.waitingFile && since != null) {
        final minutes = math.max(1, DateTime.now().difference(since).inMinutes);
        return _Note(
          '${l10n.kostvRequestWaitingFile} · '
          '${l10n.kostvRequestWaitingSince(minutes)}',
          icon: Icons.hourglass_top_rounded,
        );
      }
      return null;
    }
    if (movie?.detail?.download?.attention ?? false) {
      return _Note(
        l10n.kostvRequestAttention,
        icon: Icons.report_outlined,
        color: _pendingColor,
      );
    }
    if (!_canAsk) return null;
    final availability = movie?.availability;
    if (availability?.status == StremfinAvailabilityStatus.waitingVersion) {
      // What is looked for is on the strip; this says what asking does.
      return _Note(
        l10n.kostvRequestDownloadsWhenReady,
        icon: Icons.notifications_active_outlined,
      );
    }
    if (availability?.needsApproval ?? _c.needsApproval) {
      return _Note(
        l10n.kostvRequestNeedsApproval,
        icon: Icons.admin_panel_settings_outlined,
      );
    }
    final release = movie?.detail?.release?.text;
    if (release != null) return _Note(release, icon: Icons.event_outlined);
    return null;
  }

  /// The label over the title: not at home yet, or here at last.
  (String, Color)? _kickerFor(AppLocalizations l10n) {
    if (_arrived || _c.arrivingSoon) {
      return (l10n.kostvRequestArrived, _doneColor);
    }
    final title = _c.title;
    if (title == null || title.isInLibrary) return null;
    return (l10n.kostvRequestNotHomeYet, _ink(0.78));
  }

  /// Year, length or seasons, genres and rating.
  List<String> _metaParts(AppLocalizations l10n) {
    final title = _c.title;
    final movie = _movie?.detail;
    final series = _series?.detail;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rating = title?.rating;
    return [
      ?(series?.years ?? title?.year?.toString()),
      if (movie?.runtime case final minutes? when minutes > 0)
        _duration(l10n, minutes),
      if ((movie?.genres ?? series?.genres) case final genres?
          when genres.isNotEmpty)
        genres.take(3).join(', '),
      if (rating != null && rating > 0)
        '★ ${NumberFormat('0.0', locale).format(rating)}',
    ];
  }

  String? get _art => _c.title?.backdrop ?? _c.title?.poster;

  // ------------------------------------------------------------- the page

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = detailUsesLandscapeLayout(context);
    final page = wide ? _wide(l10n) : _narrow(l10n);
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvDiscover,
        showBackButton: true,
        child: page,
      ),
    );
  }

  /// Grey until it arrives, then the colour comes in.
  Widget _tinted(Widget child) => AnimatedBuilder(
    animation: _colour,
    builder: (context, child) => ColorFiltered(
      colorFilter: _saturation(Curves.easeInOut.transform(_colour.value)),
      child: child,
    ),
    child: child,
  );

  /// The art, blurred and dimmed, behind everything.
  Widget _environment() {
    final url = _art;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: AppColorScheme.background),
        if (url != null)
          _tinted(
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 96,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ColoredBox(color: AppColorScheme.background.withValues(alpha: 0.6)),
      ],
    );
  }

  Widget _image({Alignment alignment = Alignment.center}) {
    final url = _art;
    if (url == null) return const SizedBox.shrink();
    return _tinted(
      Image.network(
        url,
        fit: BoxFit.cover,
        alignment: alignment,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  Color _ink([double alpha = 1]) =>
      AppColorScheme.onBackground.withValues(alpha: alpha);
  Color _shade(double alpha) =>
      AppColorScheme.background.withValues(alpha: alpha);

  Widget _glass({
    required Widget child,
    required double radius,
    EdgeInsetsGeometry? padding,
    double tint = 0.5,
  }) => glassPane(
    tier: GlassSettings.tier == GlassTier.solid
        ? GlassTier.sheen
        : GlassSettings.tier,
    fallbackColor: AppColorScheme.surface.withValues(alpha: tint),
    cornerRadius: radius,
    padding: padding,
    shadow: true,
    context: context,
    child: child,
  );

  /// TV, computer and a phone on its side: the shape of Frost, the
  /// home server's page there.
  Widget _wide(AppLocalizations l10n) {
    final title = _c.title;
    final main = _mainFor(l10n);
    final extras = _extrasFor(l10n);
    final stats = _statsFor(l10n);
    final journey = _journeyFor(l10n);
    final note = _noteFor(l10n);
    final kicker = _kickerFor(l10n);
    final series = _series;
    final seasons = series?.detail?.seasons ?? const <StremfinSeason>[];
    final hasSeasons = seasons.isNotEmpty;
    final name = title?.title ?? '';
    final long = name.length > (hasSeasons ? 18 : 26);

    final text = Padding(
      padding: EdgeInsets.fromLTRB(56, 0, hasSeasons ? 516 : 56, 46),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (kicker != null) ...[
            _kicker(kicker, fontSize: 13),
            const SizedBox(height: 14),
          ],
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink(),
              fontSize: long ? 50 : 64,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: long ? -1.1 : -1.6,
            ),
          ),
          const SizedBox(height: 12),
          _metaLine(l10n, fontSize: 15),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 18),
            _strip(stats, _stripProgress, wide: true),
          ],
          if (title?.overview case final overview?) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                overview,
                maxLines: note == null && !long ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink(0.86), fontSize: 18, height: 1.44),
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 16),
            _noteChip(note, fontSize: 15),
          ],
        ],
      ),
    );

    final window = Positioned(
      left: 24,
      right: 24,
      top: 12,
      bottom: 146,
      child: _glass(
        radius: 44,
        tint: 0.36,
        child: ClipRRect(
          borderRadius: AppRadius.circular(44),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _image(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [_shade(0.96), _shade(0.8), _shade(0.1)],
                    stops: const [0, 0.55, 0.92],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_shade(0.55), _shade(0)],
                    stops: const [0, 0.65],
                  ),
                ),
              ),
              text,
              if (hasSeasons)
                Positioned(
                  top: 30,
                  right: 30,
                  bottom: 30,
                  width: 436,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _glass(
                      radius: 30,
                      tint: 0.6,
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                            child: _heading(
                              l10n.seasons,
                              count: seasons.length,
                              fontSize: 13,
                            ),
                          ),
                          Flexible(
                            child: _seasonList(
                              series!,
                              seasons,
                              l10n,
                              wide: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_c.loading && _c.title == null)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );

    final toolbar = Positioned(
      left: 24,
      right: 24,
      bottom: 106,
      child: Center(
        child: _glass(
          radius: 38,
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              _mainButton(
                main,
                height: 56,
                fontSize: 19,
                minWidth: 240,
                onRight: extras.isEmpty
                    ? null
                    : () => _extraNodes.first.requestFocus(),
                onUp: () => _fromBottomUp(seasons),
              ),
              for (final (index, extra) in extras.indexed)
                _extraButton(
                  extra,
                  _extraNodes[index],
                  height: 56,
                  onLeft: index == 0
                      ? _mainNode.requestFocus
                      : _extraNodes[index - 1].requestFocus,
                  onRight: index + 1 < extras.length
                      ? _extraNodes[index + 1].requestFocus
                      : null,
                  onUp: () => _fromBottomUp(seasons),
                ),
            ],
          ),
        ),
      ),
    );

    // Where Frost has its tabs: the request's way, step by step.
    final journeyBar = journey == null
        ? null
        : Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Center(
              child: _glass(
                radius: 30,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 11,
                ),
                child: _journey(journey, wide: true),
              ),
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        _environment(),
        FrostStage(
          navbarTop: _navbarTop,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Stack(
              clipBehavior: Clip.none,
              children: [window, toolbar, ?journeyBar],
            ),
          ),
        ),
      ],
    );
  }

  /// A phone held upright: the shape of the home server's page there, the
  /// art on top and the button across.
  Widget _narrow(AppLocalizations l10n) {
    final title = _c.title;
    final main = _mainFor(l10n);
    final extras = _extrasFor(l10n);
    final stats = _statsFor(l10n);
    final journey = _journeyFor(l10n);
    final note = _noteFor(l10n);
    final kicker = _kickerFor(l10n);
    final series = _series;
    final seasons = series?.detail?.seasons ?? const <StremfinSeason>[];
    final width = MediaQuery.sizeOf(context).width;
    final heroHeight = math.min(width * 0.95, 440.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        _environment(),
        BottomNavPadded(
          fallback: 24,
          builder: (context, bottom) => ListView(
            padding: EdgeInsets.only(bottom: bottom + 28),
            children: [
              SizedBox(
                height: heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, 0.5, 1],
                      ).createShader(rect),
                      child: _image(alignment: Alignment.topCenter),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [_shade(0.55), _shade(0)],
                          stops: const [0, 0.6],
                        ),
                      ),
                    ),
                    if (_c.loading && _c.title == null)
                      const Center(child: CircularProgressIndicator()),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (kicker != null) ...[
                            _kicker(kicker, fontSize: 11.5),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            title?.title ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink(),
                              fontSize: 32,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _metaLine(l10n, fontSize: 14.5, maxLines: 2),
                    if (stats.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _strip(stats, _stripProgress, wide: false),
                    ],
                    if (title?.overview case final overview?) ...[
                      const SizedBox(height: 16),
                      Text(
                        overview,
                        style: TextStyle(
                          color: _ink(0.86),
                          fontSize: 15.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _mainButton(main, height: 54, fontSize: 18, expand: true),
                    for (final (index, extra) in extras.indexed) ...[
                      const SizedBox(height: 10),
                      _extraButton(
                        extra,
                        _extraNodes[index],
                        height: 48,
                        expand: true,
                      ),
                    ],
                    if (journey != null) ...[
                      const SizedBox(height: 22),
                      _journey(journey, wide: false),
                    ],
                    if (note != null) ...[
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _noteChip(note, fontSize: 14),
                      ),
                    ],
                    if (seasons.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 12),
                        child: _heading(
                          l10n.seasons,
                          count: seasons.length,
                          fontSize: 12.5,
                        ),
                      ),
                      _seasonList(series!, seasons, l10n, wide: false),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A small capitals heading, as Frost's, with how many there are.
  Widget _heading(String text, {int? count, required double fontSize}) =>
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.toUpperCase()),
            if (count != null)
              TextSpan(
                text: '  $count',
                style: TextStyle(color: _ink(0.38)),
              ),
          ],
        ),
        style: TextStyle(
          color: _ink(0.62),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      );

  /// Year, length, genres and rating, with quiet dots between.
  Widget _metaLine(
    AppLocalizations l10n, {
    required double fontSize,
    int maxLines = 1,
  }) {
    final parts = _metaParts(l10n);
    return Text.rich(
      TextSpan(
        children: [
          for (final (index, part) in parts.indexed) ...[
            if (index > 0)
              TextSpan(
                text: '   ·   ',
                style: TextStyle(color: _ink(0.35)),
              ),
            TextSpan(text: part),
          ],
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _ink(0.82),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );
  }

  /// The label over the title.
  Widget _kicker((String, Color) kicker, {required double fontSize}) {
    final (text, color) = kicker;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.8,
        vertical: fontSize * 0.38,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(fontSize * 0.55),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          height: 1.1,
        ),
      ),
    );
  }

  /// The figures between two hairlines, a column each, as the ratings on
  /// the home server's page. The lower hairline fills as it comes down.
  Widget _strip(List<_Stat> stats, double? progress, {required bool wide}) {
    final labelSize = wide ? 13.0 : 10.5;
    final valueSize = wide ? 28.0 : 19.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: _ink(0.14)),
        SizedBox(
          height: wide ? 96 : 70,
          child: Row(
            children: [
              for (final (index, stat) in stats.indexed)
                Expanded(
                  child: Container(
                    decoration: index == 0
                        ? null
                        : BoxDecoration(
                            border: Border(left: BorderSide(color: _ink(0.14))),
                          ),
                    padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Shrunk to fit a narrow column rather than cut.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            stat.label.toUpperCase(),
                            maxLines: 1,
                            style: TextStyle(
                              color: _ink(0.58),
                              fontSize: labelSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: wide ? 0.6 : 0.3,
                            ),
                          ),
                        ),
                        SizedBox(height: wide ? 5 : 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (stat.busy) ...[
                                SizedBox(
                                  width: valueSize * 0.62,
                                  height: valueSize * 0.62,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: _ink(0.8),
                                  ),
                                ),
                                SizedBox(width: valueSize * 0.3),
                              ] else if (stat.icon != null) ...[
                                Icon(
                                  stat.icon,
                                  size: valueSize * 0.9,
                                  color: stat.color ?? _ink(0.92),
                                ),
                                SizedBox(width: valueSize * 0.12),
                              ],
                              Text(
                                stat.value,
                                maxLines: 1,
                                style: TextStyle(
                                  color: stat.color ?? _ink(0.94),
                                  fontSize: valueSize,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        _progressLine(progress),
      ],
    );
  }

  Widget _progressLine(double? progress) {
    if (progress == null) return Container(height: 1, color: _ink(0.14));
    final accent = AppColorScheme.accent;
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _ink(0.12)),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The request's way: asked, accepted, coming down, at home.
  Widget _journey(List<_Step> steps, {required bool wide}) {
    final accent = AppColorScheme.accent;
    Color tone(_StepState state) => switch (state) {
      _StepState.done || _StepState.current => accent,
      _StepState.failed => _alertColor,
      _StepState.upcoming => _ink(0.32),
    };
    Widget dot(_Step step, double size) {
      final color = tone(step.state);
      final solid =
          step.state == _StepState.done || step.state == _StepState.failed;
      final current = step.state == _StepState.current;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: solid
              ? color
              : (current ? color.withValues(alpha: 0.2) : Colors.transparent),
          border: Border.all(color: color, width: current ? 2.4 : 1.5),
          boxShadow: current
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Icon(
          switch (step.state) {
            _StepState.done => Icons.check_rounded,
            _StepState.failed => Icons.close_rounded,
            _ => step.icon,
          },
          size: size * 0.56,
          color: solid ? Colors.white : (current ? color : _ink(0.42)),
        ),
      );
    }

    TextStyle labelStyle(_Step step, double fontSize) => TextStyle(
      fontSize: fontSize,
      fontWeight: step.state == _StepState.current
          ? FontWeight.w800
          : FontWeight.w600,
      color: switch (step.state) {
        _StepState.failed => _alertColor,
        _StepState.current => _ink(),
        _StepState.done => _ink(0.8),
        _StepState.upcoming => _ink(0.42),
      },
    );

    bool reached(int index) => steps[index].state != _StepState.upcoming;
    Widget line(bool lit) => Container(
      height: 2,
      decoration: BoxDecoration(
        color: lit ? accent.withValues(alpha: 0.8) : _ink(0.16),
        borderRadius: BorderRadius.circular(1),
      ),
    );

    if (wide) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, step) in steps.indexed) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(width: 46, child: line(reached(index))),
              ),
            dot(step, 28),
            const SizedBox(width: 10),
            Text(step.label, style: labelStyle(step, 16)),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in steps.indexed) ...[
          if (index > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: line(reached(index)),
              ),
            ),
          SizedBox(
            width: 76,
            child: Column(
              children: [
                dot(step, 26),
                const SizedBox(height: 7),
                Text(
                  step.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle(step, 12),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One thing to say, as a quiet label.
  Widget _noteChip(_Note note, {required double fontSize}) {
    final color = note.color;
    final ink = color ?? _ink(0.86);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.85,
        vertical: fontSize * 0.55,
      ),
      decoration: BoxDecoration(
        color: (color ?? Colors.white).withValues(
          alpha: color == null ? 0.07 : 0.12,
        ),
        borderRadius: BorderRadius.circular(fontSize * 0.9),
        border: Border.all(
          color: (color ?? Colors.white).withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note.icon != null) ...[
            Icon(note.icon, size: fontSize * 1.2, color: ink),
            SizedBox(width: fontSize * 0.55),
          ],
          Flexible(
            child: Text(
              note.text,
              style: TextStyle(
                color: ink,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- buttons

  Color _toneColor(_Tone tone) => switch (tone) {
    _Tone.action => AppColorScheme.accent,
    _Tone.pending => _pendingColor,
    _Tone.progress => AppColorScheme.accent,
    _Tone.done => _doneColor,
    _Tone.muted => _ink(0.35),
  };

  /// Up from the buttons: the seasons, or the navbar on top.
  void _fromBottomUp(List<StremfinSeason> seasons) {
    if (seasons.isNotEmpty) {
      final last = _lastSeason;
      final target = last != null && _seasonNodes.containsKey(last)
          ? last
          : seasons.first.number;
      _seasonNodes[target]?.requestFocus();
      return;
    }
    if (_navbarTop) NavigationLayout.focusNavbarNotifier.value?.call();
  }

  void _toSidebar() {
    if (!_navbarTop) NavigationLayout.focusNavbarNotifier.value?.call();
  }

  Widget _mainButton(
    _Main main, {
    required double height,
    required double fontSize,
    double minWidth = 0,
    bool expand = false,
    VoidCallback? onRight,
    VoidCallback? onUp,
  }) {
    final color = _toneColor(main.tone);
    final onColor = main.tone == _Tone.action
        ? AppColorScheme.onAccent
        : Colors.white;
    final pressable = main.onPressed != null;
    // A status shows on a darker plate, filled as far as it has got.
    final filled = main.tone == _Tone.action || main.tone == _Tone.done;
    final progress = main.progress;
    return _PageFocus(
      focusNode: _mainNode,
      autofocus: !PlatformDetection.useMobileUi,
      onSelect: main.onPressed,
      onLeft: _toSidebar,
      onRight: onRight,
      onUp: onUp,
      onDown: () {},
      builder: (context, focused) {
        final lit = InputModeTracker.showFocusVisuals(context, focused);
        final radius = BorderRadius.circular(height / 2);
        final enabled = pressable || main.tone != _Tone.action;
        final background = filled
            ? (enabled ? color : color.withValues(alpha: 0.4))
            : Color.alphaBlend(color.withValues(alpha: 0.22), _shade(0.7));
        final label = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (main.busy)
              SizedBox(
                width: fontSize,
                height: fontSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: onColor,
                ),
              )
            else if (main.icon != null)
              Icon(
                main.icon,
                size: fontSize * 1.3,
                color: main.fast ? _fastColor : onColor,
                shadows: main.fast
                    ? const [Shadow(color: Colors.black26, blurRadius: 6)]
                    : null,
              ),
            SizedBox(width: fontSize * 0.5),
            Flexible(
              child: Text(
                main.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
        return AnimatedScale(
          scale: lit ? 1.05 : 1,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: height,
            constraints: BoxConstraints(minWidth: minWidth),
            width: expand ? double.infinity : null,
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(
                color: lit
                    ? Colors.white
                    : (filled
                          ? Colors.transparent
                          : color.withValues(alpha: 0.7)),
                width: lit ? 3 : 1.5,
              ),
              boxShadow: [
                if (lit || main.tone == _Tone.action)
                  BoxShadow(
                    color: color.withValues(alpha: lit ? 0.6 : 0.35),
                    blurRadius: lit ? 22 : 14,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (progress != null)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          color: color.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: height * 0.45),
                    child: Center(widthFactor: 1, child: label),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _extraButton(
    _Extra extra,
    FocusNode node, {
    required double height,
    bool expand = false,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onUp,
  }) => _PageFocus(
    focusNode: node,
    onSelect: extra.onPressed,
    onLeft: onLeft,
    onRight: onRight,
    onUp: onUp,
    onDown: () {},
    builder: (context, focused) {
      final lit = InputModeTracker.showFocusVisuals(context, focused);
      return AnimatedScale(
        scale: lit ? 1.05 : 1,
        duration: const Duration(milliseconds: 160),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: height * 0.4),
          decoration: BoxDecoration(
            color: lit ? Colors.white : _ink(0.1),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: _ink(lit ? 0 : 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                extra.icon,
                size: 22,
                color: lit ? Colors.black87 : _ink(0.9),
              ),
              const SizedBox(width: 8),
              Text(
                extra.label,
                style: TextStyle(
                  color: lit ? Colors.black87 : _ink(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ------------------------------------------------------------- seasons

  FocusNode _seasonNode(int season) =>
      _seasonNodes.putIfAbsent(season, () => FocusNode(debugLabel: 'T$season'));

  Widget _seasonList(
    KostvSeriesRequestController c,
    List<StremfinSeason> seasons,
    AppLocalizations l10n, {
    required bool wide,
  }) {
    final rows = [
      for (final (index, season) in seasons.indexed)
        _seasonRow(c, season, l10n, wide: wide, index: index, seasons: seasons),
    ];
    if (!wide) return Column(spacing: 8, children: rows);
    return ListView.separated(
      controller: _seasonScroll,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, index) => rows[index],
    );
  }

  Widget _seasonRow(
    KostvSeriesRequestController c,
    StremfinSeason season,
    AppLocalizations l10n, {
    required bool wide,
    required int index,
    required List<StremfinSeason> seasons,
  }) {
    final request = c.requestFor(season);
    final own = request != null && request.id != c.wholeRequest?.id
        ? request
        : null;
    final sendingThis = c.sending && c.sendingSeason == season.number;
    final canAsk = season.canRequest && !c.atLimit && !c.sending;
    final complete = season.status == StremfinSeasonStatus.complete;

    final String subtitle = switch (season.status) {
      StremfinSeasonStatus.complete =>
        '${l10n.kostvSeasonEpisodeCount(season.aired)} · '
            '${l10n.kostvRequestSeasonComplete}',
      StremfinSeasonStatus.upcoming => l10n.kostvRequestSeasonUpcoming,
      StremfinSeasonStatus.downloading =>
        '${l10n.kostvRequestSeasonOnItsWay} · '
            '${l10n.kostvSeasonAtHome(season.have, season.aired)}',
      _ => l10n.kostvSeasonAtHome(season.have, season.aired),
    };

    // What the row offers or says on its right.
    final _Main? chip;
    VoidCallback? onSelect;
    if (own != null && own.status.isOpen) {
      chip = _requestMain(own, l10n);
      if (own.canWithdraw) onSelect = () => _confirmWithdraw(c, own, season);
    } else if (season.canRequest && !c.atLimit) {
      final joins = season.request != null && !(season.request?.mine ?? false);
      chip = _Main(
        label: joins
            ? l10n.kostvRequestMeToo
            : (wide
                  ? l10n.kostvRequestAsk
                  : l10n.kostvRequestAskSeason(season.number)),
        icon: Icons.add_rounded,
        onPressed: canAsk
            ? () => unawaited(c.ask(season: season.number))
            : null,
        busy: sendingThis,
      );
      onSelect = chip.onPressed;
    } else {
      chip = null;
    }

    final node = _seasonNode(season.number);
    final have = season.aired == 0 ? 0.0 : season.have / season.aired;
    final percent = own?.progress?.transfer.percent;
    // What is missing fills as it comes down, after what is already there.
    final coming = percent == null ? null : have + (1 - have) * percent / 100;
    return _PageFocus(
      focusNode: node,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (!focused) return;
        _lastSeason = season.number;
        unawaited(
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          ),
        );
      },
      onUp: index > 0
          ? _seasonNode(seasons[index - 1].number).requestFocus
          : () {
              if (_navbarTop) {
                NavigationLayout.focusNavbarNotifier.value?.call();
              }
            },
      onDown: index + 1 < seasons.length
          ? _seasonNode(seasons[index + 1].number).requestFocus
          : _mainNode.requestFocus,
      onLeft: _toSidebar,
      onRight: () {},
      builder: (context, focused) {
        final lit = InputModeTracker.showFocusVisuals(context, focused);
        final chipColor = chip == null ? null : _toneColor(chip.tone);
        return AnimatedScale(
          scale: lit ? 1.02 : 1,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: lit ? _ink(0.15) : _ink(0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: lit ? Colors.white.withValues(alpha: 0.9) : _ink(0.08),
                width: lit ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _ink(complete ? 0.16 : 0.07),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _ink(0.1)),
                  ),
                  child: Text(
                    '${season.number}',
                    style: TextStyle(
                      color: _ink(complete ? 0.95 : 0.8),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.seasonNumber(season.number),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ink(),
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _ink(0.6), fontSize: 13),
                      ),
                      if (season.aired > 0) ...[
                        const SizedBox(height: 8),
                        _seasonBar(have, coming),
                      ],
                    ],
                  ),
                ),
                if (chip != null && chipColor != null) ...[
                  const SizedBox(width: 12),
                  _SeasonChip(
                    main: chip,
                    color: chipColor,
                    onColor: chip.tone == _Tone.action
                        ? AppColorScheme.onAccent
                        : Colors.white,
                    maxWidth: wide ? 200 : 170,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// How much of a season is at home (grey) and coming down (colour).
  Widget _seasonBar(double have, double? coming) {
    final accent = AppColorScheme.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _ink(0.1)),
            if (coming != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: coming.clamp(0.0, 1.0),
                child: ColoredBox(color: accent),
              ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: have.clamp(0.0, 1.0),
              child: ColoredBox(color: _ink(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWithdraw(
    KostvSeriesRequestController c,
    StremfinRequest request,
    StremfinSeason season,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name =
        '${_c.title?.title ?? ''} · ${l10n.seasonNumber(season.number)}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.kostvRequestWithdrawQuestion(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.kostvRequestWithdraw),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.withdraw(request);
  }
}

/// What a season row offers or says, on its right.
class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.main,
    required this.color,
    required this.onColor,
    required this.maxWidth,
  });

  final _Main main;
  final Color color;
  final Color onColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final filled = main.tone == _Tone.action;
    final progress = main.progress;
    final enabled = main.onPressed != null || !filled;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: filled
              ? (enabled ? color : color.withValues(alpha: 0.4))
              : color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(19),
          border: filled
              ? null
              : Border.all(color: color.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (progress != null)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ColoredBox(color: color.withValues(alpha: 0.55)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (main.busy)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onColor,
                      ),
                    )
                  else if (main.icon != null)
                    Icon(main.icon, size: 18, color: onColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      main.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A focus stop for the remote, the mouse and touch: each arrow callback
/// takes the press when it's set.
class _PageFocus extends StatefulWidget {
  const _PageFocus({
    required this.focusNode,
    required this.builder,
    this.onSelect,
    this.onFocusChange,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool autofocus;

  @override
  State<_PageFocus> createState() => _PageFocusState();
}

class _PageFocusState extends State<_PageFocus> {
  bool _focused = false;
  bool _hovered = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (isActivateKey(event)) {
      widget.onSelect?.call();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final action = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => widget.onLeft,
      LogicalKeyboardKey.arrowRight => widget.onRight,
      LogicalKeyboardKey.arrowUp => widget.onUp,
      LogicalKeyboardKey.arrowDown => widget.onDown,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    onFocusChange: (focused) {
      setState(() => _focused = focused);
      widget.onFocusChange?.call(focused);
    },
    onKeyEvent: _onKey,
    child: MouseRegion(
      cursor: widget.onSelect == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: widget.builder(context, _focused || _hovered),
      ),
    ),
  );
}

/// From grey ([amount] 0, a little dimmed) to its own colour (1).
ColorFilter _saturation(double amount) {
  final s = amount.clamp(0.0, 1.0);
  final dim = lerpDouble(0.72, 1, s)!;
  const r = 0.2126, g = 0.7152, b = 0.0722;
  List<double> row(int channel) {
    final values = [r * (1 - s), g * (1 - s), b * (1 - s)];
    values[channel] += s;
    return [for (final v in values) v * dim, 0, 0];
  }

  return ColorFilter.matrix([...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0]);
}
