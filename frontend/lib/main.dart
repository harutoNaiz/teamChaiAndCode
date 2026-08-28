import 'package:flutter/material.dart';

void main() {
  runApp(const TeamChaiAndCodeApp());
}

class TeamChaiAndCodeApp extends StatelessWidget {
  const TeamChaiAndCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: Center(child: Text('teamChaiAndCode'))));
  }
}
