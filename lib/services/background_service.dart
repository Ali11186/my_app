import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notificationsPlugin.initialize(const InitializationSettings(android: android));
}

Future<void> showNotification(String message) async {
  const details = AndroidNotificationDetails(
    'vodafone_chat', 'Vodafone Chat',
    channelDescription: 'رسائل خدمة العملاء',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  await notificationsPlugin.show(
    0, 'خدمة العملاء - فودافون', message,
    const NotificationDetails(android: details),
  );
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'vodafone_chat',
      initialNotificationTitle: 'Vodafone Care',
      initialNotificationContent: 'المحادثة شغالة في الخلفية',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await initNotifications();
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
  service.on('newMessage').listen((event) async {
    if (event != null && event['message'] != null) {
      await showNotification(event['message']);
    }
  });
}

void startBackgroundService() {
  FlutterBackgroundService().startService();
}

void stopBackgroundService() {
  FlutterBackgroundService().invoke('stopService');
}

void sendMessageToBackground(String message) {
  FlutterBackgroundService().invoke('newMessage', {'message': message});
}
