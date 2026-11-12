import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/stremfin/kostv_series_gaps.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../adaptive/adaptive_glass.dart';
import '../kostv_missing_episodes.dart';

/// How asking for the missing episodes went, on the player's card.
enum KostvGapAsk { idle, sending, sent, failed }

/// Kos TV: the card at the end of an episode when the next ones aren't at
/// home. It says which, offers asking for them, and playing the next one
/// that is at home; it never moves on by itself.
///
/// Its first button takes [focusNode] and its second [secondFocusNode], the
/// two the player moves between with Left and Right.
class KostvGapOverlay extends StatelessWidget {
  const KostvGapOverlay({
    super.key,
    required this.missing,
    required this.next,
    required this.ask,
    required this.onAsk,
    required this.onWatchNext,
    required this.onClose,
    this.atLimit = false,
    this.sentNote,
    this.focusNode,
    this.secondFocusNode,
  });

  /// The episodes missing right after the one that ended, in order.
  final List<KostvGhostEpisode> missing;

  /// The next episode at home, if there's one.
  final AggregatedItem? next;
  final KostvGapAsk ask;
  final bool atLimit;

  /// The service's word on the request, once sent.
  final String? sentNote;
  final VoidCallback onAsk;
  final VoidCallback onWatchNext;
  final VoidCallback onClose;
  final FocusNode? focusNode;
  final FocusNode? secondFocusNode;

  bool get _askable => missing.any((g) => g.canAsk);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final first = missing.first;
    final last = missing.last;
    final count = missing.length;
    final askable = _askable && ask != KostvGapAsk.sent;
    final canSend = askable && !atLimit && ask != KostvGapAsk.sending;
    final next = this.next;

    final headline = count == 1
        ? l10n.kostvGapOne(first.number)
        : l10n.kostvGapMany(first.number, last.number);
    final subtitle = count == 1 ? KostvGhostTexts.ownTitle(first) : null;
    final pill = count == 1
        ? 'S${first.season}:E${first.number}'
        : 'S${first.season}:E${first.number}–${last.number}';

    // What the card says about them, under the title.
    final (IconData, String)? status = switch (ask) {
      KostvGapAsk.sent => (
        Icons.check_circle_outline,
        sentNote ?? l10n.kostvGapRequested(count),
      ),
      KostvGapAsk.failed => (Icons.error_outline, l10n.kostvRequestFailed),
      _ when askable && atLimit => (
        Icons.hourglass_empty,
        l10n.kostvRequestLimitReached,
      ),
      _ when !askable => (
        KostvGhostTexts.icon(first),
        KostvGhostTexts.note(context, first),
      ),
      _ => null,
    };

    final watchLabel = next == null
        ? null
        : next.parentIndexNumber != null &&
              next.parentIndexNumber != first.season
        ? l10n.kostvGapWatchOther(
            next.parentIndexNumber!,
            next.indexNumber ?? 0,
          )
        : l10n.kostvGapWatch(next.indexNumber ?? 0);

    // The buttons, first to last: asking (while it can be), then the next
    // episode at home, then closing when there's room.
    final buttons = <_GapButton>[
      if (askable || ask == KostvGapAsk.sent)
        _GapButton(
          label: ask == KostvGapAsk.sent
              ? l10n.kostvGapRequested(count)
              : l10n.kostvGapAsk(count),
          icon: ask == KostvGapAsk.sent
              ? Icons.check_rounded
              : Icons.add_circle_outline,
          busy: ask == KostvGapAsk.sending,
          enabled: canSend,
          onPressed: onAsk,
          primary: true,
        ),
      if (watchLabel != null)
        _GapButton(
          label: watchLabel,
          icon: Icons.play_arrow_rounded,
          onPressed: onWatchNext,
          primary: !(askable || ask == KostvGapAsk.sent),
        ),
    ];
    // A TV closes with Back and moves between two buttons, so its close
    // button only shows when there's room for it; touch and mouse always
    // get one.
    final closeTakesFocus = buttons.length < 2;
    final showClose = closeTakesFocus || !PlatformDetection.isTV;

    final cardRadius = AppColorScheme.isPixel ? 0.0 : 18.0;
    final card = Container(
      width: 360,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.circular(cardRadius),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: adaptiveGlass(
        context: context,
        cornerRadius: cardRadius,
        blur: 18,
        fallbackColor: AppColorScheme.surface.withValues(alpha: 0.6),
        tint: AppColorScheme.surface.withValues(alpha: 0.26),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.upNext.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KostvGhostThumb(
                    ghost: first,
                    label: count == 1 ? null : '${first.number}–${last.number}',
                    width: 104,
                    radius: 10,
                    ink: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: AppRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            pill,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      status.$1,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status.$2,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (index, button) in buttons.indexed) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _GapButtonView(
                        button: button,
                        focusNode: index == 0 ? focusNode : secondFocusNode,
                        autofocus: index == 0 && focusNode == null,
                      ),
                    ),
                  ],
                  if (showClose) ...[
                    if (buttons.isNotEmpty) const SizedBox(width: 10),
                    _CloseButton(
                      focusNode: !closeTakesFocus
                          ? null
                          : (buttons.isEmpty ? focusNode : secondFocusNode),
                      tooltip: l10n.close,
                      onPressed: onClose,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (PlatformDetection.useMobileUi) {
      return Positioned(
        top: 0,
        bottom: 0,
        right: 24,
        child: Center(widthFactor: 1, child: card),
      );
    }
    return Positioned(right: 24, bottom: 120, child: card);
  }
}

@immutable
class _GapButton {
  const _GapButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;
  final bool busy;
}

class _GapButtonView extends StatefulWidget {
  const _GapButtonView({
    required this.button,
    this.focusNode,
    this.autofocus = false,
  });

  final _GapButton button;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_GapButtonView> createState() => _GapButtonViewState();
}

class _GapButtonViewState extends State<_GapButtonView> {
  bool _focused = false;

  void _press() {
    if (widget.button.enabled) widget.button.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final button = widget.button;
    final accent = AppColorScheme.accent;
    final lit = _focused || (button.primary && widget.focusNode == null);
    final background = !button.enabled
        ? Colors.white.withValues(alpha: 0.08)
        : lit
        ? accent
        : (button.primary
              ? accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.1));
    final foreground = button.enabled
        ? Colors.white
        : Colors.white.withValues(alpha: 0.6);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          _press();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _press,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.circular(12),
            border: _focused
                ? Border.fromBorderSide(
                    ThemeRegistry.active.borders.focusBorder,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (button.busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(button.icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  button.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _focused
                  ? AppColorScheme.accent.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: AppRadius.circular(12),
              border: Border.fromBorderSide(
                _focused
                    ? ThemeRegistry.active.borders.focusBorder
                    : ThemeRegistry.active.borders.chipBorder,
              ),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
