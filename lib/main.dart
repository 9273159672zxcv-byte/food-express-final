import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  static const platform = MethodChannel('com.example.food_express_route/file');

  Future<void> _pickAndUploadFile() async {
    try {
      final String? filePath = await platform.invokeMethod('pickFile');
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
        _resultText = 'Отправка...';
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
        
        for (var item in data['optimized_order']) {
          points.add(LatLng(item['lat'], item['lng']));
        }

        setState(() {
          _isLoading = false;
          _resultText = 'Маршрут построен!';
          _routePoints = points;
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
              options: MapOptions(
                initialCenter: LatLng(54.7388, 55.9721), // Уфа
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
                      strokeWidth: 4.0,
                      color: Colors.red,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: _routePoints.map((point) => Marker(
                    point: point,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.red),
                  )).toList(),
                ),
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
