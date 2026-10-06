import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRinging = false;

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
  }

  // Show Heads-up Notification for Incoming Messages
  Future<void> showMessageNotification({
    required int id,
    required String senderName,
    required String messageContent,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'whatsapp_messages',
      'Mesajlar',
      channelDescription: 'Gelen anlık sohbet mesajları',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id,
      senderName,
      messageContent,
      notificationDetails,
    );

    // Quick vibration buzz for message
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 300);
    }
  }

  // Show Full-Screen / Heads-up Incoming Call with System Default Ringtone
  Future<void> showIncomingCallNotification({
    required int id,
    required String callerName,
    required String callType,
  }) async {
    final AndroidNotificationDetails androidCallDetails = AndroidNotificationDetails(
      'whatsapp_calls_channel',
      'Gelen Aramalar',
      channelDescription: 'Gelen sesli ve görüntülü aramalar',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
    );

    final NotificationDetails callNotificationDetails = NotificationDetails(
      android: androidCallDetails,
    );

    await _notificationsPlugin.show(
      id,
      'Gelen Arama',
      '$callerName sizi $callType arıyor...',
      callNotificationDetails,
    );
  }

  // Cancel Call Notification
  Future<void> cancelCallNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    stopRingtone();
  }

  // Start Playing Incoming Call Ringtone & Continuous Vibration
  Future<void> startRingtone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      // Continuous pattern vibration until call ends: [wait 500ms, vibrate 1000ms, pause 1000ms, repeat]
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(
          pattern: [500, 1000, 1000, 1000, 1000, 1000, 1000, 1000],
          repeat: 1, // Repeat indefinitely
        );
      }

      _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(
        UrlSource('https://cdn.freesound.org/previews/218/218333_4056007-lq.mp3'),
      );
    } catch (_) {}
  }

  // Stop Ringtone & Cancel Vibration
  Future<void> stopRingtone() async {
    _isRinging = false;
    try {
      Vibration.cancel();
      await _ringtonePlayer.stop();
    } catch (_) {}
  }
}



