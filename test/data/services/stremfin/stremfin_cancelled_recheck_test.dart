import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/discover/kostv_request_status.dart';

/// Kos TV: a request cancelled after it was accepted (Stremfin 1.88) and a
/// download under review that Stremfin keeps trying on its own (1.90).
void main() {
  final l10n = lookupAppLocalizations(const Locale('es'));

  Map<String, Object?> request(Map<String, Object?> extra) => {
    'id': 7,
    'type': 'movie',
    'tmdb_id': 1,
    'title': 'Dune',
    ...extra,
  };

  test('a request cancelled after it was accepted says «Cancelada»', () {
    final cancelled = StremfinRequest.fromJson(
      request({'status': 'rejected', 'cancelled': true, 'reason': null}),
    )!;
    expect(cancelled.cancelled, isTrue);
    expect(kostvRequestStatus(l10n, cancelled).label, 'Cancelada');

    final turnedDown = StremfinRequest.fromJson(
      request({'status': 'rejected', 'reason': 'quality'}),
    )!;
    // An older Stremfin doesn't send it: not cancelled.
    expect(turnedDown.cancelled, isFalse);
    expect(
      kostvRequestStatus(l10n, turnedDown).label,
      l10n.kostvRequestRejectedQuality,
    );
  });

  test('under review and tried again on its own, a film says so', () {
    final retrying = StremfinRequest.fromJson(
      request({
        'status': 'approved',
        'progress': {
          'state': 'attention',
          'phase': 'attention',
          'recheck': {
            'until': '2026-11-15T10:00:00Z',
            'next_at': '2026-11-13T14:00:00Z',
            'every_hours': 2,
            'text': 'Se sigue intentando solo cada 2 h · quedan 2 días',
          },
        },
      }),
    )!;
    expect(
      retrying.progress!.recheck!.text,
      'Se sigue intentando solo cada 2 h · quedan 2 días',
    );
    expect(kostvRequestStatus(l10n, retrying).label, l10n.kostvRequestRetrying);

    final review = StremfinRequest.fromJson(
      request({
        'status': 'approved',
        'progress': {'state': 'attention', 'recheck': null},
      }),
    )!;
    expect(review.progress!.recheck, isNull);
    expect(
      kostvRequestStatus(l10n, review).label,
      l10n.kostvRequestUnderReview,
    );
  });

  test('a series tried again on its own says so through its episodes', () {
    final series = StremfinRequest.fromJson(
      request({
        'type': 'series',
        'status': 'approved',
        'progress': {
          'state': 'attention',
          'recheck': null,
          'episodes': [
            {'season': 1, 'episode': 1, 'phase': 'completed'},
            {
              'season': 1,
              'episode': 2,
              'phase': 'attention',
              'recheck': {'text': 'Se sigue intentando solo cada 2 h'},
            },
          ],
        },
      }),
    )!;
    expect(series.progress!.recheck!.text, 'Se sigue intentando solo cada 2 h');
    expect(kostvRequestStatus(l10n, series).label, l10n.kostvRequestRetrying);
  });
}
