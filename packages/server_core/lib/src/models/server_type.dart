enum ServerType {
  jellyfin,
  silo;

  /// The query parameter that carries the access token on media URLs.
  ///
  /// Jellyfin 12 drops the lowercase api_key param. Silo accepts the bearer
  /// token as `token` on media requests that can't carry headers (its stream
  /// and subtitle URLs). Most Silo URLs (artwork, playback plan URLs) are
  /// already signed and must not get a token appended at all, so callers that
  /// build Silo URLs decide that per URL.
  String get tokenQueryParam => switch (this) {
    ServerType.jellyfin => 'ApiKey',
    ServerType.silo => 'token',
  };

  /// Whether a user's avatar is at Jellyfin's `/Users/{id}/Images/Primary`
  /// on this server. Silo's avatars come with the profile, so they are asked
  /// for through the client's `ImageApi` instead.
  bool get hasJellyfinUserImagePath => this != ServerType.silo;

  String get productName => switch (this) {
    ServerType.jellyfin => 'Jellyfin',
    ServerType.silo => 'Silo',
  };

  /// Classifies a server from its product name.
  ///
  /// Silo's native API reports itself through `/api/v2/system/info`, which the
  /// server probe reads separately. This method still recognizes a "Silo"
  /// product name (for example a discovery hint). Silo's Jellyfin-compatible
  /// listener calls itself "Jellyfin Server" and is classified as Jellyfin.
  ///
  /// Kos TV: Emby and Plex support was removed, so anything else is treated
  /// as Jellyfin.
  static ServerType detect(String? productName, String? version) {
    if (productName != null) {
      final lower = productName.toLowerCase();
      if (lower.contains('silo')) return ServerType.silo;
    }
    return ServerType.jellyfin;
  }
}
