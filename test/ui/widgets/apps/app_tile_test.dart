import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/installed_apps_service.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:moonfin/ui/widgets/apps/app_tile.dart';

/// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Kos TV: the cards of the Apps row and the All apps screen, and where the
/// row goes on Home.
void main() {
  Future<void> pump(WidgetTester tester, Widget tile) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: tile))),
  );

  testWidgets('an app with a TV banner shows the banner alone', (tester) async {
    await pump(
      tester,
      AppTile(
        width: 213,
        height: 120,
        focused: false,
        focusColor: Colors.cyan,
        app: InstalledApp(
          packageName: 'com.netflix.ninja',
          label: 'Netflix',
          art: _png,
          isBanner: true,
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
  });

  testWidgets('an app without a banner shows its icon over its name', (
    tester,
  ) async {
    await pump(
      tester,
      AppTile(
        width: 213,
        height: 120,
        focused: true,
        focusColor: Colors.cyan,
        app: InstalledApp(packageName: 'com.example.files', label: 'Files', art: _png),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('an action card shows its icon and label', (tester) async {
    await pump(
      tester,
      const AppTile(
        width: 213,
        height: 120,
        focused: false,
        focusColor: Colors.cyan,
        icon: Icons.apps_rounded,
        label: 'All apps',
      ),
    );

    expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    expect(find.text('All apps'), findsOneWidget);
  });

  group('HomeViewModel.withAppsRow', () {
    HomeRow row(String id, HomeRowType type) =>
        HomeRow(id: id, title: id, rowType: type, items: const <AggregatedItem>[]);
    final apps = row('kostv_apps', HomeRowType.apps);

    test('goes right under the media bar', () {
      final rows = HomeViewModel.withAppsRow([
        row('bar', HomeRowType.mediaBar),
        row('resume', HomeRowType.resume),
      ], apps);
      expect(rows.map((r) => r.id), ['bar', 'kostv_apps', 'resume']);
    });

    test('goes first without a media bar', () {
      final rows = HomeViewModel.withAppsRow([
        row('resume', HomeRowType.resume),
      ], apps);
      expect(rows.map((r) => r.id), ['kostv_apps', 'resume']);
    });
  });
}
