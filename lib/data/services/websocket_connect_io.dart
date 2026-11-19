import 'dart:io' as io;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a websocket to [uri] straight on dart:io, which keeps the HTTP status
/// of a refused handshake (the generic connect drops it).
WebSocketChannel connectWebSocket(Uri uri) => IOWebSocketChannel.connect(uri);

/// The HTTP status a refused handshake was answered with, or null when it
/// failed some other way (no answer, a dropped connection).
int? handshakeStatusOf(Object error) {
  Object? current = error;
  for (var depth = 0; current != null && depth < 4; depth++) {
    if (current is io.WebSocketException) return current.httpStatusCode;
    current = current is WebSocketChannelException ? current.inner : null;
  }
  return null;
}
