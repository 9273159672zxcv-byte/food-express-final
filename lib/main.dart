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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Навигатор курьера',
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
  
  double _totalDistanceKm = 0.0;
  String _distanceToNextTurn = '';
  IconData _turnIcon = Icons.straight;
  
  List<LatLng> _routePoints = []; 
  List<LatLng> _allMarkers = []; 
  int _currentTargetIndex = 0; 
  
  LatLng? _currentPosition;
  double _heading = 0.0; 
  bool _isRecalculating = false;
  bool _isPickingOnMap = false;
  
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;
  static const platform = MethodChannel('com.example.food_express_route/file');
  
  final String _mapboxToken = 'pk.eyJ1IjoicmFpbDc3NyIsImEiOiJjbXc0eTdvY3owMmwxMnlxd3NqdDNqYXFhIn0.QSlooIUtFVn94FW-odWkZQ';

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
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

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          if (position.heading >= 0 && position.heading <= 360) {
            _heading = position.heading;
          }
        });
        
        _checkArrival();
        _checkOffRoute();
        _updateTurnHint();
        
        if (_currentPosition != null) {
          _mapController.move(_currentPosition!, _mapController.camera.zoom);
          _mapController.rotate(-_heading);
        }
      }
    });
  }

  void _updateTurnHint() {
    if (_currentPosition == null || _routePoints.isEmpty || _currentTargetIndex >= _allMarkers.length) return;

    LatLng? nextPoint;
    for (int i = 0; i < _routePoints.length; i++) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        _routePoints[i].latitude, _routePoints[i].longitude,
      );
      if (dist > 20) {
        nextPoint = _routePoints[i];
        final distanceToTurn = dist;
        
        final bearingToPoint = Geolocator.bearingBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          nextPoint.latitude, nextPoint.longitude,
        );
        
        double angleDiff = (bearingToPoint - _heading).abs();
        if (angleDiff > 180) angleDiff = 360 - angleDiff;

        setState(() {
          if (distanceToTurn > 50) {
            _distanceToNextTurn = 'Через ${distanceToTurn.toInt()} м';
            if (angleDiff < 30) {
              _turnIcon = Icons.straight;
            } else if (bearingToPoint > _heading) {
              _turnIcon = Icons.turn_right;
            } else {
              _turnIcon = Icons.turn_left;
            }
          } else {
            _distanceToNextTurn = '';
          }
        });
        break;
      }
    }
  }

  void _checkOffRoute() {
    if (_routePoints.isEmpty || _currentPosition == null || _isRecalculating) return;
    if (_currentTargetIndex >= _allMarkers.length) return;

    double minDistance = double.infinity;
    for (var point in _routePoints) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        point.latitude, point.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    if (minDistance > 50) {
      _recalculateRoute();
    }
  }

  Future<void> _recalculateRoute() async {
    if (_currentTargetIndex >= _allMarkers.length || _currentPosition == null) return;
    
    setState(() {
      _isRecalculating = true;
      _resultText = 'Перестраиваем маршрут...';
    });

    await _updateRouteForCurrentTarget();
    
    setState(() {
      _isRecalculating = false;
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
        _distanceToNextTurn = '';
      });
    }
  }

  Future<void> _updateRouteForCurrentTarget() async {
    if (_currentPosition == null || _currentTargetIndex >= _allMarkers.length) return;

    final target = _allMarkers[_currentTargetIndex];
    final start = _currentPosition!;

    setState(() {
      _resultText = 'Строим маршрут до точки ${_currentTargetIndex + 1}...';
      _distanceToNextTurn = '';
    });

    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${start.longitude},${start.latitude};${target.longitude},${target.latitude}?geometries=geojson&access_token=$_mapboxToken';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;
          List<LatLng> roadPoints = geometry.map((c) => LatLng(c[1], c[0])).toList();
          
          final double distanceInMeters = route['distance'];
          _totalDistanceKm += distanceInMeters / 1000;
          
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
      _resultText = 'Нет связи. Едем по старому маршруту.';
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
        _totalDistanceKm = 0.0;
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
          _resultText = 'Ошибка сервера. Проверьте адреса.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultText = 'Ошибка: $e';
      });
    }
  }

  Future<void> _addPointManually() async {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Добавить точку (текст)'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Например: ул. Ленина 5'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final address = controller.text;
                if (address.isNotEmpty) {
                  Navigator.pop(context);
                  await _geocodeAndAddPoint(address);
                }
              },
              child: const Text('Найти'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _geocodeAndAddPoint(String address) async {
    setState(() {
      _isLoading = true;
      _resultText = 'Ищем адрес...';
    });

    final url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json?access_token=$_mapboxToken&limit=1';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final coords = data['features'][0]['geometry']['coordinates'];
          final newPoint = LatLng(coords[1], coords[0]);
          
          setState(() {
            _allMarkers.add(newPoint);
            _isLoading = false;
            _resultText = 'Точка добавлена! Нажмите "Перестроить"';
          });
          
          _mapController.move(newPoint, 16.0);
        } else {
          setState(() {
            _isLoading = false;
            _resultText = 'Адрес не найден на карте.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultText = 'Ошибка при поиске адреса.';
      });
    }
  }

  void _enablePickOnMap() {
    setState(() {
      _isPickingOnMap = true;
      _resultText = 'Ткните пальцем в карту, куда добавить точку';
    });
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (!_isPickingOnMap) return;

    setState(() {
      _isPickingOnMap = false;
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Добавить точку?'),
          content: Text('Координаты: ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _allMarkers.add(point);
                  _resultText = 'Точка добавлена! Нажмите "Перестроить"';
                });
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  void _openReorderScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReorderPointsScreen(
          markers: _allMarkers,
          onSave: (newMarkers) {
            setState(() {
              _allMarkers = newMarkers;
              _currentTargetIndex = 0; 
              _totalDistanceKm = 0.0;
            });
            _updateRouteForCurrentTarget();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<LatLng> visibleMarkers = _allMarkers.sublist(_currentTargetIndex);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: const Color(0xFFE53935),
        toolbarHeight: 55,
        title: const Text(
          'Навигатор курьера', 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
        ),
        actions: [
          if (_allMarkers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: _completeCurrentPoint,
                child: const Text('Я НА МЕСТЕ', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_distanceToNextTurn.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.blue,
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_turnIcon, color: Colors.white, size: 40),
                    const SizedBox(width: 10),
                    Text(
                      _distanceToNextTurn,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition ?? const LatLng(54.7388, 55.9721),
                  initialZoom: 16.0,
                  onTap: _handleMapTap,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_resultText, style: const TextStyle(fontSize: 14)),
                      Text(
                        'Всего: ${_totalDistanceKm.toStringAsFixed(1)} км', 
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 50),
                          ),
                          onPressed: _isLoading ? null : _addPointManually,
                          child: const Text('+ ТЕКСТОМ', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPickingOnMap ? Colors.orange : Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 50),
                          ),
                          onPressed: _isLoading ? null : _enablePickOnMap,
                          child: Text(
                            _isPickingOnMap ? 'ТКНИТЕ...' : 'УКАЗАТЬ НА КАРТЕ',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_allMarkers.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: _openReorderScreen,
                        child: const Text('СПИСОК ТОЧЕК (СОРТИРОВКА)', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: () {
                          setState(() {
                            _currentTargetIndex = 0;
                            _totalDistanceKm = 0.0;
                          });
                          _updateRouteForCurrentTarget();
                        },
                        child: const Text('ПЕРЕСТРОИТЬ (ОПТИМИЗИРОВАТЬ)', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
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

class ReorderPointsScreen extends StatefulWidget {
  final List<LatLng> markers;
  final Function(List<LatLng>) onSave;

  const ReorderPointsScreen({Key? key, required this.markers, required this.onSave}) : super(key: key);

  @override
  State<ReorderPointsScreen> createState() => _ReorderPointsScreenState();
}

class _ReorderPointsScreenState extends State<ReorderPointsScreen> {
  late List<LatLng> _tempMarkers;

  @override
  void initState() {
    super.initState();
    _tempMarkers = List.from(widget.markers);
  }

  void _moveUp(int index) {
    if (index > 0) {
      setState(() {
        final item = _tempMarkers.removeAt(index);
        _tempMarkers.insert(index - 1, item);
      });
    }
  }

  void _moveDown(int index) {
    if (index < _tempMarkers.length - 1) {
      setState(() {
        final item = _tempMarkers.removeAt(index);
        _tempMarkers.insert(index + 1, item);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сортировка точек'),
        backgroundColor: const Color(0xFFE53935),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              widget.onSave(_tempMarkers);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _tempMarkers.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red,
                child: Text('${index + 1}', style: const TextStyle(color: Colors.white)),
              ),
              title: Text(
                'Точка ${index + 1}\n(${_tempMarkers[index].latitude.toStringAsFixed(4)}, ${_tempMarkers[index].longitude.toStringAsFixed(4)})',
                style: const TextStyle(fontSize: 14),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _tempMarkers.removeAt(index);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_upward, color: index == 0 ? Colors.grey : Colors.blue),
                    onPressed: index == 0 ? null : () => _moveUp(index),
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_downward, color: index == _tempMarkers.length - 1 ? Colors.grey : Colors.blue),
                    onPressed: index == _tempMarkers.length - 1 ? null : () => _moveDown(index),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
