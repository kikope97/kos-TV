import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android channel the request notifications of earlier versions posted to.
/// Nothing posts there any more, so it's deleted to keep it from lingering in
/// the app's notification settings after an update.
const String _retiredRequestsChannelId = 'seerr_notifications';

class LocalNotificationBootstrap {
  LocalNotificationBootstrap._();

  static final LocalNotificationBootstrap instance =
      LocalNotificationBootstrap._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await plugin.initialize(settings: initSettings);

    try {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.deleteNotificationChannel(channelId: _retiredRequestsChannelId);
    } catch (_) {}
    _initialized = true;
  }
}
