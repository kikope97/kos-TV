import 'dart:async';

import 'package:server_core/server_core.dart';

import '../data/services/socket_handler.dart';
import 'syncplay_manager.dart';

class SyncPlayRuntimeCoordinator {
  final SyncPlayManager _manager;
  final SocketHandler _socketHandler;

  StreamSubscription<ServerWebSocketMessage>? _wsSub;
  StreamSubscription<void>? _connectionSub;

  SyncPlayRuntimeCoordinator(this._manager, this._socketHandler);

  // Kos TV: it also followed a provider of the active server, which nothing
  // ever set: the manager finds the signed-in client itself.
  void start() {
    _wsSub = _socketHandler.events.listen(_route);
    // Kos TV: a command sent while the socket was down never arrives, so a
    // reconnect asks the group where it is.
    _connectionSub = _socketHandler.connections.listen(
      (_) => _manager.handleRealtimeConnected(),
    );
  }

  void stop() {
    _wsSub?.cancel();
    _wsSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
  }

  void appDidEnterBackground() => _manager.appDidEnterBackground();
  void appDidBecomeActive() => _manager.appDidBecomeActive();

  void _route(ServerWebSocketMessage message) {
    switch (message) {
      case SyncPlayCommandMessage(:final command):
        _manager.handlePlaybackCommand(command);
      case SyncPlayGroupUpdateMessage(:final update):
        _manager.handleGroupUpdate(update);
      case ServerRestartingMessage():
        _manager.handleRealtimeSessionInterrupted(
          SyncPlayError.serverRestarting,
        );
      case ServerShuttingDownMessage():
        _manager.handleRealtimeSessionInterrupted(
          SyncPlayError.serverShuttingDown,
        );
      default:
        break;
    }
  }
}
