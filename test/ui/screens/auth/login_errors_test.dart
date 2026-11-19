import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/login_state.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/auth/login_screen.dart';

// Kos TV: a failed sign-in used to show the error's English text ("Invalid
// username or password", "Connection failed (connectionError): ...").

void main() {
  final es = lookupAppLocalizations(const Locale('es'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('loginErrorMessage', () {
    test('a wrong password says so, in each language', () {
      const error = ApiClientError(
        error: 'Invalid username or password',
        errorType: 'badResponse',
        statusCode: 401,
      );
      expect(loginErrorMessage(error, es), es.loginWrongCredentials);
      expect(loginErrorMessage(error, en), en.loginWrongCredentials);
      expect(es.loginWrongCredentials, isNot(en.loginWrongCredentials));
    });

    test('a server error says the server had a problem', () {
      const error = ApiClientError(
        error: 'Server error (500) - authentication failed',
        errorType: 'badResponse',
        statusCode: 500,
      );
      expect(loginErrorMessage(error, es), es.loginServerError);
    });

    test('no answer says the server cannot be reached', () {
      for (final type in ['connectionError', 'unknown']) {
        final error = ApiClientError(
          error: 'Connection failed ($type): $type',
          errorType: type,
        );
        expect(loginErrorMessage(error, es), es.unableToConnectToServer);
      }
    });

    test('anything else is the general sign-in failure', () {
      for (final error in const [
        ApiClientError(error: 'Invalid auth response'),
        ApiClientError(error: 'FormatException', errorType: 'exception'),
        ApiClientError(
          error: 'Connection failed (badResponse): HTTP 404',
          errorType: 'badResponse',
          statusCode: 404,
        ),
      ]) {
        expect(loginErrorMessage(error, es), es.loginFailed);
      }
    });
  });

  group('isQuickConnectCodeGone', () {
    DioException answered(int status) {
      final request = RequestOptions(path: '/QuickConnect/Connect');
      return DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: status),
      );
    }

    test('a code the server forgot (404) is gone', () {
      expect(isQuickConnectCodeGone(answered(404)), isTrue);
    });

    test('a network blip or a server error keeps the code', () {
      expect(
        isQuickConnectCodeGone(
          DioException(
            requestOptions: RequestOptions(path: '/QuickConnect/Connect'),
            type: DioExceptionType.connectionError,
          ),
        ),
        isFalse,
      );
      expect(isQuickConnectCodeGone(answered(500)), isFalse);
      expect(isQuickConnectCodeGone(StateError('x')), isFalse);
    });
  });
}
