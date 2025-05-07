import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

class FaceDetectionProvider with ChangeNotifier {
  final String _backendUrl = 'http://10.134.13.24:8000/api/process-classroom/';

  // State management
  bool _isProcessing = false;
  int _totalFacesDetected = 0;
  int _totalRecognizedStudents = 0;
  Timer? _processingTimer;
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  // Recognized data
  final Set<String> _recognizedStudentIds = {};
  final Map<String, Map<String, dynamic>> _recognizedStudents = {};

  // Bounding boxes to show on UI
  final List<Map<String, dynamic>> _faceBoxes = [];

  // Getters
  int get totalFacesDetected => _totalFacesDetected;
  int get totalRecognizedStudents => _totalRecognizedStudents;
  Map<String, Map<String, dynamic>> get recognizedStudents =>
      _recognizedStudents;
  List<Map<String, dynamic>> get faceBoxes => _faceBoxes;

  // Start processing camera frames
  void startProcessing(CameraController controller) {
    // Cancel any existing timer
    _processingTimer?.cancel();

    // Create a timer that processes frames every 2 seconds
    _processingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      processCameraFrame(controller);
    });
  }

  // Stop processing
  void stopProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  // Process a single camera frame
  Future<void> processCameraFrame(CameraController controller) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Take a snapshot from the camera
      final XFile imageFile = await controller.takePicture();

      // Send it to the backend
      await sendImageToBackend(File(imageFile.path));
    } catch (e) {
      debugPrint('Error capturing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Send image to backend
  // Update your sendImageToBackend method
  Future<void> sendImageToBackend(File imageFile) async {
    try {
      print("📱 Sending image to server: ${await imageFile.length()} bytes");
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      // Add the image
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));

      // Add session info
      request.fields['session_id'] = _sessionId;
      request.fields['recognized_by'] = 'Mobile App';

      // Include already recognized students
      if (_recognizedStudentIds.isNotEmpty) {
        request.fields['already_recognized'] = _recognizedStudentIds.join(',');
      }

      // Send the request
      final response = await request.send();
      print("📱 Server response status: ${response.statusCode}");
      final responseBody = await response.stream.bytesToString();
      print("📱 Server response: $responseBody");

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);

        // Update face boxes
        _faceBoxes.clear();
        if (data['face_boxes'] != null) {
          print("📱 Got ${data['face_boxes'].length} face boxes");
          _faceBoxes
              .addAll(List<Map<String, dynamic>>.from(data['face_boxes']));
        }

        // Update total faces
        _totalFacesDetected = _faceBoxes.length;

        // Process recognized students
        if (data['recognized_students'] != null) {
          final results = data['recognized_students'] as List;
          for (final student in results) {
            if (student['student_id'] != null) {
              final studentId = student['student_id'] as String;
              _recognizedStudentIds.add(studentId);

              _recognizedStudents[studentId] = {
                'name': student['name'],
                'student_id': studentId,
                'confidence': student['confidence'] ?? 0.0,
                'timestamp': DateTime.now().toString(),
              };
            }
          }
        }

        // Update recognized count
        _totalRecognizedStudents = _recognizedStudentIds.length;

        // Notify UI to update
        notifyListeners();
      }
    } catch (e) {
      print("📱 Error sending image to backend: $e");
      debugPrint('Error sending image to backend: $e');
    }
  }

  // Reset all recognition data
  void resetAttendance() {
    _recognizedStudentIds.clear();
    _recognizedStudents.clear();
    _faceBoxes.clear();
    _totalFacesDetected = 0;
    _totalRecognizedStudents = 0;
    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    stopProcessing();
    super.dispose();
  }

  // For batch processing (classroom scan)
  Future<void> scanClassroom(CameraController controller) async {
    if (_isProcessing) return;
    _isProcessing = true;
    notifyListeners();

    try {
      // Take a high-resolution photo
      final XFile photo = await controller.takePicture();

      // Send it for processing
      await sendImageToBackend(File(photo.path));
    } catch (e) {
      debugPrint('Error in classroom scan: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
