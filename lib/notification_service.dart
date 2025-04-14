import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart'; // ✅ Needed for notifications permission

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(initializationSettings);

    // ✅ Correct way to request permission
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  static Future<void> scheduleCheckInNotifications() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'milo_channel',
      'Milo Check-ins',
      channelDescription: 'Friendly Milo check-ins',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.periodicallyShow(
      0,
      '🐾 Milo Check-in!',
      'Hey there! Want to talk or record a memory?',
      RepeatInterval.hourly,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // 🔥 Temporary: for testing
  static Future<void> showImmediateTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'milo_test_channel',
      'Milo Test Notifications',
      channelDescription: 'Immediate notification for testing',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      1,
      '🐾 Milo says hello!',
      'This is a quick test notification.',
      notificationDetails,
    );
  }
}
