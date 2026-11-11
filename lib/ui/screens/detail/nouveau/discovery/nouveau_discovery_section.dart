import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/detail_section_layout.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../widgets/navigation_layout.dart';
import '../../../../widgets/focus/locked_focus_row.dart';
import 'nouveau_discovery_card.dart';
import 'nouveau_discovery_rail.dart';

class NouveauDiscoverySection extends StatefulWidget {
  final ItemDetailViewModel viewModel;

  final UserPreferences prefs;

  /// Whether the viewer left "More like this" on. Hidden, the rail never
  /// shows, not even as a skeleton.
  final DetailSectionVisibility visibility;

  final bool Function()? onNavigateUp;

  final bool Function()? onNavigateDown;

  const NouveauDiscoverySection({
    super.key,
    required this.viewModel,
    required this.prefs,
    this.visibility = DetailSectionVisibility.all,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  static bool supportsItem(AggregatedItem item) {
    return item.type == 'Movie' || item.type == 'Series';
  }

  static bool shouldInclude(
    ItemDetailViewModel viewModel,
    DetailSectionVisibility visibility,
  ) {
    final item = viewModel.item;

    if (item == null ||
        !supportsItem(item) ||
        !visibility.shows(DetailSection.moreLikeThis)) {
      return false;
    }

    return !viewModel.similarInitialLoadComplete ||
        viewModel.similar.isNotEmpty;
  }

  @override
  State<NouveauDiscoverySection> createState() =>
      NouveauDiscoverySectionState();
}

class NouveauDiscoverySectionState extends State<NouveauDiscoverySection>
    with SingleTickerProviderStateMixin {
  static int _hubSession = 0;

  static const Duration _skeletonGracePeriod = Duration(milliseconds: 450);

  static const Duration _railFadeDuration = Duration(milliseconds: 220);

  late final String _relatedHubKey;

  late final AnimationController _relatedOpacityController;

  final ScrollController _relatedScrollController = ScrollController();

  final GlobalKey<LockedFocusRowState<AggregatedItem>> _relatedRowKey =
      GlobalKey<LockedFocusRowState<AggregatedItem>>();

  final GlobalKey _relatedRevealKey = GlobalKey();

  Timer? _skeletonTimer;

  bool _skeletonDelayElapsed = false;

  bool _relatedSkeletonShown = false;

  bool _relatedCardsShown = false;

  String? _trackedItemId;

  List<AggregatedItem> _baseRelatedSnapshot = const [];

  bool _baseRelatedCaptured = false;

  ItemDetailViewModel get _vm => widget.viewModel;

  GlobalKey? get topRevealKey => _related.isNotEmpty ? _relatedRevealKey : null;

  GlobalKey? get bottomRevealKey => topRevealKey;

  @override
  void initState() {
    super.initState();

    final session = _hubSession++;

    _relatedHubKey = 'nouveau-discovery-related-$session';

    _relatedOpacityController = AnimationController(
      vsync: this,
      duration: _railFadeDuration,
    );

    _trackedItemId = _vm.item?.id;

    _captureBaseRelatedIfAvailable();

    _initializeContent();

    _vm.addListener(_onViewModelChanged);

    _startSkeletonGracePeriod();
  }

  @override
  void didUpdateWidget(covariant NouveauDiscoverySection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);

      widget.viewModel.addListener(_onViewModelChanged);

      _resetForItem();

      return;
    }

    if (oldWidget.visibility != widget.visibility) {
      _syncRailContent();
    }
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();

    _vm.removeListener(_onViewModelChanged);

    _relatedOpacityController.dispose();

    _relatedScrollController.dispose();

    super.dispose();
  }

  void _initializeContent() {
    if (_related.isNotEmpty) {
      _relatedCardsShown = true;

      _relatedOpacityController.forward(from: 0);
    }
  }

  void _onViewModelChanged() {
    if (!mounted) {
      return;
    }

    final itemId = _vm.item?.id;

    if (itemId != _trackedItemId) {
      _resetForItem();
      return;
    }

    _captureBaseRelatedIfAvailable();

    _syncRailContent();

    setState(() {});
  }

  void _resetForItem() {
    _skeletonTimer?.cancel();

    _trackedItemId = _vm.item?.id;

    _baseRelatedSnapshot = const [];

    _baseRelatedCaptured = false;

    _skeletonDelayElapsed = false;

    _relatedSkeletonShown = false;

    _relatedCardsShown = false;

    _relatedOpacityController
      ..stop()
      ..value = 0;

    _captureBaseRelatedIfAvailable();

    _initializeContent();

    _startSkeletonGracePeriod();

    if (mounted) {
      setState(() {});
    }
  }

  void _startSkeletonGracePeriod() {
    _skeletonTimer?.cancel();

    _skeletonTimer = Timer(_skeletonGracePeriod, () {
      if (!mounted) {
        return;
      }

      _skeletonDelayElapsed = true;

      if (_related.isEmpty &&
          _relatedWaiting &&
          !_relatedCardsShown &&
          !_relatedSkeletonShown) {
        _relatedSkeletonShown = true;

        _relatedOpacityController.forward(from: 0);

        setState(() {});
      }
    });
  }

  void _syncRailContent() {
    final hasRelated = _related.isNotEmpty;

    if (hasRelated && !_relatedCardsShown) {
      final replacingSkeleton = _relatedSkeletonShown;

      _relatedCardsShown = true;

      _relatedSkeletonShown = false;

      if (replacingSkeleton) {
        _relatedOpacityController
          ..stop()
          ..value = 1;
      } else {
        _relatedOpacityController.forward(from: 0);
      }
    }

    final relatedWaiting = _relatedWaiting;

    if (!hasRelated && !relatedWaiting && _relatedSkeletonShown) {
      _relatedSkeletonShown = false;

      _relatedOpacityController
        ..stop()
        ..value = 0;
    }

    if (!_skeletonDelayElapsed) {
      return;
    }

    if (!hasRelated &&
        relatedWaiting &&
        !_relatedCardsShown &&
        !_relatedSkeletonShown) {
      _relatedSkeletonShown = true;

      _relatedOpacityController.forward(from: 0);
    }
  }

  bool get _showsBaseRelated =>
      widget.visibility.shows(DetailSection.moreLikeThis);

  /// Whether the rail is still loading. Hidden, it never holds a skeleton up.
  bool get _relatedWaiting =>
      _showsBaseRelated && !_vm.similarInitialLoadComplete;

  bool get _navbarIsLeft =>
      widget.prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;

  void _handleLeftEdge() {
    NavigationLayout.focusNavbarNotifier.value?.call();
  }

  void _captureBaseRelatedIfAvailable() {
    if (_baseRelatedCaptured || _vm.similar.isEmpty) {
      return;
    }

    _baseRelatedSnapshot = _dedupeBaseRelated(_vm.similar);

    _baseRelatedCaptured = true;
  }

  List<AggregatedItem> _dedupeBaseRelated(List<AggregatedItem> source) {
    final currentItem = _vm.item;

    final currentKeys = currentItem == null
        ? const <String>{}
        : _identityKeys(currentItem);

    final seen = <String>{};

    final result = <AggregatedItem>[];

    for (final item in source) {
      final keys = _identityKeys(item);

      if (_sharesIdentity(keys, currentKeys) || _sharesIdentity(keys, seen)) {
        continue;
      }

      seen.addAll(keys);

      result.add(item);
    }

    return List<AggregatedItem>.unmodifiable(result);
  }

  List<AggregatedItem> get _related {
    if (!_showsBaseRelated) {
      return const [];
    }

    if (_baseRelatedCaptured) {
      return _baseRelatedSnapshot;
    }

    return _dedupeBaseRelated(_vm.similar);
  }

  Set<String> _identityKeys(AggregatedItem item) {
    final keys = <String>{};

    final mediaType = switch (item.type) {
      'Series' => 'tv',
      'Movie' => 'movie',
      final type? => type.toLowerCase(),
      null => 'unknown',
    };

    final tmdbId = item.tmdbId?.trim();

    if (tmdbId != null && tmdbId.isNotEmpty) {
      keys.add('tmdb:$mediaType:$tmdbId');
    }

    final normalizedTitle = item.name.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (normalizedTitle.isNotEmpty) {
      final year = item.productionYear?.toString() ?? '';

      keys.add('title:$mediaType:$normalizedTitle|year:$year');
    }

    if (keys.isEmpty) {
      keys.add('server:${item.serverId}|id:${item.id}');
    }

    return keys;
  }

  bool _sharesIdentity(Set<String> itemKeys, Set<String> knownKeys) {
    for (final key in itemKeys) {
      if (knownKeys.contains(key)) {
        return true;
      }
    }

    return false;
  }

  bool get canFocusTop {
    if (!mounted) {
      return false;
    }

    return _related.isNotEmpty && _relatedRowKey.currentState != null;
  }

  bool focusTop() {
    final row = _relatedRowKey.currentState;

    if (_related.isEmpty || row == null) {
      return false;
    }

    row.requestFocusFromMemory();

    return true;
  }

  bool focusBottom() => focusTop();

  @override
  Widget build(BuildContext context) {
    final related = _related;

    if (related.isEmpty && !_relatedWaiting) {
      return const SizedBox.shrink();
    }

    return KeyedSubtree(
      key: _relatedRevealKey,
      child: NouveauDiscoveryRail(
        // Existing localization key kept because changing generated
        // localization API is outside this UI cleanup.
        title: AppLocalizations.of(context).similar,
        items: related,
        showSkeleton: _relatedSkeletonShown && related.isEmpty,
        opacity: _relatedOpacityController,
        rowKey: _relatedRowKey,
        hubKey: _relatedHubKey,
        controller: _relatedScrollController,
        onNavigateUp: () {
          return widget.onNavigateUp?.call() ?? false;
        },
        onNavigateDown: () {
          return widget.onNavigateDown?.call() ?? false;
        },
        onTap: (item) {
          NouveauDiscoveryCard.openItem(context, item);
        },
        onLeftEdge: _navbarIsLeft ? _handleLeftEdge : null,
        itemBuilder: (context, item, width, isFocused) {
          return NouveauDiscoveryCard(
            item: item,
            imageApi: _vm.imageApi,
            prefs: widget.prefs,
            width: width,
            isFocused: isFocused,
          );
        },
      ),
    );
  }
}
