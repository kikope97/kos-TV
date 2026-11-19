/// Query parameters that carry a person's token on an image URL.
const _tokenParams = {'apikey', 'api_key'};

/// Kos TV: the image cache key for a URL that signs itself with a token (the
/// server plugin's studio logos and titled thumbnails), which is the URL
/// without it. Each person and each new sign-in would otherwise download the
/// same picture again under a key holding their token. Null when the URL has
/// no token, so it keeps its usual key. The request still sends the token.
String? tokenFreeImageCacheKey(String url) {
  final queryAt = url.indexOf('?');
  if (queryAt < 0) return null;
  final query = url.substring(queryAt + 1);
  final parts = query.split('&');
  bool isToken(String part) {
    final equals = part.indexOf('=');
    final name = equals < 0 ? part : part.substring(0, equals);
    return _tokenParams.contains(name.toLowerCase());
  }

  if (!parts.any(isToken)) return null;
  final kept = parts.where((p) => p.isNotEmpty && !isToken(p)).join('&');
  final path = url.substring(0, queryAt);
  return kept.isEmpty ? path : '$path?$kept';
}
