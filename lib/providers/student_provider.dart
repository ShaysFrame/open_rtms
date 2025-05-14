import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class StudentProvider with ChangeNotifier {
  File? _currentImage;

  File? get currentImage => _currentImage;
  final String _backendUrl = 'http://10.134.30.235:8000/api/register/';

  Future<void> setCurrentImage(dynamic image) async {
    if (image is String) {
      _currentImage = File(image);
    } else if (image?.path != null) {
      _currentImage = File(image.path);
    }
    notifyListeners();
  }

  Future<void> registerStudent({
    required String name,
    required String id,
  }) async {
    if (_currentImage == null) {
      throw Exception('No image selected');
    }

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      request.fields['name'] = name;
      request.fields['student_id'] = id;
      request.files.add(await http.MultipartFile.fromPath(
        'photo',
        _currentImage!.path,
      ));

      final response = await request.send();

      if (response.statusCode != 200 && response.statusCode != 201) {
        final responseBody = await response.stream.bytesToString();
        throw Exception(
            'Server returned ${response.statusCode}: $responseBody');
      }

      // Reset current image after successful registration
      _currentImage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error registering student: $e');
      rethrow;
    }
  }
}
