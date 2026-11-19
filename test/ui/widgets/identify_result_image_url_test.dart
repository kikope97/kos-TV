import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/identify_dialog.dart';

void main() {
  test('a full-size TMDB poster is asked for at thumbnail size', () {
    expect(
      identifyResultImageUrl('https://image.tmdb.org/t/p/original/abc.jpg'),
      'https://image.tmdb.org/t/p/w154/abc.jpg',
    );
  });

  test('other result images are left as they are', () {
    const sized = 'https://image.tmdb.org/t/p/w500/abc.jpg';
    const other = 'https://example.com/poster.jpg';
    expect(identifyResultImageUrl(sized), sized);
    expect(identifyResultImageUrl(other), other);
  });
}
