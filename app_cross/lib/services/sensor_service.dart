import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  
  // Roughness logic identical to the web app
  double roughness = 1;
  final int averageWindowSize = 15;
  List<double> magHistory = [];

  Function(double)? onRoughnessChanged;

  void startTracking(double sensitivityMultiplier, double speedInfluenceMultiplier, double currentSpeedKmH) {
    _accelSubscription = userAccelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).listen((UserAccelerometerEvent event) {
      // Get magnitude of acceleration vector (X and Y only)
      // We ignore Z-axis (forward/backward) so that braking/accelerating the car
      // doesn't register as a bad road.
      // Assumes phone is mounted in a standard dashboard orientation where
      // Y is vertical (up/down bumps) and X is lateral (left/right sway).
      final mag = math.sqrt(event.x * event.x + event.y * event.y);
      
      magHistory.add(mag);
      if (magHistory.length > averageWindowSize) {
        magHistory.removeAt(0);
      }

      // Calculate standard deviation of magnitude
      double mean = magHistory.reduce((a, b) => a + b) / magHistory.length;
      double variance = magHistory.map((val) => (val - mean) * (val - mean)).reduce((a, b) => a + b) / magHistory.length;
      
      // Calculate speed factor
      // Base roughness heavily influenced by speed, higher speed dampens the raw shock reading
      double speedFactor = 1.0;
      if (currentSpeedKmH > 20) {
          speedFactor = 20 / currentSpeedKmH; 
      }
      
      // Speed multiplier from user settings
      double speedMultiplier = 1.0 + ((speedInfluenceMultiplier - 1.0) * (1.0 - speedFactor));

      // Calculate final scaled roughness index (1-4 expected range)
      double calculatedRoughness = (variance * sensitivityMultiplier * speedMultiplier).clamp(0.0, 50.0);
      
      // Determine bucket based on web logic:
      // roughness < 1.0 => 1 (Green/Good)
      // roughness < 2.5 => 2 (Yellow/Fair)
      // roughness < 5.0 => 3 (Orange/Poor)
      // roughness >= 5.0 => 4 (Red/Bad)
      
      double roughnessClass = 1;
      if (calculatedRoughness < 1.0) {
        roughnessClass = 1;
      } else if (calculatedRoughness < 2.5) {
        roughnessClass = 2;
      } else if (calculatedRoughness < 5.0) {
        roughnessClass = 3;
      } else {
        roughnessClass = 4;
      }

      if (roughnessClass != roughness) {
        roughness = roughnessClass;
        onRoughnessChanged?.call(roughness);
      }
    });
  }

  void stopTracking() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    magHistory.clear();
  }
}
