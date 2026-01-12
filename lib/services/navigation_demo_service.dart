import 'dart:async';
import '../utils/demo_locations.dart';

class NavigationDemoService {
  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  Stream<Map<String, dynamic>> startNavigation(String destination) async* {
    _isNavigating = true;
    List<Map<String, dynamic>> steps = DemoLocations.getRoute(destination);

    for (var step in steps) {
      if (!_isNavigating) break;
      yield step;
      await Future.delayed(Duration(seconds: step['duration']));
    }
    _isNavigating = false;
  }

  void stopNavigation() {
    _isNavigating = false;
  }
}
