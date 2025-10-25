// lib/models/beacon_model.dart

import 'dart:math' as math;

class BeaconModel {
  final String id;
  final String name;
  final int rssi;
  final String location;
  final bool isSimulated;

  BeaconModel({
    required this.id,
    required this.name,
    required this.rssi,
    required this.location,
    this.isSimulated = false,
  });

  // Calculate approximate distance based on RSSI
  double get estimatedDistance {
    // Using path loss formula: distance = 10 ^ ((TxPower - RSSI) / (10 * n))
    // Where TxPower = -59 dBm at 1m, n = 2 (path loss exponent)
    const txPower = -59;
    const pathLossExponent = 2.0;

    if (rssi == 0) return 0.0;

    double ratio = (txPower - rssi) / (10 * pathLossExponent);
    return double.parse((math.pow(10, ratio) as double).toStringAsFixed(2));
  }

  String get proximityLevel {
    double distance = estimatedDistance;
    if (distance < 1) return "Immediate";
    if (distance < 3) return "Near";
    if (distance < 10) return "Far";
    return "Unknown";
  }
}

class Math {
  static double pow(num x, num exponent) {
    return math.pow(x, exponent).toDouble();
  }
}
