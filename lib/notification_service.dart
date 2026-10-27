import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> init() async {
    await localNotifier.setup(
      appName: 'OTP Watcher',
      shortcutPolicy: ShortcutPolicy.ignore,
    );
  }

  Future<void> showOtpNotification({
    required String otp,
    required String message,
  }) async {
    // show desktop notification
    final notification = LocalNotification(
      title: '🔐 New OTP Detected',
      body: 'Code: $otp\n$message',
    );
    await notification.show();

    // play sound
    await _playAlert();
  }

  Future<void> _playAlert() async {
    try {
      String soundPath = 'assets/audio/alert.mp3';
      await _player.play(AssetSource(soundPath));
    } catch (e) {
      debugPrint('Error playing alert: $e');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
