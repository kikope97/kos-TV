import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Kos TV: a step of getting in (start, server, sign-in, then Home). On the
/// web it takes the place of the page in the browser's history instead of
/// adding one, so Back from Home doesn't go back to the sign-in or to the
/// start screen. Elsewhere it is a plain `context.go`.
void kostvAuthGo(BuildContext context, String location) {
  if (kIsWeb) {
    Router.neglect(context, () => context.go(location));
  } else {
    context.go(location);
  }
}
