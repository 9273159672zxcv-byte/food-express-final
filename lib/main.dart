import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const platform = MethodChannel('com.example.food_express_route/file');

  Future<void> _pickAndUploadFile() async {
    try {
      // Вызов нативного выбора файла
      final String? filePath = await platform.invokeMethod('pickFile');
      
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
        _resultText = 'Отправка файла на сервер...';
      });

      File file = File(filePath);
      var uri = Uri.parse('http://95.163.230.180:8081/upload');
      var request = http.MultipartRequest('POST', uri);
      
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      setState(() {
        _isLoading = false;
        if (response.statusCode == 200) {
          _resultText = 'Успех! Сервер ответил:\n${response.body}';
        } else {
          _resultText = 'Ошибка сервера: ${response.statusCode}\n${response.body}';
        }
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
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickAndUploadFile,
                icon: const Icon(Icons.file_upload),
                label: const Text('ВЫБРАТЬ ФАЙЛ EXCEL'),
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
