import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

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

    // Haptic feedback
    try {
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  // Show Full-Screen / Heads-up Incoming Call with System Default Ringtone and Continuous Vibration
  Future<void> showIncomingCallNotification({
    required int id,
    required String callerName,
    required String callType,
  }) async {
    final AndroidNotificationDetails androidCallDetails = AndroidNotificationDetails(
      'whatsapp_calls_channel_v2',
      'Gelen Aramalar',
      channelDescription: 'Gelen sesli ve görüntülü aramalar',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([
        0, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000,
        1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000
      ]),
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

  // Start Playing Incoming Call Ringtone
  Future<void> startRingtone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(
        UrlSource('https://cdn.freesound.org/previews/218/218333_4056007-lq.mp3'),
      );
    } catch (_) {}
  }

  // Stop Ringtone
  Future<void> stopRingtone() async {
    _isRinging = false;
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }
}




