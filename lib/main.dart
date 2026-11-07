child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    if (_isLoading) 
      const CircularProgressIndicator() 
    else 
      const Icon(Icons.local_shipping, size: 80, color: Color(0xFFE53935)),
    const SizedBox(height: 20),
    
    // Вот здесь мы добавили прокрутку для текста
    Expanded(
      child: SingleChildScrollView(
        child: Text(
          _resultText, 
          textAlign: TextAlign.center, 
          style: const TextStyle(fontSize: 14),
        ),
      ),
    ),
    
    const SizedBox(height: 20),
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
