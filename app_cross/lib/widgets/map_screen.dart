import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../services/data_service.dart';
import 'navigation_overlay.dart';
import 'settings_dialog.dart';
import 'search_dialog.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  PointAnnotationManager? pointAnnotationManager;
  PolylineAnnotationManager? polylineAnnotationManager;

  // Services
  final LocationService _locationService = LocationService();
  final SensorService _sensorService = SensorService();
  final DataService _dataService = DataService();

  // State
  bool _isInit = false;
  bool _isRecording = false;
  double _currentRoughness = 1.0;
  double _currentSpeedKmH = 0.0;
  String _mapStyle = MapboxStyles.DARK;
  
  // Settings
  double _sensitivityMultiplier = 1.0;
  double _speedInfluenceMultiplier = 1.0;

  // Data
  List<PointData> _recordedPoints = [];
  geo.Position? _currentPos;
  PointAnnotation? _userMarker;
  PolylineAnnotation? _routeLine;

  // Destination
  geo.Position? _destination;
  String? _destinationName;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await _locationService.initialize();
      _locationService.onPositionChanged = _updateUserLocation;
      _locationService.onSpeedChanged = (speed) => setState(() => _currentSpeedKmH = speed);
      _locationService.startTracking();

      _sensorService.onRoughnessChanged = (val) {
        setState(() => _currentRoughness = val);
        if (_isRecording && _currentPos != null) {
          _recordedPoints.add(PointData(
            lat: _currentPos!.latitude,
            lng: _currentPos!.longitude,
            roughness: _currentRoughness,
            time: DateTime.now().toIso8601String(),
          ));
          _updateRouteLine();
        }
      };

      setState(() => _isInit = true);
    } catch (e) {
      print("Init error: $e");
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
    // Enable the blue location puck
    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
      showAccuracyRing: true,
    ));
    
    pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    polylineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
  }

  bool _hasCenteredInitially = false;

  void _centerOnUser() {
    if (_currentPos != null && mapboxMap != null) {
      mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(_currentPos!.longitude, _currentPos!.latitude)),
          zoom: 15.0,
          bearing: _currentPos!.heading,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }
  }

  Future<void> _updateUserLocation(geo.Position position) async {
    _currentPos = position;
    
    if (mapboxMap != null && !_hasCenteredInitially) {
       _hasCenteredInitially = true;
       _centerOnUser();
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        WakelockPlus.enable();
        _recordedPoints.clear();
        _sensorService.startTracking(_sensitivityMultiplier, _speedInfluenceMultiplier, _currentSpeedKmH);
      } else {
        WakelockPlus.disable();
        _sensorService.stopTracking();
      }
    });
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        sensitivityMultiplier: _sensitivityMultiplier,
        speedInfluenceMultiplier: _speedInfluenceMultiplier,
        currentStyle: _mapStyle,
        onSensitivityChanged: (v) => _sensitivityMultiplier = v,
        onSpeedInfluenceChanged: (v) => _speedInfluenceMultiplier = v,
        onStyleChanged: (style) {
          setState(() => _mapStyle = style);
          mapboxMap?.loadStyleURI(style);
        },
        onExport: () => _dataService.exportCsv(_recordedPoints),
        onImport: _importCsv,
      ),
    );
  }

  Future<void> _importCsv() async {
     try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String contents = await file.readAsString();
        
        List<String> lines = contents.split('\n');
        List<PointData> newPoints = [];
        
        // Skip header
        for (int i = 1; i < lines.length; i++) {
          if (lines[i].trim().isEmpty) continue;
          List<String> parts = lines[i].split(',');
          if (parts.length >= 4) {
             newPoints.add(PointData(
               lat: double.parse(parts[0]),
               lng: double.parse(parts[1]),
               roughness: double.parse(parts[2]),
               time: parts[3]
             ));
          }
        }
        
        setState(() {
          _recordedPoints = newPoints;
        });
        _updateRouteLine();
      }
    } catch (e) {
      print("Import error: $e");
    }
  }

  void _openSearch() {
    showDialog(
      context: context,
      builder: (ctx) => SearchDialog(
        onLocationSelected: (lat, lng, name) {
          setState(() {
            _destination = GeolocatorPosition(latitude: lat, longitude: lng, timestamp: DateTime.now(), accuracy: 1, altitude: 1, altitudeAccuracy: 1, heading: 1, headingAccuracy: 1, speed: 1, speedAccuracy: 1);
            _destinationName = name;
          });
          _fetchRouteToDestination(lat, lng);
        },
      ),
    );
  }

  Future<void> _fetchRouteToDestination(double destLat, double destLng) async {
    if (_currentPos == null) return;
    
    try {
       final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${_currentPos!.longitude},${_currentPos!.latitude};$destLng,$destLat'
          '?overview=full&geometries=geojson'
       );
       final response = await http.get(url);
       
       if (response.statusCode == 200) {
         final data = json.decode(response.body);
         final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
         
         List<geo.Position> linePoints = coordinates.map((coord) {
            return geo.Position(longitude: coord[0], latitude: coord[1], timestamp: DateTime.now(), accuracy: 1, altitude: 1, altitudeAccuracy: 1, heading: 1, headingAccuracy: 1, speed: 1, speedAccuracy: 1); // GeoJSON is Long, Lat
         }).toList();
         
         _drawRouteLine(linePoints, Colors.blue);
       }
    } catch (e) {
      print("Routing error: $e");
    }
  }

  void _updateRouteLine() {
    if (_recordedPoints.isEmpty) return;
    List<geo.Position> linePoints = _recordedPoints.map((p) => geo.Position(longitude: p.lng, latitude: p.lat, timestamp: DateTime.now(), accuracy: 1, altitude: 1, altitudeAccuracy: 1, heading: 1, headingAccuracy: 1, speed: 1, speedAccuracy: 1)).toList();
    // For simplicity, drawing the whole line as green during recording. 
    // In a full implementation, this would be a LineLayer with a feature collection 
    // to support multi-color segments.
    _drawRouteLine(linePoints, Colors.green);
  }
  
  Future<void> _drawRouteLine(List<geo.Position> points, Color color) async {
     if (polylineAnnotationManager == null) return;
     
     if (_routeLine != null) {
       await polylineAnnotationManager!.delete(_routeLine!);
     }
     
     var hexColor = color.value.toRadixString(16).padLeft(8, '0').substring(2);
     
     _routeLine = await polylineAnnotationManager!.create(
       PolylineAnnotationOptions(
         geometry: LineString(coordinates: points.map((p) => Position(p.longitude, p.latitude)).toList()),
         lineColor: int.parse('FF$hexColor', radix: 16),
         lineWidth: 5.0,
       )
     );
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    _sensorService.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map Background
          MapWidget(
            key: const ValueKey("mapWidget"),
            onMapCreated: _onMapCreated,
            styleUri: _mapStyle,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(24.0311, 49.8397)),
              zoom: 12.0,
            ),
          ),
          
          // Header Floating Buttons
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: _openSettings,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _openSearch,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _destinationName ?? 'Search destination...',
                              style: const TextStyle(color: Colors.grey, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          
          // Bottom Overlay
          NavigationOverlay(
            isRecording: _isRecording,
            currentRoughness: _currentRoughness,
            currentSpeedKmH: _currentSpeedKmH,
            onRecordToggle: _toggleRecording,
          ),
        ],
      ),
    );
  }
}

// Helper to bridge Geolocator class name collision
class GeolocatorPosition extends geo.Position {
   GeolocatorPosition({required super.longitude, required super.latitude, required super.timestamp, required super.accuracy, required super.altitude, required super.altitudeAccuracy, required super.heading, required super.headingAccuracy, required super.speed, required super.speedAccuracy});
}
