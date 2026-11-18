import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/image_source.dart';

void main() {
  const base = 'https://jf.example.com/Items/abc/Images';

  test('asks the server for a step at or a quarter above the decode', () {
    expect(
      sizedJellyfinArtworkUrl(
        '$base/Backdrop/0?maxWidth=1920&quality=90&tag=t1',
        width: 300,
      ),
      '$base/Backdrop/0?maxWidth=400&quality=90&tag=t1',
    );
    expect(
      sizedJellyfinArtworkUrl('$base/Primary?quality=90', height: 200),
      '$base/Primary?quality=90&maxHeight=320',
    );
  });

  test('never asks for more than the URL did, nor nearly the same', () {
    const small = '$base/Primary?maxWidth=300&quality=90';
    expect(sizedJellyfinArtworkUrl(small, width: 600), small);
    const close = '$base/Primary?maxWidth=420&quality=90';
    expect(sizedJellyfinArtworkUrl(close, width: 300), close);
  });

  test('leaves other servers, files and unbounded decodes alone', () {
    const tmdb = 'https://image.tmdb.org/t/p/w1280/x.jpg';
    expect(sizedJellyfinArtworkUrl(tmdb, width: 200), tmdb);
    const file = '/data/images/Items/abc/Images/Primary';
    expect(sizedJellyfinArtworkUrl(file, width: 200), file);
    const url = '$base/Primary?maxWidth=1920';
    expect(sizedJellyfinArtworkUrl(url), url);
  });

  test('is a no-op off the web', () {
    const url = '$base/Backdrop/0?maxWidth=1920';
    expect(webSizedArtworkUrl(url, width: 200), url);
  });
}
