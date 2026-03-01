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

  void startTracking() {
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
      
      // Calculate final raw scaled roughness
      double calculatedRoughness = variance.clamp(0.0, 50.0);
      
      double finalRoughness = calculatedRoughness.clamp(0.0, 10.0);

      // Only notify if the change is significant (e.g., > 0.2) to prevent
      // excessive setState calls and UI rebuilds at 50fps.
      if ((finalRoughness - roughness).abs() > 0.2) {
        roughness = finalRoughness;
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
