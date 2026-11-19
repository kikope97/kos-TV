import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/di/providers.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_websocket_handler.dart';
import 'package:server_core/server_core.dart';

/// Kos TV: the admin lists live in the app-wide scope, so each visit to the
/// panel must read them again rather than show an old copy.
void main() {
  testWidgets('opening the panel again reads the lists again', (tester) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        socketHandlerProvider.overrideWithValue(SocketHandler()),
        adminUsersListProvider.overrideWith((ref) async {
          reads++;
          return [ServerUser(id: 'u$reads', name: 'User $reads')];
        }),
      ],
    );
    addTearDown(container.dispose);

    Widget panel() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AdminWebSocketHandler(
          child: Consumer(
            builder: (context, ref, _) {
              final users = ref.watch(adminUsersListProvider).valueOrNull;
              return Text(users?.single.name ?? 'loading');
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(find.text('User 1'), findsOneWidget);

    // Leaving the panel keeps the cached list, and coming back reads it anew.
    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('User 2'), findsOneWidget);
  });
}
