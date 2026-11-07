import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  String _resultText = 'Введите имя файла и нажмите кнопку';
  final TextEditingController _controller = TextEditingController(text: 'test.xlsx');

  Future<void> _buildRoute() async {
    setState(() {
      _isLoading = true;
      _resultText = 'Запрос маршрута...';
    });

    try {
      var uri = Uri.parse('http://95.163.230.180:8081/upload');
      var request = http.MultipartRequest('POST', uri);
      
      // Отправляем имя файла, который лежит на сервере
      request.fields['filename'] = _controller.text;

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      setState(() {
        _isLoading = false;
        _resultText = 'Ответ: ${response.statusCode}\n${response.body}';
      });
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE53935),
        title: const Text('Фуд-Экспресс', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) const CircularProgressIndicator() else const Icon(Icons.local_shipping, size: 80, color: Color(0xFFE53935)),
              const SizedBox(height: 30),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Имя файла на сервере',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(_resultText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _buildRoute,
                icon: const Icon(Icons.route),
                label: const Text('ПОСТРОИТЬ МАРШРУТ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
