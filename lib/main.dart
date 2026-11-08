import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Фуд-Экспресс',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isLoading = false;
  String _resultText = 'Выберите Excel-файл';
  
  List<LatLng> _routePoints = []; 
  List<LatLng> _allMarkers = []; 
  int _currentTargetIndex = 0; 
  
  LatLng? _currentPosition;
  double _heading = 0.0; 
  
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<CompassEvent>? _compassStreamSubscription;
  static const platform = MethodChannel('com.example.food_express_route/file');
  
  final String _mapboxToken = 'pk.eyJ1IjoicmFpbDc3NyIsImEiOiJjbXc0eTdvY3owMmwxMnlxd3NqdDNqYXFhIn0.QSlooIUtFVn94FW-odWkZQ';

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    _startCompass();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _compassStreamSubscription?.cancel();
    super.dispose();
  }

  void _startCompass() {
    _compassStreamSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null && mounted) {
        setState(() {
          _heading = event.heading!;
        });
        // Встроенный поворот карты (чтобы дорога всегда была впереди)
        _mapController.rotate(-_heading);
      }
    });
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _resultText = 'Включите GPS на телефоне');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _resultText = 'Нет доступа к геолокации');
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
        _mapController.move(_currentPosition!, 16.0);
      }
    } catch (e) {}

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
        _checkArrival();
        _mapController.move(_currentPosition!, _mapController.camera.zoom);
      }
    });
  }

  void _checkArrival() {
    if (_currentPosition == null || _allMarkers.isEmpty || _currentTargetIndex >= _allMarkers.length) return;

    final targetPoint = _allMarkers[_currentTargetIndex];
    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude,
      targetPoint.latitude, targetPoint.longitude,
    );

    if (distance < 50) {
      _completeCurrentPoint();
    }
  }

  void _completeCurrentPoint() {
    if (_currentTargetIndex < _allMarkers.length - 1) {
      setState(() {
        _currentTargetIndex++;
        _updateRouteForCurrentTarget();
      });
    } else {
      setState(() {
        _resultText = 'Вы посетили все точки! Маршрут завершен.';
        _allMarkers.clear();
        _routePoints.clear();
      });
    }
  }

  Future<void> _updateRouteForCurrentTarget() async {
    if (_currentPosition == null || _currentTargetIndex >= _allMarkers.length) return;

    final target = _allMarkers[_currentTargetIndex];
    final start = _currentPosition!;

    setState(() => _resultText = 'Строим маршрут до точки ${_currentTargetIndex + 1}...');

    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${start.longitude},${start.latitude};${target.longitude},${target.latitude}?geometries=geojson&access_token=$_mapboxToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry']['coordinates'] as List;
          List<LatLng> roadPoints = geometry.map((c) => LatLng(c[1], c[0])).toList();
          
          setState(() {
            _routePoints = roadPoints; 
            _resultText = 'Едем к точке ${_currentTargetIndex + 1}';
          });
          
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints([start, target]),
              padding: const EdgeInsets.all(50),
            ),
          );
          return;
        }
      }
    } catch (e) {}

    setState(() {
      _routePoints = [start, target];
      _resultText = 'Едем к точке ${_currentTargetIndex + 1} (по прямой)';
    });
  }

  Future<void> _pickAndUploadFile() async {
    if (_currentPosition == null) {
      setState(() => _resultText = 'Ждем сигнал GPS...');
      return;
    }

    try {
      final String? filePath = await platform.invokeMethod('pickFile');
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
        _resultText = 'Построение маршрута...';
      });

      File file = File(filePath);
      var uri = Uri.parse('http://95.163.230.180:8081/upload');
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        List<LatLng> markerPoints = [];

        if (data['points'] != null) {
          for (var p in data['points']) {
            var parts = p.split(',');
            markerPoints.add(LatLng(double.parse(parts[1]), double.parse(parts[0])));
          }
        }

        setState(() {
          _isLoading = false;
          _allMarkers = markerPoints;
          _currentTargetIndex = 0; 
        });

        if (markerPoints.isNotEmpty) {
           await _updateRouteForCurrentTarget();
        }
      } else {
        setState(() {
          _isLoading = false;
          _resultText = 'Ошибка сервера: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultText = 'Ошибка: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    List<LatLng> visibleMarkers = _allMarkers.sublist(_currentTargetIndex);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: const Color(0xFFE53935),
        title: const Text('Фуд-Экспресс'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition ?? const LatLng(54.7388, 55.9721),
                  initialZoom: 16.0,
                  // Разрешаем вращение карты (оно управляется компасом)
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.food_express_route',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: visibleMarkers.asMap().entries.map((entry) {
                      int originalIndex = entry.key + _currentTargetIndex;
                      LatLng point = entry.value;
                      return Marker(
                        point: point,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${originalIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_currentPosition != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition!,
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 5,
                                )
                              ]
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: Column(
                children: [
                  Text(_resultText, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 50),
                          ),
                          onPressed: _isLoading ? null : _pickAndUploadFile,
                          child: const Text('ВЫБРАТЬ EXCEL', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                      if (_allMarkers.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 50),
                            ),
                            onPressed: _completeCurrentPoint,
                            child: const Text('Я НА МЕСТЕ', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          backgroundColor: Colors.blue,
          child: const Icon(Icons.my_location, color: Colors.white),
          onPressed: () {
            if (_currentPosition != null) {
              _mapController.move(_currentPosition!, 16.0);
            } else {
              _startLocationTracking();
            }
          },
        ),
      ),
    );
  }
}
