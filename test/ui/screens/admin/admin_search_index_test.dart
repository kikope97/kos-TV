import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/admin_search_index.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('Jellyfin rows are searchable and the Emby ones are gone', () {
    Set<String?> anchors(ServerType server) => {
      for (final entry in adminSearchEntries(server)) entry.anchor,
    };
    const jellyfinRows = {
      'branding.SplashscreenEnabled',
      'settings.QuickConnectAvailable',
      'settings.SlowResponseThresholdMs',
      'metadata.DummyChapterDuration',
      'live-tv.SaveRecordingNFO',
    };
    // Moonfin's Emby-only rows, removed in Kos TV.
    const embyRows = {
      'settings.IsInMaintenanceMode',
      'settings.EnableAutomaticRestart',
      'settings.BannerText',
      'metadata.UseFileCreationTimeForDateAdded',
      'live-tv.WakeServer',
    };

    final jellyfin = anchors(ServerType.jellyfin);
    expect(jellyfin, containsAll(jellyfinRows));
    expect(jellyfin.intersection(embyRows), isEmpty);
    for (final shared in ['branding.CustomCss', 'settings.ServerName']) {
      expect(jellyfin, contains(shared));
    }
  });
}
