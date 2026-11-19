import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a websocket to [uri]. The browser does the handshake.
WebSocketChannel connectWebSocket(Uri uri) => WebSocketChannel.connect(uri);

/// The HTTP status a refused handshake was answered with. A browser never
/// says, so there is none on the web.
int? handshakeStatusOf(Object error) => null;
