import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'dart:math' as math;

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
  PolygonAnnotationManager? polygonAnnotationManager;
  CircleAnnotationManager? circleAnnotationManager;

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
  List<PolylineAnnotation?> _routeLines = [];

  // Destination
  geo.Position? _destination;
  String? _destinationName;
  bool _hasRoute = false;
  bool _showRouteActions = false;
  bool _isDrivingMode = false;
  List<geo.Position> _currentRoutePoints = [];
  Uint8List? _arrowImage;

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

  Future<void> _updateLocationPuck() async {
    if (mapboxMap == null) return;
    await mapboxMap!.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: !_isDrivingMode,
      showAccuracyRing: !_isDrivingMode,
      puckBearing: PuckBearing.COURSE,
      puckBearingEnabled: _isDrivingMode,
      locationPuck: (_isDrivingMode && _arrowImage != null) ? LocationPuck(
        locationPuck2D: LocationPuck2D(
          bearingImage: _arrowImage!,
        )
      ) : null,
    ));
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/arrow.png');
      _arrowImage = bytes.buffer.asUint8List();
    } catch (e) {
      print("Could not load custom arrow: $e");
    }

    // Enable the location puck, overriding the blue dot with our custom arrow if available
    await _updateLocationPuck();
    
    pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    polylineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    polygonAnnotationManager = await mapboxMap.annotations.createPolygonAnnotationManager();
    circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    
    mapboxMap.gestures.getSettings().then((settings) {
       mapboxMap.gestures.updateSettings(
          GesturesSettings(
             rotateEnabled: true,
             pitchEnabled: true,
          )
       );
    });
    
    // Attach gesture listeners
    mapboxMap.addInteraction(LongTapInteraction.onMap(_onMapLongClickListener));
  }

  void _cancelRoute() async {
    setState(() {
      _destination = null;
      _destinationName = null;
      _hasRoute = false;
      _isDrivingMode = false;
      _showRouteActions = false;
      _currentRoutePoints.clear();
      _isCentered = false;
    });
    _updateLocationPuck();
    
    if (polylineAnnotationManager != null && _routeLines.isNotEmpty) {
      for (var line in _routeLines) {
        if (line != null) await polylineAnnotationManager!.delete(line);
      }
      _routeLines.clear();
    }
    if (pointAnnotationManager != null && _userMarker != null) {
      await pointAnnotationManager!.delete(_userMarker!);
      _userMarker = null;
    }
    // Restore recorded points after route is gone
    _drawRecordedPoints();
  }

  void _drawDestinationMarker(double lat, double lng) async {
    if (pointAnnotationManager == null) return;
    
    if (_userMarker != null) {
      await pointAnnotationManager!.delete(_userMarker!);
    }
    Uint8List? markerImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/marker.png');
      markerImage = bytes.buffer.asUint8List();
    } catch (e) {
      print("Could not load custom marker: $e");
    }

    _userMarker = await pointAnnotationManager!.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(lng, lat)),
        image: markerImage,
        iconSize: 3.0,
        iconAnchor: IconAnchor.BOTTOM
      )
    );
  }

  void _onMapLongClickListener(MapContentGestureContext context) {
    if (_hasRoute) return; 
    
    double lat = context.point.coordinates.lat as double;
    double lng = context.point.coordinates.lng as double;

    setState(() {
      _destinationName = "Dropped Pin (${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)})";
      _destination = GeolocatorPosition(latitude: lat, longitude: lng, timestamp: DateTime.now(), accuracy: 1, altitude: 1, altitudeAccuracy: 1, heading: 1, headingAccuracy: 1, speed: 1, speedAccuracy: 1);
      _showRouteActions = true;
    });
    
    _drawDestinationMarker(lat, lng);
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
      
      mapboxMap!.getCameraState().then((state) {
          CameraOptions cameraOpts;
          if (_isDrivingMode) {
             cameraOpts = CameraOptions(
               center: Point(coordinates: Position(_currentPos!.longitude, _currentPos!.latitude)),
               bearing: _currentPos!.heading,
               padding: MbxEdgeInsets(top: MediaQuery.of(context).size.height * 0.6, left: 0, bottom: 0, right: 0), // Shift puck downwards below center
               pitch: 60.0,
               zoom: 20.0,
             );
          } else {
             cameraOpts = CameraOptions(
               center: Point(coordinates: Position(_currentPos!.longitude, _currentPos!.latitude)),
               bearing: 0,
               padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
               pitch: 0,
               zoom: state.zoom,
             );
          }
          
          mapboxMap!.flyTo(
            cameraOpts,
            MapAnimationOptions(duration: 1000),
          ).then((_) {
             Future.delayed(const Duration(milliseconds: 100), () {
                _isCenteredTriggeredByButton = false;
             });
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
        mapboxMap!.getCameraState().then((state) {
            if (_isDrivingMode) {
               mapboxMap!.setCamera(
                 CameraOptions(
                   center: Point(coordinates: Position(position.longitude, position.latitude)),
                   bearing: position.heading,
                   padding: MbxEdgeInsets(top: MediaQuery.of(context).size.height * 0.6, left: 0, bottom: 0, right: 0),
                   pitch: 60.0,
                   zoom: state.zoom,
                 ),
               );
            } else {
               mapboxMap!.setCamera(
                 CameraOptions(
                   center: Point(coordinates: Position(position.longitude, position.latitude)),
                   bearing: 0,
                   padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                   zoom: state.zoom,
                 ),
               );
            }
        });
      }
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        WakelockPlus.enable();
        // Removed _recordedPoints.clear() to keep previously recorded points on map
        _sensorService.startTracking();
      } else {
        WakelockPlus.disable();
        _sensorService.stopTracking();
      }
    });
  }

  Future<void> _openSettings() async {
    await showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        sensitivityMultiplier: _sensitivityMultiplier,
        speedInfluenceMultiplier: _speedInfluenceMultiplier,
        currentStyle: _mapStyle,
        onSensitivityChanged: (v) {
          _sensitivityMultiplier = v;
        },
        onSpeedInfluenceChanged: (v) {
          _speedInfluenceMultiplier = v;
        },
        onStyleChanged: (style) {
          setState(() => _mapStyle = style);
          mapboxMap?.loadStyleURI(style);
        },
        onExport: () => _dataService.exportCsv(_recordedPoints),
        onImport: _importData,
      ),
    );
    
    // Trigger map redraw once the dialog closes
    _updateRouteLine();
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
            _showRouteActions = true;
            if(_destination!=null){
              _isCentered = false;
              _updateUserLocation(_destination!);
            }

          });
          _drawDestinationMarker(lat, lng);


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
         
         setState(() {
            _currentRoutePoints = linePoints;
            _hasRoute = true;
         });
         
         _drawRouteLine(linePoints, Colors.blue);
         _hideRecordedPoints();
         _zoomToBounds(linePoints);
       }
    } catch (e) {
      print("Routing error: $e");
    }
  }

  void _zoomToBounds(List<geo.Position> routeParams) {
     if (mapboxMap == null || routeParams.isEmpty) return;
     
     double minLat = routeParams.first.latitude;
     double maxLat = routeParams.first.latitude;
     double minLng = routeParams.first.longitude;
     double maxLng = routeParams.first.longitude;
     
     for (var p in routeParams) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
     }
     
     // Include user current position in bounds
     if (_currentPos != null) {
        if (_currentPos!.latitude < minLat) minLat = _currentPos!.latitude;
        if (_currentPos!.latitude > maxLat) maxLat = _currentPos!.latitude;
        if (_currentPos!.longitude < minLng) minLng = _currentPos!.longitude;
        if (_currentPos!.longitude > maxLng) maxLng = _currentPos!.longitude;
     }

     mapboxMap!.cameraForCoordinateBounds(
        CoordinateBounds(
           southwest: Point(coordinates: Position(minLng, minLat)),
           northeast: Point(coordinates: Position(maxLng, maxLat)),
           infiniteBounds: true,
        ),
        MbxEdgeInsets(top: 100.0, left: 50.0, bottom: 250.0, right: 50.0),
        null,
        null,
        null,
        null,
     ).then((cameraOpts) {
        mapboxMap!.flyTo(cameraOpts, MapAnimationOptions(duration: 1000));
        setState(() => _isCentered = false);
     });
  }

  void _updateRouteLine() {
    if (_recordedPoints.isEmpty) return;
    _drawRecordedPoints();
  }

  Future<void> _hideRecordedPoints() async {
    if (_recordedPointAnnotations.isNotEmpty) {
      await polygonAnnotationManager?.deleteAll();
      _recordedPointAnnotations = [];
    }
    if (_recordedCircleAnnotations.isNotEmpty) {
      await circleAnnotationManager?.deleteAll();
      _recordedCircleAnnotations = [];
    }
  }

  List<PolygonAnnotation?> _recordedPointAnnotations = [];
  List<CircleAnnotation?> _recordedCircleAnnotations = [];

  List<Position> _createCirclePolygon(double lat, double lng, double radiusMeters) {
    List<Position> points = [];
    int segments = 10;
    double earthRadius = 6378137.0;
    
    double latRad = lat * math.pi / 180.0;
    double lngRad = lng * math.pi / 180.0;
    double d = radiusMeters / earthRadius;

    for (int i = 0; i <= segments; i++) {
      double bearing = 2.0 * math.pi * i / segments;
      double ptLatRad = math.asin(
        math.sin(latRad) * math.cos(d) +
        math.cos(latRad) * math.sin(d) * math.cos(bearing)
      );
      double ptLngRad = lngRad + math.atan2(
        math.sin(bearing) * math.sin(d) * math.cos(latRad),
        math.cos(d) - math.sin(latRad) * math.sin(ptLatRad)
      );
      points.add(Position(ptLngRad * 180.0 / math.pi, ptLatRad * 180.0 / math.pi));
    }
    return points;
  }

  Future<void> _drawRecordedPoints() async {
    if (polygonAnnotationManager == null || circleAnnotationManager == null) return;

    try {
      // Clear existing points
      if (_recordedPointAnnotations.isNotEmpty) {
        await polygonAnnotationManager!.deleteAll();
        _recordedPointAnnotations = [];
      }
      if (_recordedCircleAnnotations.isNotEmpty) {
        await circleAnnotationManager!.deleteAll();
        _recordedCircleAnnotations = [];
      }

      if (_recordedPoints.isEmpty) return;

      List<PolygonAnnotationOptions> polygonOptionsList = [];
      List<CircleAnnotationOptions> circleOptionsList = [];

      for (var p in _recordedPoints) {
        // Calculate speed factor
        double speedFactor = 1.0;
        if (p.speed > 20) {
            speedFactor = 20 / p.speed; 
        }
        
        // Speed multiplier from user settings
        double speedMultiplier = 1.0 + ((_speedInfluenceMultiplier - 1.0) * (1.0 - speedFactor));

        // Custom Red-Green Gradient algorithm
        double adjustedRoughness = p.roughness * _sensitivityMultiplier * speedMultiplier;
        double clampedRoughness = adjustedRoughness.clamp(0.0, 10.0);
        int r, g;
        
        if (clampedRoughness <= 5) {
          g = 255;
          r = ((clampedRoughness / 5.0) * 255.0).round();
        } else {
          r = 255;
          g = ((1.0 - ((clampedRoughness - 5.0) / 5.0)) * 255.0).round();
        }
        
        Color pointColor = Color.fromARGB(255, r, g, 0);
        var hexColor = pointColor.value.toRadixString(16).padLeft(8, '0').substring(2);

        // 2.0 meter radius = 4.0 meter diameter
        polygonOptionsList.add(PolygonAnnotationOptions(
          geometry: Polygon(coordinates: [_createCirclePolygon(p.lat, p.lng, 2.0)]),
          fillColor: int.parse('FF$hexColor', radix: 16),
        ));

        // 3.0 pixel radius minimal visual fallback for low zooms
        circleOptionsList.add(CircleAnnotationOptions(
          geometry: Point(coordinates: Position(p.lng, p.lat)),
          circleColor: int.parse('FF$hexColor', radix: 16),
          circleRadius: 3.0,
        ));
      }

      _recordedPointAnnotations = await polygonAnnotationManager!.createMulti(polygonOptionsList);
      _recordedCircleAnnotations = await circleAnnotationManager!.createMulti(circleOptionsList);
    } catch (e, stacktrace) {
      print("Error in _drawRecordedPoints: $e");
      print(stacktrace);
    }
  }
  
  // Haversine distance in meters between two lat/lng pairs
  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLam = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) *
        math.sin(dLam / 2) * math.sin(dLam / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  // Perpendicular distance from point p to segment [start, end] (in meters)
  // start/end are [lng, lat], p has p.lat/p.lng
  double _getPerpendicularDist(PointData p, List<double> start, List<double> end) {
    const R = 6371000.0;
    const d2r = math.pi / 180;

    final lat1 = start[1] * d2r;
    final lng1 = start[0] * d2r;
    final lat2 = end[1] * d2r;
    final lng2 = end[0] * d2r;
    final lat3 = p.lat * d2r;
    final lng3 = p.lng * d2r;

    final cosLat = math.cos((lat1 + lat2) / 2);
    final x2 = (lng2 - lng1) * cosLat;
    final y2 = lat2 - lat1;
    final x3 = (lng3 - lng1) * cosLat;
    final y3 = lat3 - lat1;

    final l2 = x2 * x2 + y2 * y2;
    if (l2 == 0) return double.infinity;

    final t = (x3 * x2 + y3 * y2) / l2;
    if (t < 0 || t > 1) return double.infinity;

    final projX = t * x2;
    final projY = t * y2;
    final dx = x3 - projX;
    final dy = y3 - projY;

    return math.sqrt(dx * dx + dy * dy) * R;
  }

  // Green -> Yellow -> Orange -> Red gradient based on roughness 0-10
  Color _getColorFromRoughness(double roughness) {
    final clamped = roughness.clamp(0.0, 10.0);
    int r, g;
    if (clamped <= 5) {
      g = 255;
      r = ((clamped / 5) * 255).round();
    } else {
      r = 255;
      g = ((1 - ((clamped - 5) / 5)) * 255).round();
    }
    return Color.fromARGB(255, r, g, 0);
  }

  Future<void> _drawRouteLine(List<geo.Position> points, Color fallbackColor) async {
     if (polylineAnnotationManager == null) return;
     
     // Clear existing route lines
     for (var line in _routeLines) {
       if (line != null) await polylineAnnotationManager!.delete(line);
     }
     _routeLines.clear();

     if (points.length < 2) return;

     // Convert route points to [lng, lat] coordinate pairs
     final routeCoords = points.map((p) => [p.longitude, p.latitude]).toList();

     // Prepare recorded points with adjusted roughness
     final adjustedPoints = _recordedPoints.map((p) {
       double speedFactor = 1.0;
       if (p.speed > 20) speedFactor = 20 / p.speed;
       double speedMultiplier = 1.0 + ((_speedInfluenceMultiplier - 1.0) * (1.0 - speedFactor));
       double adjusted = p.roughness * _sensitivityMultiplier * speedMultiplier;
       return _AdjustedPoint(p, adjusted);
     }).toList();

     // Build sub-segments with color data
     List<_RouteSubSegment> subSegments = [];

     for (int i = 0; i < routeCoords.length - 1; i++) {
       final start = routeCoords[i];
       final end = routeCoords[i + 1];
       final segmentLength = _getDistance(start[1], start[0], end[1], end[0]);

       double chunkSize = 5.0; // meters
       // Optimization for long distances
       if (segmentLength > 5000) chunkSize = 200;
       else if (segmentLength > 1000) chunkSize = 50;
       else if (segmentLength > 200) chunkSize = 15;

       final numSplits = math.max(1, (segmentLength / chunkSize).ceil());

       for (int k = 0; k < numSplits; k++) {
         final ratioStart = k / numSplits;
         final ratioEnd = (k + 1) / numSplits;

         final subStart = [
           start[0] + (end[0] - start[0]) * ratioStart,
           start[1] + (end[1] - start[1]) * ratioStart
         ];
         final subEnd = [
           start[0] + (end[0] - start[0]) * ratioEnd,
           start[1] + (end[1] - start[1]) * ratioEnd
         ];

         final midLng = (subStart[0] + subEnd[0]) / 2;
         final midLat = (subStart[1] + subEnd[1]) / 2;

         // Find nearby recorded points and calculate weighted average roughness
         double sumRoughness = 0;
         double totalWeight = 0;

         for (var ap in adjustedPoints) {
           // Fast bounding box pre-filter (~20m)
           if ((ap.point.lat - midLat).abs() > 0.0002 || (ap.point.lng - midLng).abs() > 0.0002) continue;

           final dist = _getPerpendicularDist(ap.point, subStart, subEnd);
           final maxDist = math.max(10.0, chunkSize / 2);

           if (dist <= maxDist) {
             double weight = 1 / (dist + 1);
             sumRoughness += ap.adjustedRoughness * weight;
             totalWeight += weight;
           }
         }

         Color? segColor;
         if (totalWeight > 0) {
           segColor = _getColorFromRoughness(sumRoughness / totalWeight);
         }

         subSegments.add(_RouteSubSegment(subStart, subEnd, segColor));
       }
     }

     // Second pass: fill null-colored gaps by interpolating from neighbors
     const maxGapFill = 20;
     for (int i = 0; i < subSegments.length; i++) {
       if (subSegments[i].color != null) continue;

       Color? prevColor;
       Color? nextColor;
       int gapToPrev = 0;
       int gapToNext = 0;

       for (int j = i - 1; j >= 0; j--) {
         gapToPrev++;
         if (subSegments[j].color != null) { prevColor = subSegments[j].color; break; }
       }
       for (int j = i + 1; j < subSegments.length; j++) {
         gapToNext++;
         if (subSegments[j].color != null) { nextColor = subSegments[j].color; break; }
       }

       if (gapToPrev <= maxGapFill && gapToNext <= maxGapFill && prevColor != null && nextColor != null) {
         final totalGap = gapToPrev + gapToNext;
         final ratio = gapToPrev / totalGap;
         final r = (prevColor.red + (nextColor.red - prevColor.red) * ratio).round();
         final g = (prevColor.green + (nextColor.green - prevColor.green) * ratio).round();
         subSegments[i].color = Color.fromARGB(255, r, g, 0);
       } else if (gapToPrev <= maxGapFill && prevColor != null) {
         subSegments[i].color = prevColor;
       } else if (gapToNext <= maxGapFill && nextColor != null) {
         subSegments[i].color = nextColor;
       } else {
         subSegments[i].color = fallbackColor; // Default blue for unrecorded areas
       }
     }

     // Merge consecutive segments with the same color into longer polylines to reduce annotation count
     List<PolylineAnnotationOptions> optionsList = [];
     int segIdx = 0;
     while (segIdx < subSegments.length) {
       final currentColor = subSegments[segIdx].color!;
       List<Position> mergedCoords = [Position(subSegments[segIdx].start[0], subSegments[segIdx].start[1])];
       
       while (segIdx < subSegments.length && subSegments[segIdx].color == currentColor) {
         mergedCoords.add(Position(subSegments[segIdx].end[0], subSegments[segIdx].end[1]));
         segIdx++;
       }

       var hexColor = currentColor.value.toRadixString(16).padLeft(8, '0').substring(2);
       optionsList.add(PolylineAnnotationOptions(
         geometry: LineString(coordinates: mergedCoords),
         lineColor: int.parse('FF$hexColor', radix: 16),
         lineWidth: 5.0,
       ));
     }

     // Batch create all polyline annotations
     _routeLines = await polylineAnnotationManager!.createMulti(optionsList);
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
                setState(() {
                   _isCentered = false;
                   if (_isDrivingMode) {
                      //_isDrivingMode = false; // Breaking out of driving lock
                      //_updateLocationPuck();
                   }
                });
              }
            },

            onZoomListener: (zoomInfo) {
              if(_currentPos!=null){
                _updateUserLocation(_currentPos!);
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
                  child: (_hasRoute || _destinationName != null)
                      ? GestureDetector(
                          onTap: _cancelRoute,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.close, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Cancel Route',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                )
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
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
            bottom: _hasRoute ? 250 : 150,
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
          
          // Route Actions Panel
          if (_showRouteActions && _destination != null)
            Positioned(
               bottom: 130,
               left: 20,
               right: 20,
               child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  child: Row(
                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                     children: [
                        if (!_hasRoute)
                          ElevatedButton.icon(
                             onPressed: () {
                                if (_destination != null) {
                                   _fetchRouteToDestination(_destination!.latitude, _destination!.longitude);
                                }
                             },
                             icon: const Icon(Icons.map),
                             label: const Text('Show Route'),
                             style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                             ),
                          ),
                        if (_hasRoute)
                          ElevatedButton.icon(
                             onPressed: () {
                                setState(() {
                                   _showRouteActions = false;
                                   _isDrivingMode = true;
                                   _isCentered = true;
                                });
                                _updateLocationPuck();
                                _centerOnUser();
                             },
                             icon: const Icon(Icons.navigation),
                             label: const Text('Start Drive'),
                             style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                             ),
                          ),
                     ],
                  ),
               ),
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

// Helper classes for colored route algorithm
class _AdjustedPoint {
  final PointData point;
  final double adjustedRoughness;
  _AdjustedPoint(this.point, this.adjustedRoughness);
}

class _RouteSubSegment {
  final List<double> start;
  final List<double> end;
  Color? color;
  _RouteSubSegment(this.start, this.end, this.color);
}
