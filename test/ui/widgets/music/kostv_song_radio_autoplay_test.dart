import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/stremfin/kostv_song_radio.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _server = 'https://casa.example';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  @override
  bool get isOfflinePlayback => false;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => null;
}

class _Factory extends Fake implements MediaServerClientFactory {
  _Factory(this.client);

  final MediaServerClient client;

  @override
  MediaServerClient? getClientIfExists(String serverId) => client;
}

/// The server plugin, without stations (nor anything else).
class _NoPlugin implements HttpClientAdapter {
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.uri.path);
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

AggregatedItem _stream(String id, {String artist = 'Lola'}) => kostvStreamItem(
  deezerId: id,
  title: 'Canción $id',
  serverId: _server,
  artist: artist,
);

/// Kos TV: the endless play (∞) with the requests service's song radio
/// (`docs/musica-radio.md`, «Orden de las fuentes»).
void main() {
  final music = KostvNowPlaying.instance;
  late _Manager manager;
  late _NoPlugin plugin;
  late List<String> fetched;

  setUp(() {
    manager = _Manager();
    final client =
        JellyfinMediaServerClient(
            baseUrl: _server,
            deviceInfo: const DeviceInfo(
              id: 'device',
              name: 'Device',
              appName: 'kOS TV',
              appVersion: '1.0.0',
            ),
          )
          ..accessToken = 'token'
          ..userId = 'ana';
    GetIt.instance
      ..registerSingleton<PlaybackManager>(manager)
      ..registerSingleton<MediaServerClient>(client)
      ..registerSingleton<MediaServerClientFactory>(_Factory(client));
    plugin = _NoPlugin();
    KostvMusicPlugin.instance = KostvMusicPlugin(
      dio: Dio()..httpClientAdapter = plugin,
    );
    fetched = [];
    // Each song's radio: 30 of its own, by five artists in turn.
    KostvSongRadio.instance = KostvSongRadio(
      fetch: (id, {only, limit}) async {
        fetched.add(id);
        return StremfinSongRadio(
          songs: [
            for (var i = 0; i < 30; i++)
              StremfinSong(
                title: 'Canción $id-$i',
                deezerId: '$id-$i',
                artist: 'a${i % 5}',
              ),
          ],
        );
      },
      match: (songs) async => const StremfinSongMatch(songs: [null]),
      version: () => '1.101.0',
      available: () => true,
      who: () => 'ana',
    );
  });

  tearDown(() async {
    music.debugReset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvSongRadio.instance = KostvSongRadio();
    await GetIt.instance.reset();
  });

  List<String> ids() => [
    for (final s in manager.queueService.items) (s as AggregatedItem).id,
  ];

  test('one radio call for each time it adds more; when the chosen song\'s '
      'has nothing left, the radio of the last song that played', () async {
    final chosen = _stream('100');
    music.noteQueueSource(KostvMusicSource.album, [chosen]);
    manager.queueService.setQueue([chosen]);
    await music.debugAutoplay();
    expect(fetched, ['100']);
    expect(ids(), hasLength(26));
    // Near the end again: the chosen song's radio, kept (no call), gives
    // what wasn't added yet.
    manager.queueService.jumpTo(24);
    await music.debugAutoplay();
    expect(fetched, ['100']);
    expect(ids(), hasLength(31));
    // Nothing left of it: the radio of the song sounding, once.
    manager.queueService.jumpTo(30);
    await music.debugAutoplay();
    expect(fetched, ['100', '100-29']);
    expect(ids(), hasLength(56));
    expect(ids().toSet(), hasLength(56));
    expect(
      ids().skip(31).every((id) => id.startsWith('stremfin:100-29-')),
      isTrue,
    );
    // The song's radio was enough: the plugin wasn't asked for a station.
    expect(plugin.asked.where((p) => p.endsWith('/Music/Station')), isEmpty);
  });

  test('the chosen song\'s radio had to be asked and gave nothing new: no '
      'second call (the plugin\'s station then)', () async {
    final chosen = _stream('100');
    final queue = [
      chosen,
      for (var i = 0; i < 30; i++) _stream('100-$i', artist: 'a${i % 5}'),
    ];
    // A station put on: all of it came by itself but the song it began with.
    music.noteQueueSource(KostvMusicSource.radio, queue);
    manager.queueService.setQueue(queue);
    manager.queueService.jumpTo(30);
    await music.debugAutoplay();
    expect(fetched, ['100']);
    expect(
      plugin.asked.where((p) => p.endsWith('/Music/Station')),
      hasLength(1),
    );
  });
}
