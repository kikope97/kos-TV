// Kos TV: the browser's media session (title, cover and buttons on the lock
// screen and the computer's media keys), only on the web.
export 'kostv_now_playing_web_session_stub.dart'
    if (dart.library.js_interop) 'kostv_now_playing_web_session_web.dart';
