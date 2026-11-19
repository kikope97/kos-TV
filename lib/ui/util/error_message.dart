import 'dart:async';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/app_localizations.dart';

const _maxDetailLength = 200;

// Kos TV: a ProblemDetails `title` is only the status in English ("Not
// Found", "Forbidden"), so it never reaches the screen.
const _detailKeys = ['message', 'Message', 'error', 'Error', 'detail'];

/// What Jellyfin answers to any unhandled exception outside development
/// mode. It says nothing the status doesn't.
const _genericServerTexts = {'error processing request.'};

const _connectionMarkers = [
  'socketexception',
  'handshakeexception',
  'failed host lookup',
  'connection refused',
  'connection reset',
  'network is unreachable',
  'no route to host',
];

/// Turns a caught error into text for the screen, preferring the server's
/// reason and then the HTTP status over the raw exception.
String describeError(Object error, AppLocalizations l10n) {
  if (error is DioException) return _describeDioError(error, l10n);
  if (error is TimeoutException) return l10n.unableToConnectToServer;
  final text = error.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}

String _describeDioError(DioException error, AppLocalizations l10n) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return l10n.unableToConnectToServer;
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      break;
  }

  final status = error.response?.statusCode;
  final detail = _serverDetail(error.response?.data);

  // Kos TV: the everyday failures read in the app's language and say what
  // happened. The server's own text (usually English) goes to the log.
  final byStatus = switch (status) {
    401 => l10n.kostvErrorSessionExpired,
    403 => l10n.kostvErrorNoPermission,
    404 => l10n.kostvErrorNotOnServer,
    final int code when code >= 500 && code <= 599 =>
      l10n.kostvErrorServerFailed,
    _ => null,
  };
  if (byStatus != null) {
    if (detail != null) {
      ServerLog.network(
        'HTTP $status from ${error.requestOptions.path}: $detail',
        level: ServerLogLevel.warning,
      );
    }
    return byStatus;
  }

  if (detail != null) return detail;

  if (status != null && (status < 200 || status > 299)) {
    return l10n.adminServerReturnedHttp(status);
  }

  final cause = error.error?.toString().toLowerCase() ?? '';
  if (_connectionMarkers.any(cause.contains)) {
    return l10n.unableToConnectToServer;
  }
  return l10n.adminUnknownError;
}

String? _serverDetail(Object? data) {
  String? text;
  if (data is Map) {
    for (final key in _detailKeys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        text = value;
        break;
      }
    }
    // plex.tv sends its reasons as a list.
    if (data['errors'] case [{'message': final String message}, ...]
        when text == null) {
      text = message;
    }
  } else if (data is String && !data.contains('<')) {
    text = data;
  }

  text = text?.trim();
  if (text == null || text.isEmpty) return null;
  if (_genericServerTexts.contains(text.toLowerCase())) return null;
  if (text.length > _maxDetailLength) {
    return '${text.substring(0, _maxDetailLength)}...';
  }
  return text;
}
