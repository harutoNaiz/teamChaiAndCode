import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/chat_screen.dart';
import 'theme/app_theme.dart';

import 'services/agent_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AgentService.instance.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TeamChaiAndCodeApp());
}

class TeamChaiAndCodeApp extends StatelessWidget {
  const TeamChaiAndCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'teamChaiAndCode',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // ChatGPT dark-first aesthetic
      home: const ChatScreen(),
    );
  }
}
