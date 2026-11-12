import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/stremfin_client.dart';
import '../../../data/services/stremfin/stremfin_inbox.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../detail/detail_layout_metrics.dart';
import 'kostv_request_status.dart';

/// Kos TV: opens the requests tray: a glass panel sliding in from the left
/// on a TV, a computer or a phone on its side, a page of its own on a phone
/// held upright.
Future<void> showKostvRequestsTray(BuildContext context) {
  if (!detailUsesLandscapeLayout(context)) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const KostvRequestsTray(panel: false),
      ),
    );
  }
  final l10n = AppLocalizations.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.kostvTrayOpen,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const KostvRequestsTray(panel: true),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Kos TV: the person's own requests: what is new to them, what is under
/// way (followed live while it is open) and what finished. Opening it counts
/// the news as seen.
class KostvRequestsTray extends StatefulWidget {
  const KostvRequestsTray({super.key, required this.panel});

  /// A panel at the left of the screen (TV, computer), or a whole page.
  final bool panel;

  @override
  State<KostvRequestsTray> createState() => _KostvRequestsTrayState();
}

const _pendingColor = Color(0xFFF2A93B);
const _doneColor = Color(0xFF2EAD5B);
const _alertColor = Color(0xFFE5675A);

/// The grey of a title not at home yet, a little dimmed.
const _grey = ColorFilter.matrix([
  0.2126 * 0.75, 0.7152 * 0.75, 0.0722 * 0.75, 0, 0, //
  0.2126 * 0.75, 0.7152 * 0.75, 0.0722 * 0.75, 0, 0, //
  0.2126 * 0.75, 0.7152 * 0.75, 0.0722 * 0.75, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class _KostvRequestsTrayState extends State<KostvRequestsTray> {
  final StremfinService _service = GetIt.instance<StremfinService>();
  StremfinInbox get _inbox => _service.inbox;

  /// What was news when the tray opened (and what turned news while open):
  /// shown as news while it stays open, already counted as seen.
  final Set<int> _news = {};
  final Map<String, FocusNode> _nodes = {};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _news.addAll(_inbox.news.map((r) => r.id));
    unawaited(_inbox.markAllSeen());
    _inbox.addListener(_onInbox);
    _service.addListener(_onInbox);
    unawaited(_inbox.sync());
    _inbox.watch();
  }

  @override
  void dispose() {
    _inbox.unwatch();
    _inbox.removeListener(_onInbox);
    _service.removeListener(_onInbox);
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onInbox() {
    if (!mounted) return;
    // Something arrived while the person is looking: news, and seen.
    final fresh = _inbox.news.map((r) => r.id).toList();
    if (fresh.isNotEmpty) {
      _news.addAll(fresh);
      unawaited(_inbox.markAllSeen());
    }
    setState(() {});
  }

  FocusNode _node(String key) =>
      _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'tray-$key'));

  void _close() => Navigator.of(context).maybePop();

  void _open(StremfinRequest request) {
    final type = request.type;
    final tmdbId = request.tmdbId;
    if (type == null || tmdbId == null) return;
    // Its page: grey while on its way, the home server's page once there.
    unawaited(context.push(Destinations.kostvRequestOf(type.apiValue, tmdbId)));
  }

  Future<void> _withdraw(StremfinRequest request) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          l10n.kostvRequestWithdrawQuestion(
            request.displayTitle ?? request.title ?? '',
          ),
        ),
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
    if (confirmed != true || !mounted) return;
    try {
      await _service.withdrawRequest(request.id);
      if (!mounted) return;
      _snack(l10n.kostvRequestWithdrawn);
    } on StremfinException {
      if (!mounted) return;
      _snack(l10n.kostvRequestFailed);
      unawaited(_inbox.sync());
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // --------------------------------------------------------------- texts

  String _ago(AppLocalizations l10n, DateTime? at) {
    if (at == null) return '';
    final since = DateTime.now().difference(at);
    if (since.inMinutes < 1) return l10n.justNow;
    if (since.inHours < 1) return l10n.minutesAgo(since.inMinutes);
    if (since.inDays < 1) return l10n.hoursAgo(since.inHours);
    return l10n.daysAgo(since.inDays);
  }

  String _speed(int bytesPerSecond) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final mb = bytesPerSecond / (1024 * 1024);
    if (mb >= 1) return '${NumberFormat('0.0', locale).format(mb)} MB/s';
    return '${NumberFormat('0', locale).format(bytesPerSecond / 1024)} KB/s';
  }

  String _left(AppLocalizations l10n, int seconds) {
    if (seconds < 60) return l10n.kostvValueUnderAMinute;
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return l10n.minutesShort(minutes);
    return l10n.kostvHoursMinutes(minutes ~/ 60, minutes % 60);
  }

  /// Under the status of one coming down: episodes, speed and time left.
  String? _details(AppLocalizations l10n, StremfinRequest request) {
    final progress = request.progress;
    if (progress == null) return null;
    final t = progress.transfer;
    final total = progress.episodesTotal;
    final parts = [
      if (total != null && total > 0)
        l10n.kostvTrayEpisodes(progress.episodesDone ?? 0, total),
      if (!t.paused && (t.speed ?? 0) > 0) _speed(t.speed!),
      if (!t.paused && t.etaSeconds != null)
        l10n.kostvTrayTimeLeft(_left(l10n, t.etaSeconds!)),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Color _ink([double alpha = 1]) =>
      AppColorScheme.onBackground.withValues(alpha: alpha);

  Color _tone(KostvTone tone) => switch (tone) {
    KostvTone.pending => _pendingColor,
    KostvTone.done => _doneColor,
    KostvTone.failed => _alertColor,
    KostvTone.muted => _ink(0.5),
    _ => AppColorScheme.accent,
  };

  // ---------------------------------------------------------------- page

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final panel = widget.panel;
    final content = _content(l10n, panel: panel);
    if (!panel) {
      return Scaffold(
        backgroundColor: AppColorScheme.background,
        body: SafeArea(child: content),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = (width * 0.42).clamp(400.0, 640.0);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: panelWidth,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              AppColorScheme.surface.withValues(alpha: 0.9),
              AppColorScheme.background,
            ),
            border: Border(right: BorderSide(color: _ink(0.1))),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)],
          ),
          child: SafeArea(right: false, child: content),
        ),
      ),
    );
  }

  Widget _content(AppLocalizations l10n, {required bool panel}) {
    final inbox = _inbox;
    final all = [...inbox.active, ...inbox.finished];
    final news = [
      for (final request in [...inbox.active, ...inbox.finished])
        if (_news.contains(request.id)) request,
    ];
    final active = [
      for (final r in inbox.active)
        if (!_news.contains(r.id)) r,
    ];
    final finished = [
      for (final r in inbox.finished)
        if (!_news.contains(r.id)) r,
    ];
    final rows = <({String key, StremfinRequest request, bool isNew})>[
      for (final r in news) (key: 'n${r.id}', request: r, isNew: true),
      for (final r in active) (key: 'a${r.id}', request: r, isNew: false),
      for (final r in finished) (key: 'f${r.id}', request: r, isNew: false),
    ];

    final Widget body;
    if (!inbox.isLoaded) {
      body = Center(
        child: inbox.failed
            ? _message(
                l10n,
                icon: Icons.cloud_off_rounded,
                title: l10n.kostvTrayLoadFailed,
                action: (l10n.retry, () => unawaited(inbox.sync())),
              )
            : const CircularProgressIndicator(),
      );
    } else if (all.isEmpty) {
      body = Center(
        child: _message(
          l10n,
          icon: Icons.inbox_outlined,
          title: l10n.kostvTrayEmpty,
          hint: l10n.kostvTrayEmptyHint,
          action: (
            l10n.kostvTrayGoDiscover,
            () {
              final router = GoRouter.of(context);
              _close();
              router.go(Destinations.kostvDiscover);
            },
          ),
        ),
      );
    } else {
      var index = 0;
      Widget row(({String key, StremfinRequest request, bool isNew}) entry) {
        final at = index++;
        return _row(
          l10n,
          entry.request,
          key: entry.key,
          isNew: entry.isNew,
          panel: panel,
          up: at > 0 ? rows[at - 1].key : null,
          down: at + 1 < rows.length ? rows[at + 1].key : null,
          first: at == 0,
        );
      }

      body = ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(panel ? 20 : 12, 4, panel ? 20 : 12, 28),
        children: [
          if (news.isNotEmpty) ...[
            _heading(l10n.kostvTrayNews, news.length, dot: true),
            for (final entry in rows.where((r) => r.isNew)) row(entry),
          ],
          if (active.isNotEmpty) ...[
            _heading(l10n.kostvTrayActive, active.length),
            for (final entry in rows.where((r) => r.key.startsWith('a')))
              row(entry),
          ],
          if (finished.isNotEmpty) ...[
            _heading(l10n.kostvTrayFinished, finished.length),
            for (final entry in rows.where((r) => r.key.startsWith('f')))
              row(entry),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(l10n, panel: panel),
        Expanded(child: body),
      ],
    );
  }

  Widget _header(AppLocalizations l10n, {required bool panel}) {
    final me = _service.me;
    final quota = [
      if (me?.dailyLeft case final left?) l10n.kostvTrayQuotaDaily(left),
      if (me?.limit case final limit? when limit > 0)
        l10n.kostvTrayQuotaPending(me?.pending ?? 0, limit),
    ].join('  ·  ');
    final atLimit = me?.atLimit ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(panel ? 32 : 8, panel ? 30 : 8, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!panel)
            IconButton(
              onPressed: _close,
              icon: const Icon(Icons.arrow_back_rounded),
              color: _ink(0.9),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
          if (panel) ...[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColorScheme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.inbox_rounded,
                color: AppColorScheme.accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.kostvTrayTitle,
                  style: TextStyle(
                    color: _ink(),
                    fontSize: panel ? 30 : 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (atLimit || quota.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    atLimit ? l10n.kostvRequestLimitReached : quota,
                    maxLines: 2,
                    style: TextStyle(
                      color: atLimit ? _alertColor : _ink(0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text, int count, {bool dot = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
    child: Row(
      children: [
        if (dot) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColorScheme.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: _ink(0.62),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            color: _ink(0.38),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _message(
    AppLocalizations l10n, {
    required IconData icon,
    required String title,
    String? hint,
    (String, VoidCallback)? action,
  }) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: _ink(0.35)),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink(0.9),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: _ink(0.6), fontSize: 14.5),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            autofocus: !PlatformDetection.useMobileUi,
            onPressed: action.$2,
            child: Text(action.$1),
          ),
        ],
      ],
    ),
  );

  Widget _row(
    AppLocalizations l10n,
    StremfinRequest request, {
    required String key,
    required bool isNew,
    required bool panel,
    required String? up,
    required String? down,
    required bool first,
  }) {
    final status = kostvRequestStatus(l10n, request);
    final color = _tone(status.tone);
    final details = request.status == StremfinRequestStatus.approved
        ? _details(l10n, request)
        : null;
    final arrived = request.status == StremfinRequestStatus.completed;
    final node = _node(key);
    final withdrawKey = '$key-w';
    final canWithdraw = request.canWithdraw;
    final title = request.displayTitle ?? request.title ?? '';
    final progress = status.progress;

    final row = _TrayFocus(
      focusNode: node,
      autofocus: first && !PlatformDetection.useMobileUi,
      onSelect: () => _open(request),
      onUp: up == null ? () {} : _node(up).requestFocus,
      onDown: down == null ? () {} : _node(down).requestFocus,
      onRight: canWithdraw ? _node(withdrawKey).requestFocus : () {},
      onLeft: _close,
      onFocused: () => unawaited(
        Scrollable.ensureVisible(
          node.context!,
          alignment: 0.4,
          duration: const Duration(milliseconds: 200),
        ),
      ),
      builder: (context, focused) {
        final lit = InputModeTracker.showFocusVisuals(context, focused);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: lit
                ? _ink(0.14)
                : (isNew
                      ? AppColorScheme.accent.withValues(alpha: 0.08)
                      : _ink(0.04)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: lit
                  ? Colors.white.withValues(alpha: 0.9)
                  : (isNew
                        ? AppColorScheme.accent.withValues(alpha: 0.35)
                        : _ink(0.07)),
              width: lit ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _poster(request, grey: !arrived, panel: panel),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink(),
                              fontSize: panel ? 17 : 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(l10n, request.lastChange),
                          style: TextStyle(color: _ink(0.45), fontSize: 12.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (status.icon != null) ...[
                          Icon(status.icon, size: 16, color: color),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            status.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (progress != null &&
                        status.tone == KostvTone.progress) ...[
                      const SizedBox(height: 8),
                      _bar(progress),
                    ],
                    if (details != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _ink(0.6), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (canWithdraw) ...[
                const SizedBox(width: 10),
                _withdrawButton(l10n, request, withdrawKey, key),
              ] else if (!panel || lit)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _ink(lit ? 0.9 : 0.35),
                  ),
                ),
            ],
          ),
        );
      },
    );
    return row;
  }

  Widget _withdrawButton(
    AppLocalizations l10n,
    StremfinRequest request,
    String key,
    String rowKey,
  ) => _TrayFocus(
    focusNode: _node(key),
    onSelect: () => unawaited(_withdraw(request)),
    onLeft: _node(rowKey).requestFocus,
    onRight: () {},
    onUp: () {},
    onDown: () {},
    builder: (context, focused) {
      final lit = InputModeTracker.showFocusVisuals(context, focused);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: lit ? Colors.white : _ink(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _ink(lit ? 0 : 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.undo_rounded,
              size: 17,
              color: lit ? Colors.black87 : _ink(0.85),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.kostvTrayWithdraw,
              style: TextStyle(
                color: lit ? Colors.black87 : _ink(0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _poster(
    StremfinRequest request, {
    required bool grey,
    required bool panel,
  }) {
    final width = panel ? 52.0 : 46.0;
    final url = request.poster;
    final placeholder = Container(
      color: _ink(0.08),
      alignment: Alignment.center,
      child: Icon(
        request.type == StremfinTitleType.series
            ? Icons.tv_rounded
            : Icons.movie_outlined,
        color: _ink(0.35),
        size: 22,
      ),
    );
    final image = url == null
        ? placeholder
        : Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 120,
            errorBuilder: (_, _, _) => placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: width * 1.5,
        child: grey ? ColorFiltered(colorFilter: _grey, child: image) : image,
      ),
    );
  }

  Widget _bar(double progress) {
    final accent = AppColorScheme.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _ink(0.12)),
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 600),
              builder: (_, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: math.max(0.0, value),
                child: ColoredBox(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A focus stop for the remote, the mouse and touch.
class _TrayFocus extends StatefulWidget {
  const _TrayFocus({
    required this.focusNode,
    required this.builder,
    this.onSelect,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onFocused,
    this.autofocus = false,
  });

  final FocusNode focusNode;
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onFocused;
  final bool autofocus;

  @override
  State<_TrayFocus> createState() => _TrayFocusState();
}

class _TrayFocusState extends State<_TrayFocus> {
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
      if (focused) widget.onFocused?.call();
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
