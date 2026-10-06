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
  }

  // Start Playing Incoming Call Ringtone
  Future<void> startRingtone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      // Play a standard telephone / mobile phone ringing audio stream
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

