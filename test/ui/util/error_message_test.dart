import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations_en.dart';
import 'package:moonfin/ui/util/error_message.dart';

final _l10n = AppLocalizationsEn();
final _request = RequestOptions(path: '/Items');

// Spelled out so the test fails if the wording changes, which comparing
// against the l10n getters wouldn't catch.
const _unableToConnect = 'Unable to connect to server';
const _unknownError = 'Unknown error';

DioException _badResponse(int status, [Object? data]) => DioException(
  requestOptions: _request,
  type: DioExceptionType.badResponse,
  response: Response(requestOptions: _request, statusCode: status, data: data),
);

void main() {
  group('describeError', () {
    test('reports timeouts and connection failures as unable to connect', () {
      for (final type in const [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
      ]) {
        final error = DioException(requestOptions: _request, type: type);
        expect(describeError(error, _l10n), _unableToConnect, reason: '$type');
      }
      expect(describeError(TimeoutException('slow'), _l10n), _unableToConnect);
    });

    test('recognizes a socket failure wrapped as an unknown error', () {
      final error = DioException(
        requestOptions: _request,
        error: 'SocketException: No route to host (OS Error: errno = 113)',
      );
      expect(describeError(error, _l10n), _unableToConnect);
    });

    test("reads plex.tv's list of errors", () {
      final refused = _badResponse(400, {
        'errors': [
          {
            'code': 1001,
            'message': 'User could not be authenticated',
            'status': 400,
          },
        ],
      });
      expect(describeError(refused, _l10n), 'User could not be authenticated');
    });

    test('prefers the reason the server sent', () {
      final missingName = _badResponse(400, {'message': 'Name is required'});
      expect(describeError(missingName, _l10n), 'Name is required');
      expect(
        describeError(_badResponse(409, 'Library is locked'), _l10n),
        'Library is locked',
      );
    });

    // Kos TV: these used to show the server's English text ("Not Found",
    // "Error processing request.") or a bare status.
    test('says what happened for the everyday statuses', () {
      expect(
        describeError(_badResponse(401, {'error': 'Not authenticated'}), _l10n),
        'Your session has expired. Sign in again.',
      );
      expect(
        describeError(_badResponse(403, {'code': 7}), _l10n),
        "You don't have permission to do this.",
      );
      expect(
        describeError(
          _badResponse(404, {'title': 'Not Found', 'status': 404}),
          _l10n,
        ),
        "It's no longer on the server.",
      );
      for (final status in const [500, 502, 503]) {
        expect(
          describeError(
            _badResponse(status, 'Error processing request.'),
            _l10n,
          ),
          'The server ran into a problem. Try again.',
          reason: '$status',
        );
      }
    });

    test("never shows a ProblemDetails title or Jellyfin's generic text", () {
      expect(
        describeError(_badResponse(409, {'title': 'Conflict'}), _l10n),
        'Server returned HTTP 409',
      );
      expect(
        describeError(_badResponse(400, 'Error processing request.'), _l10n),
        'Server returned HTTP 400',
      );
      expect(
        describeError(
          _badResponse(400, {'title': 'Bad Request', 'detail': 'Bad id'}),
          _l10n,
        ),
        'Bad id',
      );
    });

    test('falls back to the status when the body has no reason', () {
      expect(
        describeError(_badResponse(418, '<html>Teapot</html>'), _l10n),
        'Server returned HTTP 418',
      );
    });

    test('shortens a long server reason', () {
      final result = describeError(_badResponse(400, 'x' * 500), _l10n);
      expect(result, '${'x' * 200}...');
    });

    test('never shows a DioException with nothing to go on', () {
      final error = DioException(requestOptions: _request);
      expect(describeError(error, _l10n), _unknownError);
    });

    test('drops the Exception prefix from other errors', () {
      expect(
        describeError(Exception('No results returned.'), _l10n),
        'No results returned.',
      );
      expect(describeError(StateError('bad'), _l10n), 'Bad state: bad');
    });
  });
}
