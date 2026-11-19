import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/cast/cast_provider.dart';
import 'package:moonfin/data/services/cast/cast_service.dart';
import 'package:moonfin/data/services/cast/cast_target.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/remote_play_to_session_dialog.dart';

class _Devices implements CastProvider {
  _Devices(this.targets);

  final List<CastTarget> targets;

  @override
  Set<CastTargetKind> get supportedKinds => {CastTargetKind.jellyfinSession};

  @override
  Future<List<CastTarget>> discoverTargets(AggregatedItem item) async =>
      targets;

  @override
  Future<void> playToTarget(
    CastTarget target, {
    required AggregatedItem item,
    List<AggregatedItem>? queueItems,
    int? startPositionTicks,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}
}

final _item = AggregatedItem(
  id: 'movie',
  serverId: 'home',
  rawData: const {'Id': 'movie', 'Type': 'Movie'},
);

Future<AppLocalizations> _open(
  WidgetTester tester,
  List<CastTarget> targets,
) async {
  GetIt.instance.registerSingleton<CastService>(
    CastService([_Devices(targets)]),
  );
  addTearDown(GetIt.instance.reset);
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('es')],
      locale: const Locale('es'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return TextButton(
              onPressed: () =>
                  showRemotePlayToSessionDialog(context, item: _item),
              child: const Text('Cast'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Cast'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return l10n;
}

void main() {
  // Kos TV: the search never closes (late devices still join), so the
  // "searching" state used to stay forever with nothing around.
  testWidgets('with no devices around, the list says so after a while', (
    tester,
  ) async {
    final l10n = await _open(tester, const []);
    expect(find.text(l10n.noRemoteDevices), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    expect(find.text(l10n.noRemoteDevices), findsOneWidget);
  });

  testWidgets('an unnamed device and title are worded in the app language', (
    tester,
  ) async {
    final l10n = await _open(tester, const [
      CastTarget(
        id: 'tv',
        kind: CastTargetKind.jellyfinSession,
        title: '',
        nowPlaying: true,
      ),
    ]);
    expect(find.text(l10n.kostvCastUnknownDevice), findsOneWidget);
    expect(find.text(l10n.nowPlaying), findsOneWidget);
    expect(find.text('Unknown device'), findsNothing);
  });
}
