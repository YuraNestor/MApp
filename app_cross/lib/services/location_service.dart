import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;
  Position? currentPosition;
  double? speedKmH;
  double? heading;

  Function(Position)? onPositionChanged;
  Function(double)? onSpeedChanged;
  Function(double)? onHeadingChanged;

  Future<void> initialize() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }
  }

  void startTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, 
      )
    ).listen((Position position) {
      currentPosition = position;
      onPositionChanged?.call(position);

      speedKmH = (position.speed * 3.6); // m/s to km/h
      onSpeedChanged?.call(speedKmH!);

      if (position.heading > 0) {
        heading = position.heading;
        onHeadingChanged?.call(heading!);
      }
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}
