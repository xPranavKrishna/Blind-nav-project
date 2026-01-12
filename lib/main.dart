import 'package:flutter/material.dart';
import 'pages/home_page.dart';

import 'package:firebase_core/firebase_core.dart';

import 'services/console_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    ConsoleService().log("Initializing Firebase...");
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCwfUETc5T001Wrl0XQfsHrYLwWarIKtzw",
        appId: "1:435173981948:android:f10904f053671c8115a179",
        messagingSenderId: "435173981948",
        projectId: "navi-ai-indoor-navigation",
        storageBucket: "navi-ai-indoor-navigation.firebasestorage.app",
        databaseURL: "https://navi-ai-indoor-navigation-default-rtdb.asia-southeast1.firebasedatabase.app",
      ),
    );
    ConsoleService().log("Firebase Initialized Successfully");
  } catch (e) {
    ConsoleService().log("Firebase Init Error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vazhikaatti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.yellow,
        brightness: Brightness.dark, // High contrast by default
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
