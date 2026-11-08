import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';

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
  List<LatLng> _markers = [];
  static const platform = MethodChannel('com.example.food_express_route/file');

  Future<void> _pickAndUploadFile() async {
    // 1. Запрашиваем разрешение на геолокацию
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _resultText = 'Вы не разрешили доступ к геолокации';
        });
        return;
      }
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
        List<LatLng> points = [];
        List<LatLng> markerPoints = [];
        
        for (var coord in data['route']) {
          points.add(LatLng(coord[1], coord[0])); 
        }

        if (data['points'] != null) {
          for (var p in data['points']) {
            var parts = p.split(',');
            markerPoints.add(LatLng(double.parse(parts[1]), double.parse(parts[0])));
          }
        }

        setState(() {
          _isLoading = false;
          _resultText = 'Маршрут построен! Точек: ${markerPoints.length}';
          _routePoints = points;
          _markers = markerPoints;
        });
      } else {
        setState(() {
          _isLoading = false;
          _resultText = 'Ошибка: ${response.statusCode}';
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE53935),
        title: const Text('Фуд-Экспресс'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(54.7388, 55.9721),
                initialZoom: 12.0,
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
                      strokeWidth: 5.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: _markers.asMap().entries.map((entry) {
                    int index = entry.key;
                    LatLng point = entry.value;
                    return Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const CurrentLocationLayer(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text(_resultText, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _pickAndUploadFile,
                  child: const Text('ВЫБРАТЬ ФАЙЛ EXCEL'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
