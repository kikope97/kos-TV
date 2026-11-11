import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/spotlight/spotlight_images.dart';

PersonBackdropCandidate _candidate(String key) => PersonBackdropCandidate(
  key: key,
  fullUrl: 'full/$key',
  cardUrl: 'card/$key',
);

void main() {
  final local = [_candidate('l1'), _candidate('l2')];

  Map<String, String?> pick({String? mainBackdropKey}) =>
      personCardBackdropsFor(
        local: local,
        mainBackdropKey: mainBackdropKey,
        random: math.Random(7),
      );

  test('the filmography card takes from the local pool', () {
    final picked = pick();
    expect(picked.keys, ['filmography']);
    expect(picked['filmography'], anyOf('card/l1', 'card/l2'));
  });

  test('the hero keeps the backdrop it took', () {
    expect(pick(mainBackdropKey: 'l1')['filmography'], 'card/l2');
  });

  test('one backdrop between them is repeated rather than left out', () {
    final picked = personCardBackdropsFor(
      local: [_candidate('solo')],
      mainBackdropKey: 'solo',
      random: math.Random(7),
    );
    expect(picked.values, everyElement('card/solo'));
  });

  test('a person with nothing to draw gets nothing', () {
    final picked = personCardBackdropsFor(local: const []);
    expect(picked.values, everyElement(isNull));
  });
}
