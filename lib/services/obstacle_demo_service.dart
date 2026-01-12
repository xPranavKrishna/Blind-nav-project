import 'dart:async';
import 'dart:math';

class ObstacleDemoService {
  final StreamController<bool> _obstacleController = StreamController<bool>.broadcast();
  Stream<bool> get obstacleStream => _obstacleController.stream;
  Timer? _simulationTimer;

  void startSimulation() {
    // Randomly trigger obstacle every 10-20 seconds for demo
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (Random().nextBool()) {
        triggerObstacle();
      }
    });
  }

  void triggerObstacle() {
    _obstacleController.add(true);
    // Auto-clear after 3 seconds for demo flow, or let user clear it?
    // For now, just trigger it. The UI should handle the "Stop" and then resume.
    Future.delayed(Duration(seconds: 5), () {
      _obstacleController.add(false);
    });
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
  }

  void dispose() {
    _obstacleController.close();
  }
}
