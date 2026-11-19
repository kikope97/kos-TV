import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/viewmodels/item_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/focus/focusable_wrapper.dart';
import 'kostv/kostv_detail_buttons.dart';

/// Kos TV: whether a person's page has to say their titles couldn't be read,
/// in place of the filmography it would show.
bool showsFilmographyFailure(ItemDetailViewModel viewModel) =>
    viewModel.item?.type == 'Person' &&
    viewModel.filmographyFailed &&
    viewModel.filmography.isEmpty;

/// Kos TV: «Error al cargar», with a «Reintentar» the remote can reach, where
/// a person's filmography goes when it couldn't be read.
///
/// The button keeps [focusNode] while it tries again, and has it again if it
/// fails once more. When the titles come in, [onRecovered] runs after the
/// frame that draws them, if the button had the focus, for the page to put
/// it on them.
class PersonFilmographyFailed extends StatefulWidget {
  const PersonFilmographyFailed({
    super.key,
    required this.viewModel,
    this.focusNode,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRecovered,
    this.padding = EdgeInsets.zero,
    this.large = false,
  });

  final ItemDetailViewModel viewModel;
  final FocusNode? focusNode;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRecovered;
  final EdgeInsetsGeometry padding;

  /// The ten-foot size, for the TV and wide screens.
  final bool large;

  @override
  State<PersonFilmographyFailed> createState() =>
      _PersonFilmographyFailedState();
}

class _PersonFilmographyFailedState extends State<PersonFilmographyFailed> {
  static const _fast = Duration(milliseconds: 160);

  final FocusNode _ownNode = FocusNode(debugLabel: 'filmographyRetry');
  bool _retrying = false;

  FocusNode get _node => widget.focusNode ?? _ownNode;

  @override
  void dispose() {
    _ownNode.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    final hadFocus = _node.hasFocus;
    final onRecovered = widget.onRecovered;
    final viewModel = widget.viewModel;
    setState(() => _retrying = true);
    await viewModel.retryFilmography();
    if (mounted) setState(() => _retrying = false);
    if (!hadFocus || viewModel.filmographyFailed || onRecovered == null) {
      return;
    }
    // This button is gone once the titles are drawn, and the focus with it.
    WidgetsBinding.instance.addPostFrameCallback((_) => onRecovered());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = !_retrying;

    Widget face(bool lit) {
      final ink = kostvGlassInk(lit: lit, enabled: enabled);
      return AnimatedScale(
        scale: lit ? 1.06 : 1,
        duration: _fast,
        child: AnimatedContainer(
          duration: _fast,
          padding: EdgeInsets.symmetric(
            horizontal: widget.large ? 18 : 16,
            vertical: widget.large ? 10 : 9,
          ),
          decoration: kostvGlass(lit: lit, enabled: enabled, radius: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: ink, size: 19),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  l10n.retry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.failedToLoad,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: widget.large ? 16 : 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            FocusableWrapper(
              focusNode: _node,
              onSelect: enabled ? () => unawaited(_retry()) : null,
              onNavigateUp: widget.onUp,
              onNavigateDown: widget.onDown,
              onNavigateLeft: widget.onLeft,
              borderRadius: 10,
              disableScale: true,
              suppressFocusGlow: true,
              useBackgroundFocus: false,
              semanticLabel: l10n.retry,
              child: Builder(
                builder: (context) => face(Focus.of(context).hasFocus),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
