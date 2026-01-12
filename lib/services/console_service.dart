import 'dart:async';
import 'package:flutter/foundation.dart';

class ConsoleService {
  static final ConsoleService _instance = ConsoleService._internal();
  factory ConsoleService() => _instance;
  ConsoleService._internal();

  final ValueNotifier<List<String>> logs = ValueNotifier([]);

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final logMsg = "[$timestamp] $message";
    print(logMsg); // Also print to system console
    
    // Add to list (keep last 50)
    final currentLogs = List<String>.from(logs.value);
    currentLogs.insert(0, logMsg);
    if (currentLogs.length > 50) {
      currentLogs.removeLast();
    }
    logs.value = currentLogs;
  }
}
