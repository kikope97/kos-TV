import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_core/server_core.dart';

import '../../../../di/providers.dart';
import 'admin_media_analytics_provider.dart';
import 'admin_status_providers.dart';
import 'admin_user_providers.dart';

class AdminWebSocketHandler extends ConsumerStatefulWidget {
  final Widget child;

  const AdminWebSocketHandler({super.key, required this.child});

  @override
  ConsumerState<AdminWebSocketHandler> createState() =>
      _AdminWebSocketHandlerState();
}

class _AdminWebSocketHandlerState extends ConsumerState<AdminWebSocketHandler>
    with WidgetsBindingObserver {
  StreamSubscription<ServerWebSocketMessage>? _subscription;

  /// Kept for [dispose], where `ref` can no longer be used.
  late final ProviderContainer _container;

  /// When the app went to the background, to reload what a long absence may
  /// have left stale.
  DateTime? _pausedAt;

  /// Away this long, the cached lists are read again on return.
  static const _staleAfter = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    // Kos TV: the lists live in the app-wide scope, so each visit to the
    // panel reads them again instead of showing what an earlier one fetched.
    _invalidateCachedLists();
    WidgetsBinding.instance.addObserver(this);
    _subscription = ref.read(socketHandlerProvider).events.listen(_onEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    // Kos TV: the analytics item lists can be huge, so they go with the panel.
    releaseAdminLibraryItems(_container);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        _pausedAt = null;
        if (pausedAt != null &&
            DateTime.now().difference(pausedAt) >= _staleAfter) {
          _invalidateCachedLists();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _invalidateCachedLists() {
    _container
      ..invalidate(adminUsersListProvider)
      ..invalidate(adminLibrariesProvider)
      ..invalidate(adminInstalledPluginsProvider)
      ..invalidate(adminAvailablePackagesProvider)
      ..invalidate(adminRepositoriesProvider)
      ..invalidate(adminDevicesProvider)
      ..invalidate(adminMediaSummaryProvider);
  }

  void _onEvent(ServerWebSocketMessage event) {
    // Task and session lists follow their own feeds (adminTasksProvider,
    // adminSessionsProvider), so only the one-off events are handled here.
    switch (event) {
      case LibraryChangedMessage():
        ref.invalidate(adminLibrariesProvider);
      // Anything can change across a restart, so every cached list is dropped.
      case ServerRestartingMessage():
      case ServerShuttingDownMessage():
        ref
          ..invalidate(adminInstalledPluginsProvider)
          ..invalidate(adminAvailablePackagesProvider)
          ..invalidate(adminRepositoriesProvider)
          ..invalidate(adminUsersListProvider)
          ..invalidate(adminLibrariesProvider)
          ..invalidate(adminDevicesProvider)
          ..invalidate(adminNotificationSummaryProvider);
      case ServerEventMessage(:final type):
        switch (type) {
          case 'PackageInstallationCompleted':
          case 'PackageInstallationFailed':
          case 'PackageInstallationCancelled':
          case 'PackageUninstalled':
          case 'RestartRequired':
            ref.invalidate(adminInstalledPluginsProvider);
            ref.invalidate(adminAvailablePackagesProvider);
            ref.invalidate(adminRepositoriesProvider);
            ref.invalidate(adminNotificationSummaryProvider);
          case 'UserDeleted':
          case 'UserUpdated':
            ref.invalidate(adminUsersListProvider);
          default:
            break;
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}