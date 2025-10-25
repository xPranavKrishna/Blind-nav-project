import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(NaviAiApp());
}

class NaviAiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAVI-AI Indoor Navigation',
      theme: ThemeData(
        primaryColor: Color(0xFF5B8DBE),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
