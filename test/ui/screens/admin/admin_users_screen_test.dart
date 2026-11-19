import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/users/admin_users_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// A 12.2 server's UserDto.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/admin/user.json').readAsStringSync())
        as Map<String, dynamic>;

class _FakeUsersApi extends Fake implements AdminUsersApi {
  Map<String, dynamic> user = _fixture();
  final postedPolicies = <Map<String, dynamic>>[];

  /// What the server holds now, when it differs from the listed user.
  Map<String, dynamic>? serverUser;

  /// Answers the next policy post with this status.
  int? refuseWith;

  @override
  Future<ServerUser> getUserById(String userId) async => ServerUser.fromJson(
    jsonDecode(jsonEncode(serverUser ?? user)) as Map<String, dynamic>,
  );

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async =>
      [ServerUser.fromJson(jsonDecode(jsonEncode(user)) as Map<String, dynamic>)];

  @override
  Future<void> updateUserPolicy(String userId, Map<String, dynamic> p) async {
    final status = refuseWith;
    if (status != null) {
      final request = RequestOptions(path: '/Users/$userId/Policy');
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: status),
      );
    }
    postedPolicies.add(p);
  }
}

class _FakeImageApi extends Fake implements ImageApi {
  @override
  String getUserImageUrl(String userId) =>
      'http://jf/Users/$userId/Images/Primary';
}

void main() {
  late _FakeUsersApi users;
  late _MockMediaServerClient client;
  late AppLocalizations l10n;

  setUp(() async {
    users = _FakeUsersApi();
    client = _MockMediaServerClient();
    when(() => client.adminUsersApi).thenReturn(users);
    when(() => client.imageApi).thenReturn(_FakeImageApi());
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminUsersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('disabling a user posts their whole policy', (tester) async {
    users.user['Policy'] = {
      ...users.user['Policy'] as Map<String, dynamic>,
      'AccessSchedules': [
        {'DayOfWeek': 'Monday', 'StartHour': 8, 'EndHour': 20},
      ],
      'AllowedTags': ['kids'],
      'MaxParentalSubRating': 1,
      'SyncPlayAccess': 'JoinGroups',
    };
    final before = Map<String, dynamic>.from(users.user['Policy'] as Map);
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, l10n.disable));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.disable));
    await tester.pumpAndSettle();

    expect(users.postedPolicies.single, {...before, 'IsDisabled': true});
  });

  testWidgets('the card shows last activity', (tester) async {
    users.user['LastActivityDate'] =
        DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String();
    await pump(tester);

    expect(find.text(l10n.adminUserLastActivity(l10n.hoursAgo(3))), findsOneWidget);
  });

  testWidgets('the avatar URL carries the image tag', (tester) async {
    users.user['PrimaryImageTag'] = 'abc';
    await pump(tester);
    // Tests answer every HTTP request with 400, so the load itself fails.
    tester.takeException();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final url = Uri.parse((avatar.backgroundImage! as NetworkImage).url);
    expect(url.queryParameters['tag'], 'abc');
  });

  // Kos TV: the list may be hours old, and the server replaces the whole
  // policy, so what another admin changed meanwhile must survive.
  testWidgets('disabling a user posts the policy the server has now', (
    tester,
  ) async {
    await pump(tester);
    final fresh = Map<String, dynamic>.from(users.user['Policy'] as Map)
      ..['MaxParentalRating'] = 10
      ..['BlockedTags'] = ['terror'];
    users.serverUser = {...users.user, 'Policy': fresh};

    await tester.tap(find.widgetWithText(OutlinedButton, l10n.disable));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.disable));
    await tester.pumpAndSettle();

    expect(users.postedPolicies.single, {...fresh, 'IsDisabled': true});
  });

  testWidgets('the signed-in admin can neither disable nor delete themself', (
    tester,
  ) async {
    when(() => client.userId).thenReturn(users.user['Id'] as String);
    await pump(tester);

    expect(find.widgetWithText(OutlinedButton, l10n.disable), findsNothing);
    expect(find.widgetWithText(OutlinedButton, l10n.delete), findsNothing);
    expect(find.widgetWithText(OutlinedButton, l10n.manage), findsOneWidget);
  });

  testWidgets("the server's refusal to disable an admin is explained", (
    tester,
  ) async {
    users.user['Policy'] = {
      ...users.user['Policy'] as Map<String, dynamic>,
      'IsAdministrator': true,
    };
    users.refuseWith = 403;
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, l10n.disable));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.disable));
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.adminUserPolicyUpdateFailed(l10n.adminCannotDisableAdministrator),
      ),
      findsOneWidget,
    );
  });
}
