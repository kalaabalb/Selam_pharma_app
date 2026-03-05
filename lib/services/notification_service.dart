import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:hive/hive.dart';
import '../screens/trash_screen.dart';
import '../screens/notification_screen.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  GlobalKey<NavigatorState>? navigatorKey;

  /// Returns the current value of the user preference controlling whether
  /// notifications should be shown at all. Defaults to true when the box is
  /// not yet opened.
  bool get _notificationsAllowed {
    try {
      final box = Hive.box('settings');
      return box.get('notifications_enabled', defaultValue: true) as bool;
    } catch (_) {
      return true;
    }
  }

  /// Public helper used by callers or tests to determine whether a notification
  /// would actually be shown/scheduled.  If [payload] starts with
  /// "trash:" and [isScheduled] is true, this also considers the per‑feature trash toggle.
  bool areNotificationsAllowed({String? payload, bool isScheduled = false}) {
    if (!_notificationsAllowed) return false;
    if (payload != null && payload.startsWith('trash:') && isScheduled) {
      try {
        final box = Hive.box('settings');
        final trashAllowed =
            box.get('trash_notifications_enabled', defaultValue: true) as bool;
        if (!trashAllowed) return false;
      } catch (_) {
        // ignore errors; default to allowing
      }
    }
    return true;
  }

  /// Update the persisted preference and if notifications are being turned
  /// off, cancel any pending notifications right away.
  Future<void> setNotificationsEnabled(bool enabled) async {
    try {
      final box = Hive.box('settings');
      await box.put('notifications_enabled', enabled);
    } catch (_) {}
    if (!enabled) {
      try {
        await cancelAll();
      } catch (_) {}
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final String localTz = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // fallback to UTC if timezone lookup fails
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const initSettings = InitializationSettings(
      android: android,
      iOS: ios,
      linux: linux,
    );
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) async {
        final payload = details.payload;
        if (payload != null) {
          try {
            if (payload.startsWith('notif:')) {
              navigatorKey?.currentState?.push(
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              );
            } else if (payload.startsWith('trash:')) {
              navigatorKey?.currentState?.push(
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
            }
          } catch (_) {}
        }
      },
    );
    _initialized = true;
  }

  int _idFor(String id, int offset) {
    // stable, non-negative id per notification type per medicine
    final h = id.hashCode;
    return (h.abs() % 1000000) + (offset * 1000000);
  }

  Future<void> showImmediate({
    required String title,
    required String body,
    int id = 0,
    String? payload,
  }) async {
    await initialize();
    if (!areNotificationsAllowed(payload: payload)) return;
    final android = AndroidNotificationDetails(
      'shmed_chan',
      'App notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    final ios = DarwinNotificationDetails();
    final linux = LinuxNotificationDetails();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: ios,
        linux: linux,
      ),
      payload: payload,
    );
  }

  Future<void> schedule({
    required String notifId,
    required int offset,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    await initialize();
    if (!areNotificationsAllowed(payload: payload, isScheduled: true)) return;
    final ident = _idFor(notifId, offset);
    final android = AndroidNotificationDetails(
      'shmed_chan',
      'App notifications',
      importance: Importance.defaultImportance,
    );
    final ios = DarwinNotificationDetails();
    final linux = LinuxNotificationDetails();
    await _plugin.zonedSchedule(
      id: ident,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: NotificationDetails(
        android: android,
        iOS: ios,
        linux: linux,
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelFor(String notifId) async {
    await initialize();
    // cancel three offsets (2-day,1-day,final)
    for (var offset = 0; offset < 3; offset++) {
      final id = _idFor(notifId, offset);
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}
