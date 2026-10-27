import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(480, 680),
    minimumSize: Size(400, 560),
    center: true,
    title: 'OTP Watcher',
    titleBarStyle: TitleBarStyle.hidden, // clean look on macOS
    backgroundColor: Color(0xFF0F1117),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OtpWatcherApp());
}

class OtpWatcherApp extends StatelessWidget {
  const OtpWatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTP Watcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF1A1D27),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
