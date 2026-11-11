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

const _pendingColor = Color(0xFFF2A93B);
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

  String _eta(AppLocalizations l10n, int seconds) {
    if (seconds < 60) return l10n.kostvRequestLessThanAMinute;
    return _duration(l10n, (seconds / 60).ceil());
  }

  String _speed(int bytesPerSecond) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final mb = bytesPerSecond / (1024 * 1024);
    if (mb >= 1) return '${NumberFormat('0.0', locale).format(mb)} MB/s';
    final kb = bytesPerSecond / 1024;
    return '${NumberFormat('0', locale).format(kb)} KB/s';
  }

  String _names(List<String> names) => names.join(', ');

  /// Who asked for it, from the person's point of view.
  String? _requesters(
    AppLocalizations l10n, {
    required bool mine,
    required List<String> requesters,
  }) {
    final me = _c.service.me?.name;
    final others = [
      for (final name in requesters)
        if (name != me) name,
    ];
    if (mine) {
      return others.isEmpty
          ? l10n.kostvRequestRequestedByYou
          : l10n.kostvRequestRequestedByYouAnd(_names(others));
    }
    if (others.isEmpty) return null;
    return l10n.kostvRequestRequestedBy(_names(others));
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

  /// The live line under the button: speed and time left, episodes, how
  /// long it has waited.
  String? _transferLine(
    StremfinTransfer transfer,
    AppLocalizations l10n, {
    StremfinProgress? progress,
  }) {
    final parts = <String>[
      if (progress?.episodesTotal case final total? when total > 0)
        l10n.kostvRequestEpisodesDone(progress!.episodesDone ?? 0, total),
      if (transfer.phase == StremfinPhase.waitingFile &&
          transfer.waitingSince != null)
        l10n.kostvRequestWaitingSince(
          math.max(
            1,
            DateTime.now().difference(transfer.waitingSince!).inMinutes,
          ),
        ),
      if (transfer.speed case final speed? when speed > 0 && !transfer.paused)
        _speed(speed),
      if (transfer.etaSeconds case final eta? when !transfer.paused)
        l10n.kostvRequestTimeLeft(_eta(l10n, eta)),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
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
    final onPressed = c.atLimit || sending ? null : () => unawaited(c.ask());
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
      icon: Icons.add_rounded,
      fast: availability?.fast ?? false,
      onPressed: onPressed,
      busy: sending,
    );
  }

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
      return _Main(
        label: l10n.kostvRequestAskAll,
        icon: Icons.add_rounded,
        onPressed: c.atLimit || c.sending ? null : () => unawaited(c.ask()),
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

  /// The live line: how the download goes, or how fast it would be.
  _Note? _statusFor(AppLocalizations l10n) {
    if (_arrived) return null;
    if (_c.arrivingSoon) {
      return _Note(l10n.kostvRequestArrivingSoon, icon: Icons.schedule_rounded);
    }
    final movie = _movie;
    final series = _series;
    final StremfinRequest? request = movie?.request ?? series?.wholeRequest;
    if (request != null) {
      if (request.status == StremfinRequestStatus.pending) {
        return _Note(
          l10n.kostvRequestUpdatesOnItsOwn,
          icon: Icons.autorenew_rounded,
        );
      }
      final progress = request.progress;
      if (progress?.state == StremfinProgressState.attention) {
        return _Note(l10n.kostvRequestAttention, icon: Icons.report_outlined);
      }
      if (progress?.state == StremfinProgressState.waitingVersion) {
        return _Note(
          l10n.kostvRequestDownloadsWhenReady,
          icon: Icons.notifications_active_outlined,
        );
      }
      final line = progress == null
          ? null
          : _transferLine(progress.transfer, l10n, progress: progress);
      return line == null ? null : _Note(line, icon: Icons.speed_rounded);
    }
    if (movie == null) return null;
    final download = movie.detail?.download;
    if (download != null) {
      if (download.attention) {
        return _Note(l10n.kostvRequestAttention, icon: Icons.report_outlined);
      }
      final where = _transferMain(
        download.transfer,
        l10n,
        percent: download.transfer.percent,
      ).label;
      final line = _transferLine(download.transfer, l10n);
      return _Note(
        line == null ? where : '$where · $line',
        icon: Icons.download_rounded,
      );
    }
    if (movie.detail == null || movie.detail?.canRequest.allowed != true) {
      return null;
    }
    if (movie.checkingAvailability) {
      return _Note(
        l10n.kostvRequestChecking,
        icon: Icons.travel_explore_rounded,
      );
    }
    final availability = movie.availability;
    if (availability == null) return null;
    switch (availability.status) {
      case StremfinAvailabilityStatus.ready:
        final summary = availability.summary;
        final head = availability.fast
            ? l10n.kostvRequestFastNote
            : l10n.kostvRequestSlowNote;
        return _Note(
          summary == null ? head : '$head · $summary',
          icon: availability.fast
              ? Icons.bolt_rounded
              : Icons.hourglass_bottom_rounded,
          color: availability.fast ? _pendingColor : null,
        );
      case StremfinAvailabilityStatus.waitingVersion:
        final release = availability.release?.text;
        final criterion = availability.criterion;
        final head =
            release ??
            (availability.reason == 'quality' && criterion != null
                ? l10n.kostvRequestNoGoodVersion(criterion)
                : l10n.kostvRequestNoVersionYet);
        return _Note(head, icon: Icons.event_outlined);
      default:
        return null;
    }
  }

  /// What else the page has to say, under the overview.
  List<_Note> _notesFor(AppLocalizations l10n) {
    if (_arrived) return const [];
    final notes = <_Note>[];
    if (_c.loadError != null) {
      notes.add(
        _Note(
          l10n.kostvRequestLoadFailed,
          icon: Icons.cloud_off_rounded,
          color: _alertColor,
        ),
      );
      return notes;
    }
    final movie = _movie;
    final series = _series;
    final StremfinRequest? request = movie?.request ?? series?.wholeRequest;
    if (request != null) {
      final who = _requesters(
        l10n,
        mine: request.mine,
        requesters: request.requesters,
      );
      if (who != null) notes.add(_Note(who, icon: Icons.person_outline));
    }
    final rejected = movie?.rejected;
    if (request == null && rejected != null) {
      notes.add(
        _Note(
          switch (rejected.reason) {
            'quality' => l10n.kostvRequestRejectedQuality,
            'later' => l10n.kostvRequestRejectedLater,
            _ => l10n.kostvRequestRejected,
          },
          icon: Icons.do_not_disturb_on_outlined,
          color: _alertColor,
        ),
      );
    }
    final canAsk = movie != null
        ? request == null && (movie.detail?.canRequest.allowed ?? false)
        : (series?.detail?.canRequestAll ?? false) ||
              (series?.detail?.seasons.any((s) => s.canRequest) ?? false);
    if (canAsk && _c.atLimit) {
      notes.add(
        _Note(_limitText(l10n), icon: Icons.block_rounded, color: _alertColor),
      );
    } else if (canAsk &&
        (movie?.availability?.needsApproval ?? _c.needsApproval)) {
      notes.add(
        _Note(
          l10n.kostvRequestNeedsApproval,
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
    }
    final waiting =
        movie?.availability?.status ==
        StremfinAvailabilityStatus.waitingVersion;
    if (movie != null && canAsk && waiting) {
      notes.add(
        _Note(
          l10n.kostvRequestDownloadsWhenReady,
          icon: Icons.notifications_active_outlined,
        ),
      );
    }
    final release = movie?.detail?.release?.text;
    if (release != null && !waiting) {
      notes.add(_Note(release, icon: Icons.event_outlined));
    }
    final detail = series?.detail;
    if (detail != null && detail.missing > 0) {
      notes.add(
        _Note(
          l10n.kostvRequestSeriesMissing(detail.missing),
          icon: Icons.video_library_outlined,
        ),
      );
    }
    return notes;
  }

  /// Year, length, genres and rating.
  String _meta(AppLocalizations l10n) {
    final title = _c.title;
    final movie = _movie?.detail;
    final series = _series?.detail;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rating = title?.rating;
    return [
      series?.years ?? title?.year?.toString(),
      if (movie?.runtime case final minutes? when minutes > 0)
        _duration(l10n, minutes),
      if (series != null && series.seasons.isNotEmpty)
        l10n.kostvSeasonsCount(series.seasons.length),
      ...?(movie?.genres ?? series?.genres)?.take(3),
      if (rating != null && rating > 0)
        '★ ${NumberFormat('0.0', locale).format(rating)}',
    ].whereType<String>().join('  ·  ');
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
    final status = _statusFor(l10n);
    final notes = _notesFor(l10n);
    final series = _series;
    final seasons = series?.detail?.seasons ?? const <StremfinSeason>[];
    final hasSeasons = seasons.isNotEmpty;

    final text = Padding(
      padding: EdgeInsets.fromLTRB(56, 0, hasSeasons ? 520 : 56, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            title?.title ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink(),
              fontSize: hasSeasons ? 52 : 64,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _meta(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink(0.78),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (title?.overview case final overview?) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 744,
              child: Text(
                overview,
                maxLines: notes.length > 1 ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink(0.88), fontSize: 18, height: 1.44),
              ),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final note in notes) _noteLine(note, fontSize: 15),
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
                    colors: [_shade(0.95), _shade(0.74), _shade(0)],
                    stops: const [0, 0.5, 0.8],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_shade(0.5), _shade(0)],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
              text,
              if (hasSeasons)
                Positioned(
                  top: 28,
                  right: 28,
                  bottom: 28,
                  width: 440,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _glass(
                      radius: 30,
                      tint: 0.55,
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                            child: Text(
                              l10n.seasons.toUpperCase(),
                              style: TextStyle(
                                color: _ink(0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              ),
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
                minWidth: 280,
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

    final statusBar = status == null
        ? null
        : Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Center(
              child: _glass(
                radius: 26,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: _noteLine(
                    status,
                    fontSize: 16,
                    bottom: 0,
                    center: true,
                  ),
                ),
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
              children: [window, toolbar, ?statusBar],
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
    final status = _statusFor(l10n);
    final notes = _notesFor(l10n);
    final series = _series;
    final seasons = series?.detail?.seasons ?? const <StremfinSeason>[];
    final width = MediaQuery.sizeOf(context).width;
    final heroHeight = math.min(width * 0.9, 420.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        _environment(),
        BottomNavPadded(
          fallback: 24,
          builder: (context, bottom) => ListView(
            padding: EdgeInsets.only(bottom: bottom + 24),
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
                        stops: [0, 0.55, 1],
                      ).createShader(rect),
                      child: _image(alignment: Alignment.topCenter),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [_shade(0.45), _shade(0)],
                          stops: const [0, 0.6],
                        ),
                      ),
                    ),
                    if (_c.loading && _c.title == null)
                      const Center(child: CircularProgressIndicator()),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 8,
                      child: Text(
                        title?.title ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ink(),
                          fontSize: 32,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _meta(l10n),
                      style: TextStyle(
                        color: _ink(0.72),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (title?.overview case final overview?) ...[
                      const SizedBox(height: 14),
                      Text(
                        overview,
                        style: TextStyle(
                          color: _ink(0.88),
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _mainButton(main, height: 54, fontSize: 18, expand: true),
                    if (status != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: _noteLine(
                          status,
                          fontSize: 14,
                          center: true,
                          bottom: 0,
                        ),
                      ),
                    ],
                    for (final (index, extra) in extras.indexed) ...[
                      const SizedBox(height: 10),
                      _extraButton(
                        extra,
                        _extraNodes[index],
                        height: 48,
                        expand: true,
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      for (final note in notes) _noteLine(note, fontSize: 14),
                    ],
                    if (seasons.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        l10n.seasons,
                        style: TextStyle(
                          color: _ink(),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
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

  Widget _noteLine(
    _Note note, {
    required double fontSize,
    bool center = false,
    double bottom = 6,
  }) {
    final color = note.color ?? _ink(0.82);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: fontSize * 0.12),
              child: Icon(note.icon, size: fontSize * 1.2, color: color),
            ),
            SizedBox(width: fontSize * 0.5),
          ],
          Flexible(
            child: Text(
              note.text,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                height: 1.35,
                fontWeight: FontWeight.w500,
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
              Icon(main.icon, size: fontSize * 1.3, color: onColor),
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
            if (main.fast) ...[
              SizedBox(width: fontSize * 0.6),
              _FastBadge(fontSize: fontSize * 0.72),
            ],
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

    final String subtitle = switch (season.status) {
      StremfinSeasonStatus.complete => l10n.kostvRequestSeasonComplete,
      StremfinSeasonStatus.upcoming => l10n.kostvRequestSeasonUpcoming,
      StremfinSeasonStatus.downloading => l10n.kostvRequestSeasonOnItsWay,
      _ => l10n.kostvRequestSeasonEpisodes(season.have, season.aired),
    };

    // What the row offers or says on its right.
    final _Main? chip;
    VoidCallback? onSelect;
    if (own != null && own.status.isOpen) {
      chip = _requestMain(own, l10n);
      if (own.canWithdraw) onSelect = () => _confirmWithdraw(c, own, season);
    } else if (season.canRequest) {
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
    } else if (season.status == StremfinSeasonStatus.complete) {
      chip = _Main(
        label: l10n.kostvRequestSeasonComplete,
        icon: Icons.check_rounded,
        tone: _Tone.done,
      );
    } else {
      chip = null;
    }

    final node = _seasonNode(season.number);
    final transfer = own?.progress?.transfer;
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
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            color: lit ? _ink(0.16) : _ink(0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: lit ? Colors.white.withValues(alpha: 0.85) : _ink(0.08),
              width: lit ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.seasonNumber(season.number),
                      style: TextStyle(
                        color: _ink(),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        subtitle,
                        if (transfer != null)
                          ?_transferLine(
                            transfer,
                            l10n,
                            progress: own?.progress,
                          ),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _ink(0.65), fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              if (chip != null && chipColor != null) ...[
                const SizedBox(width: 10),
                _SeasonChip(
                  main: chip,
                  color: chipColor,
                  onColor: chip.tone == _Tone.action
                      ? AppColorScheme.onAccent
                      : Colors.white,
                  maxWidth: wide ? 210 : 180,
                ),
              ],
            ],
          ),
        );
      },
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

/// The ⚡ of a film whose download would start at once.
class _FastBadge extends StatelessWidget {
  const _FastBadge({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.kostvRequestFastNote,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.5,
          vertical: fontSize * 0.18,
        ),
        decoration: BoxDecoration(
          color: _pendingColor,
          borderRadius: BorderRadius.circular(fontSize),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt_rounded,
              size: fontSize * 1.25,
              color: Colors.black,
            ),
            Text(
              l10n.kostvRequestFast,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
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
