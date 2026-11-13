import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_music_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: what the Music page keeps for opening at once.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an answer kept is there next time, also after the app restarts', () {
    fakeAsync((async) {
      final memory = StremfinMusicMemory();
      memory.write('a /music/charts/top-songs?', {'items': []});
      async.elapse(const Duration(seconds: 3));
      Object? read;
      memory.read('a /music/charts/top-songs?').then((v) => read = v);
      async.flushMicrotasks();
      expect(read, {'items': []});
      // Another one, as after a restart: it reads what was written down.
      Object? again;
      StremfinMusicMemory()
          .read('a /music/charts/top-songs?')
          .then((v) => again = v);
      async.flushMicrotasks();
      expect(again, {'items': []});
      Object? missing = 'x';
      memory.read('b /music/charts/top-songs?').then((v) => missing = v);
      async.flushMicrotasks();
      expect(missing, isNull);
    });
  });

  test('each person keeps their own, and the token is never written', () {
    final one = StremfinMusicMemory.scopeOf('token-of-ana');
    expect(one, StremfinMusicMemory.scopeOf('token-of-ana'));
    expect(one, isNot(StremfinMusicMemory.scopeOf('token-of-luis')));
    expect(one, isNot(contains('ana')));
  });

  test('a request for a record says so, with its Deezer id and artist', () {
    final request = StremfinRequest.fromJson({
      'id': 9,
      'type': 'music',
      'deezer_id': '302127',
      'artist': 'Daft Punk',
      'title': 'Discovery',
      'status': 'completed',
    })!;
    expect(request.isMusic, isTrue);
    expect(request.deezerId, '302127');
    expect(request.artist, 'Daft Punk');
    expect(request.type, isNull);
    final film = StremfinRequest.fromJson({
      'id': 10,
      'type': 'movie',
      'tmdb_id': 1,
      'status': 'pending',
    })!;
    expect(film.isMusic, isFalse);
  });
}
