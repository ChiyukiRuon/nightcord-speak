import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> initSystemNotifications() async {}

// Permission is requested from the gateway form's explicit user action.
Future<void> requestNotificationPermission() async {
  try {
    if (web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  } catch (_) {
    // Some mobile browsers expose notifications only to installed web apps.
  }
}

Future<void> showSystemNotification({required String title, required String body}) async {
  try {
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
  } catch (_) {
    // Mobile browsers without document notifications retain the in-app notice.
  }
}
