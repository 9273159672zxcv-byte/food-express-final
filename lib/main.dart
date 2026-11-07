import 'dart:io';
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
  String _resultText = 'Выберите Excel-файл для загрузки';

  Future<void> _pickAndUploadFile() async {
    // Временная заглушка, так как мы убрали file_picker
    // Здесь будет стандартный выбор файла, если понадобится
    setState(() {
      _resultText = 'Выбор файла пока недоступен. Нажмите для теста сети.';
    });
    
    // ТЕСТ СЕТИ: Отправляем пустой запрос на сервер, чтобы проверить связь
    setState(() {
      _isLoading = true;
      _resultText = 'Проверка связи с сервером...';
    });

    try {
      var uri = Uri.parse('http://95.163.230.180:8081/upload');
      var request = http.MultipartRequest('POST', uri);
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      setState(() {
        _isLoading = false;
        _resultText = 'Сервер ответил: ${response.statusCode}\n${response.body}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _resultText = 'Ошибка сети: $e';
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
              Text(_resultText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isLoading ? null : _pickAndUploadFile,
                child: const Text('ПРОВЕРИТЬ СВЯЗЬ С СЕРВЕРОМ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
