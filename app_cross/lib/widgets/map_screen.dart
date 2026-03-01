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
      };

      setState(() => _isInit = true);
    } catch (e) {
      print("Init error: $e");
    }
  }

  CircleAnnotationManager? circleAnnotationManager;

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
    circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
  }

  bool _hasCenteredInitially = false;
  bool _isCentered = false;
  bool _isCenteredTriggeredByButton = false;

  void _centerOnUser() {
    if (_currentPos != null && mapboxMap != null) {
      setState(() {
        _isCentered = true;
      });
      _isCenteredTriggeredByButton = true;
      
      mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(_currentPos!.longitude, _currentPos!.latitude)),
          zoom: 15.0,
          bearing: _currentPos!.heading,
        ),
        MapAnimationOptions(duration: 1000),
      ).then((_) {
         Future.delayed(const Duration(milliseconds: 100), () {
            _isCenteredTriggeredByButton = false;
         });
      });
    }
  }

  Future<void> _updateUserLocation(geo.Position position) async {
    _currentPos = position;
    
    if (_isRecording) {
      _recordedPoints.add(PointData(
         timestamp: DateTime.now().toIso8601String(),
         lat: position.latitude,
         lng: position.longitude,
         roughness: _currentRoughness,
         speed: _currentSpeedKmH,
         heading: position.heading,
      ));
      _updateRouteLine();
    }
    
    if (mapboxMap != null) {
      if (!_hasCenteredInitially) {
        _hasCenteredInitially = true;
        _centerOnUser();
      } else if (_isCentered && !_isCenteredTriggeredByButton) {
        mapboxMap!.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(position.longitude, position.latitude)),
            bearing: position.heading,
          ),
        );
      }
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        WakelockPlus.enable();
        // Removed _recordedPoints.clear() to keep previously recorded points on map
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
          // When style changes, recreate the map widget (or use Mapbox style loading APIs)
        },
        onExport: () => _dataService.exportCsv(_recordedPoints),
        onImport: _importData,
      ),
    );
  }

  Future<void> _importData() async {
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
          // Expected format: timestamp,lat,lng,roughness,speed,heading
          if (parts.length >= 6) {
             newPoints.add(PointData(
               timestamp: parts[0],
               lat: double.tryParse(parts[1]) ?? 0.0,
               lng: double.tryParse(parts[2]) ?? 0.0,
               roughness: double.tryParse(parts[3]) ?? 1.0,
               speed: double.tryParse(parts[4]) ?? 0.0,
               heading: double.tryParse(parts[5]) ?? 0.0,
             ));
          } else if (parts.length >= 4) {
             // Fallback for older CSV format without speed/heading
             newPoints.add(PointData(
               timestamp: parts[3],
               lat: double.tryParse(parts[0]) ?? 0.0,
               lng: double.tryParse(parts[1]) ?? 0.0,
               roughness: double.tryParse(parts[2]) ?? 1.0,
               speed: 0.0,
               heading: 0.0,
             ));
          }
        }
        
        setState(() {
          _recordedPoints.addAll(newPoints); // Append imported points to existing layout
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
    _drawRecordedPoints();
  }

  List<CircleAnnotation?> _recordedPointAnnotations = [];

  Future<void> _drawRecordedPoints() async {
    if (circleAnnotationManager == null) return;

    // Clear existing points
    if (_recordedPointAnnotations.isNotEmpty) {
      await circleAnnotationManager!.deleteAll();
      _recordedPointAnnotations.clear();
    }

    List<CircleAnnotationOptions> optionsList = _recordedPoints.map((p) {
      Color pointColor;
      if (p.roughness == 1.0) {
        pointColor = Colors.green;
      } else if (p.roughness == 2.0) {
        pointColor = Colors.yellow;
      } else if (p.roughness == 3.0) {
        pointColor = Colors.orange;
      } else if (p.roughness == 4.0) {
        pointColor = Colors.red;
      } else {
        // Fallback for older imports where roughness was the raw variance float instead of a bucket
        if (p.roughness < 1.0) pointColor = Colors.green;
        else if (p.roughness < 2.5) pointColor = Colors.yellow;
        else if (p.roughness < 5.0) pointColor = Colors.orange;
        else pointColor = Colors.red;
      }

      var hexColor = pointColor.value.toRadixString(16).padLeft(8, '0').substring(2);

      return CircleAnnotationOptions(
        geometry: Point(coordinates: Position(p.lng, p.lat)),
        circleColor: int.parse('FF$hexColor', radix: 16),
        circleRadius: 6.0,
        circleStrokeWidth: 1.0,
        circleStrokeColor: 0xFFFFFFFF, // white border
      );
    }).toList();

    _recordedPointAnnotations = await circleAnnotationManager!.createMulti(optionsList);
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
            onScrollListener: (_) {
              if (_isCentered && !_isCenteredTriggeredByButton) {
                setState(() => _isCentered = false);
              }
            },
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
          
          // Center Location Button
          Positioned(
            bottom: 150,
            right: 20,
            child: AnimatedOpacity(
              opacity: _isCentered ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: _isCentered,
                child: FloatingActionButton(
                  heroTag: 'centerMapBtn',
                  backgroundColor: Colors.blueAccent,
                  onPressed: _centerOnUser,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
              ),
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
