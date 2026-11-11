class WebRuntimeConfig {
  final int schemaVersion;
  final String? defaultServerUrl;
  final String? discoveryProxyUrl;
  final bool enableWebRtcScan;
  final String? brandingName;
  final bool pluginMode;
  final String? forcedServerUrl;

  /// Kos TV: the household Jellyfin server (`serverUrl`), opened straight on
  /// its sign-in like the apps' built-in one.
  final String? kostvServerUrl;

  /// Kos TV: the requests service (`requestsUrl`), usually the path the
  /// container passes on to it (`/stremfin`).
  final String? kostvRequestsUrl;

  const WebRuntimeConfig({
    required this.schemaVersion,
    required this.defaultServerUrl,
    required this.discoveryProxyUrl,
    required this.enableWebRtcScan,
    required this.brandingName,
    required this.pluginMode,
    required this.forcedServerUrl,
    this.kostvServerUrl,
    this.kostvRequestsUrl,
  });

  static const defaults = WebRuntimeConfig(
    schemaVersion: 1,
    defaultServerUrl: null,
    discoveryProxyUrl: null,
    enableWebRtcScan: true,
    brandingName: 'kOS TV',
    pluginMode: false,
    forcedServerUrl: null,
  );

  factory WebRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final defaultServerUrl = _readNullableString(json['defaultServerUrl']);
    final discoveryProxyUrl = _readNullableString(json['discoveryProxyUrl']);
    final brandingName = _readNullableString(json['brandingName']);
    final forcedServerUrl = _readNullableString(json['forcedServerUrl']);

    return WebRuntimeConfig(
      schemaVersion: _readInt(json['schemaVersion']) ?? defaults.schemaVersion,
      defaultServerUrl: defaultServerUrl,
      discoveryProxyUrl: discoveryProxyUrl,
      enableWebRtcScan:
          _readBool(json['enableWebRtcScan']) ?? defaults.enableWebRtcScan,
      brandingName: brandingName ?? defaults.brandingName,
      pluginMode: _readBool(json['pluginMode']) ?? defaults.pluginMode,
      forcedServerUrl: forcedServerUrl,
      kostvServerUrl: _readNullableString(json['serverUrl']),
      kostvRequestsUrl: _readNullableString(json['requestsUrl']),
    );
  }

  static String? _readNullableString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text;
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
