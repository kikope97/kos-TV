enum CastTargetKind {
  jellyfinSession,
  googleCast,
  airPlay,
  dlna,
}

class CastTarget {
  final String id;
  final CastTargetKind kind;
  final String title;
  final String subtitle;

  /// Kos TV: the device is playing something whose name is unknown. The
  /// list words that; [subtitle] stays empty.
  final bool nowPlaying;

  const CastTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.nowPlaying = false,
  });
}
