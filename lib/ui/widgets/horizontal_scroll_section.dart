import 'package:flutter/material.dart';

import '../../util/platform_detection.dart';

class HorizontalScrollSection extends StatefulWidget {
  final String title;
  final Widget Function(BuildContext context, ScrollController controller)
  builder;
  final ScrollController? scrollController;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry headerPadding;
  final double contentSpacing;
  final Widget? trailing;
  final bool showControls;
  final VoidCallback? onScrollPastStart;
  final VoidCallback? onScrollPastEnd;

  const HorizontalScrollSection({
    super.key,
    required this.title,
    required this.builder,
    this.scrollController,
    this.titleStyle,
    this.headerPadding = EdgeInsets.zero,
    this.contentSpacing = 12,
    this.trailing,
    this.showControls = true,
    this.onScrollPastStart,
    this.onScrollPastEnd,
  });

  @override
  State<HorizontalScrollSection> createState() =>
      _HorizontalScrollSectionState();
}

class _HorizontalScrollSectionState extends State<HorizontalScrollSection> {
  late ScrollController _controller;
  late bool _ownsController;
  final _metricsChanged = RowMetricsSignal();

  static const _scrollStep = 480.0;
  static const _scrollDuration = Duration(milliseconds: 380);
  static const _scrollCurve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.scrollController == null;
    _controller = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController == widget.scrollController) {
      return;
    }

    if (_ownsController) {
      _controller.dispose();
    }
    _ownsController = widget.scrollController == null;
    _controller = widget.scrollController ?? ScrollController();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    _metricsChanged.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) {
      if (delta < 0) {
        widget.onScrollPastStart?.call();
      } else {
        widget.onScrollPastEnd?.call();
      }
      return;
    }

    final current = _controller.offset;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );

    if ((target - current).abs() < 0.5) {
      if (delta < 0) {
        widget.onScrollPastStart?.call();
      } else {
        widget.onScrollPastEnd?.call();
      }
      return;
    }

    _controller.animateTo(
      target,
      duration: _scrollDuration,
      curve: _scrollCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasControls =
        widget.showControls && PlatformDetection.useDesktopUi;
    final hasHeader =
        widget.title.isNotEmpty || widget.trailing != null || hasControls;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasHeader)
          Padding(
            padding: widget.headerPadding,
            child: Row(
              children: [
                if (widget.title.isEmpty)
                  const Spacer()
                else
                  Expanded(
                    child: Text(
                      widget.title,
                      style: widget.titleStyle ??
                          Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                if (widget.trailing != null) widget.trailing!,
                // Hidden rather than left out, so a section without them keeps
                // the same header height and its row starts as far under the
                // title as every other section's.
                if (PlatformDetection.useDesktopUi)
                  Visibility(
                    visible: hasControls,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    // Kos TV: only while the row has more than fits, and
                    // the one at the end it's at greyed out.
                    child: RowHeaderArrows(
                      controller: _controller,
                      metricsChanged: _metricsChanged,
                      onBack: () => _scrollBy(-_scrollStep),
                      onForward: () => _scrollBy(_scrollStep),
                      // Rows that do something past their ends keep that
                      // arrow working there.
                      keepBack: widget.onScrollPastStart != null,
                      keepForward: widget.onScrollPastEnd != null,
                    ),
                  ),
              ],
            ),
          ),
        if (hasHeader && widget.contentSpacing > 0)
          SizedBox(height: widget.contentSpacing),
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _metricsChanged.notify();
            return false;
          },
          child: widget.builder(context, _controller),
        ),
      ],
    );
  }
}

/// Kos TV: rings when a row's size or the size of what it holds changes
/// (cards loading, the window resized), which its scroll controller doesn't
/// report. Fed from a [ScrollMetricsNotification] listener around the row.
class RowMetricsSignal extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Kos TV: the ‹ › pair in a row's header on desktop. Neither shows while
/// every card fits and there is nothing to scroll; once the row can scroll,
/// the arrow pointing past the end it's at is greyed out. Hidden rather than
/// left out, so the header keeps its height either way.
class RowHeaderArrows extends StatefulWidget {
  const RowHeaderArrows({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onForward,
    this.metricsChanged,
    this.keepBack = false,
    this.keepForward = false,
  });

  final ScrollController? controller;
  final VoidCallback onBack;
  final VoidCallback onForward;

  /// Rings when the row's sizes change; see [RowMetricsSignal].
  final Listenable? metricsChanged;

  /// Keep that arrow pressable at the row's end, for rows that do something
  /// there (the guide moves its time window).
  final bool keepBack;
  final bool keepForward;

  @override
  State<RowHeaderArrows> createState() => _RowHeaderArrowsState();
}

class _RowHeaderArrowsState extends State<RowHeaderArrows> {
  bool _back = false;
  bool _forward = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_refresh);
    widget.metricsChanged?.addListener(_refresh);
    _refreshAfterLayout();
  }

  @override
  void didUpdateWidget(covariant RowHeaderArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_refresh);
      widget.controller?.addListener(_refresh);
    }
    if (oldWidget.metricsChanged != widget.metricsChanged) {
      oldWidget.metricsChanged?.removeListener(_refresh);
      widget.metricsChanged?.addListener(_refresh);
    }
    // The row was rebuilt too: what it holds may have changed.
    _refreshAfterLayout();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_refresh);
    widget.metricsChanged?.removeListener(_refresh);
    super.dispose();
  }

  void _refreshAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    final position = widget.controller?.positions.singleOrNull;
    final measured = position != null && position.hasContentDimensions;
    final back = measured && position.extentBefore > 0.5;
    final forward = measured && position.extentAfter > 0.5;
    if (back == _back && forward == _forward) return;
    setState(() {
      _back = back;
      _forward = forward;
    });
  }

  Widget _arrow(IconData icon, VoidCallback? onPressed) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    descendantsAreFocusable: false,
    child: IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scrolls = _back || _forward;
    return Visibility(
      visible: scrolls || widget.keepBack || widget.keepForward,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(
            Icons.chevron_left,
            _back || widget.keepBack ? widget.onBack : null,
          ),
          _arrow(
            Icons.chevron_right,
            _forward || widget.keepForward ? widget.onForward : null,
          ),
        ],
      ),
    );
  }
}
