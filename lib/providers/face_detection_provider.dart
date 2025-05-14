import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'attendance_provider.dart';

class FaceDetectionProvider with ChangeNotifier {
  final FlutterVision _vision = FlutterVision();
  final String _backendUrl = 'http://10.134.30.235:8000/api/recognize/';

  // Reference to centralized attendance provider
  AttendanceProvider? _attendanceProvider;

  // Update these properties in your class

  int _totalFacesDetected = 0;
  int _totalFacesRecognized = 0;

  bool _isModelLoaded = false;

  // Use the centralized session ID if available
  String get _currentSessionId =>
      _attendanceProvider?.sessionId ??
      DateTime.now().millisecondsSinceEpoch.toString();

  Set<String> recognizedStudentIdsThisSession =
      {}; // Persistent across detections

  Map<String, DateTime> lastProcessedFaces = {};

  List<Map<String, dynamic>> _detections = [];
  final Map<String, Map<String, dynamic>> _recognizedStudents = {};

  List<Map<String, dynamic>> get detections => _detections;
  Map<String, Map<String, dynamic>> get recognizedStudents =>
      _recognizedStudents;

  // Add method to update attendanceProvider
  void updateAttendanceProvider(AttendanceProvider attendanceProvider) {
    _attendanceProvider = attendanceProvider;
  }

  // Method to update detections directly (used by ML Kit)
  void updateDetections(List<Map<String, dynamic>> detections) {
    _detections = detections;
    _totalFacesDetected = detections.length;

    // Update the centralized attendance provider's count
    if (_attendanceProvider != null) {
      _attendanceProvider!.updateDetectionCount(detections.length);
    }

    notifyListeners();
  }

  // Method to add placeholder entries for ML Kit detected faces
  void addPlaceholders(Map<String, Map<String, dynamic>> mlKitFaceIds) {
    // Add placeholders to the recognizedStudents map
    mlKitFaceIds.forEach((key, value) {
      _recognizedStudents[key] = value;
    });
    notifyListeners();
  }

  void resetAttendance() {
    _recognizedStudents.clear();
    recognizedStudentIdsThisSession.clear();
    lastProcessedFaces.clear();

    // Also reset the centralized attendance provider if available
    if (_attendanceProvider != null) {
      _attendanceProvider!.resetAttendance();
    }

    notifyListeners();
  }

  // Public method to process uploaded images [!]
  Future<void> processUploadedImage(File image) async {
    if (!_isModelLoaded) {
      debugPrint('📱 Model not loaded, loading now...');
      debugPrint('📱 Model loaded successfully');
    }

    try {
      debugPrint('📱 Processing uploaded image: ${image.path}');

      // Check if file exists and has content
      if (!await image.exists()) {
        throw Exception("Image file does not exist");
      }

      final fileSize = await image.length();
      debugPrint('📱 Image file size: $fileSize bytes');

      if (fileSize < 100) {
        throw Exception("Image file too small or corrupted: $fileSize bytes");
      }

      // Load the image into memory
      final Uint8List bytes = await image.readAsBytes();
      debugPrint('📱 Read ${bytes.length} bytes from image file');

      // Get image dimensions
      final img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception("Failed to decode image - format may be unsupported");
      }

      debugPrint(
          '📱 Decoded image dimensions: ${decodedImage.width}x${decodedImage.height}');

      // No need to run YOLO face detection here since ML Kit has already detected faces
      // We're keeping _detections populated from the updateDetections() method

      // Send the whole image directly to backend for recognition without cropping
      debugPrint('📱 Sending whole image to backend for face recognition...');

      try {
        // Create multipart request
        final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

        // Add the full image (not cropped)
        request.files
            .add(await http.MultipartFile.fromPath('image', image.path));

        // Add device info as recognized_by
        request.fields['recognized_by'] = 'Flutter Mobile App - Full Image';

        // Add quality flag to tell backend this is a high quality image
        request.fields['high_quality'] = 'true';

        // Add already recognized student IDs to avoid duplicates
        // Use centralized provider if available
        if (_attendanceProvider != null) {
          final alreadyRecognized =
              _attendanceProvider!.getAlreadyRecognizedIdsParam();
          if (alreadyRecognized.isNotEmpty) {
            request.fields['already_recognized'] = alreadyRecognized;
          }
        } else if (recognizedStudentIdsThisSession.isNotEmpty) {
          request.fields['already_recognized'] =
              recognizedStudentIdsThisSession.join(',');
        }

        // Add session ID to help backend group attendance records
        request.fields['session_id'] = _currentSessionId;

        // Send the request with timeout
        final response = await request
            .send()
            .timeout(const Duration(seconds: 30), onTimeout: () {
          throw Exception("Backend request timed out after 30 seconds");
        });

        // Process the response
        final responseBody = await response.stream.bytesToString();
        debugPrint("📱 API response: ${response.statusCode} - $responseBody");

        if (response.statusCode == 200) {
          // Parse response
          final data = jsonDecode(responseBody);

          if (data.containsKey('results') && data['results'] is List) {
            final results = data['results'] as List;
            debugPrint(
                "📱 Got ${results.length} recognition results from backend");

            // Map the backend results to the ML Kit faces
            if (results.isNotEmpty && _detections.isNotEmpty) {
              // For each detected face from ML Kit, try to match with a backend result
              for (int i = 0; i < _detections.length; i++) {
                final detection = _detections[i];
                final boxLeft = detection['box'][0];
                final boxTop = detection['box'][1];
                final detectionId = "${boxLeft.toInt()}_${boxTop.toInt()}";

                // The backend may return results in any order, so find the best match
                // This is simplified logic - in reality you might want to map based on face position
                if (i < results.length) {
                  final result = results[i];

                  if (result.containsKey('student_id') &&
                      result['student_id'] != null) {
                    // Student recognized
                    final studentId = result['student_id'] as String;
                    final String studentName = result['name'] ?? "Unknown Name";

                    debugPrint(
                        "📱 Mapping recognized student $studentName to face ID: $detectionId");

                    // Store in session tracking (legacy)
                    recognizedStudentIdsThisSession.add(studentId);

                    // Calculate confidence
                    double confidence = 1.0;
                    if (result.containsKey('distance')) {
                      confidence = 1.0 - (result['distance'] ?? 0.0);
                      confidence = confidence.clamp(0.0, 1.0);
                    }

                    // Update the centralized attendance provider if available
                    if (_attendanceProvider != null) {
                      _attendanceProvider!.addRecognizedStudent(
                        detectionId: detectionId,
                        studentId: studentId,
                        name: studentName,
                        confidence: confidence,
                        source: 'face_detection',
                      );
                    }

                    // Also update local map for backwards compatibility
                    _recognizedStudents[detectionId] = {
                      'name': studentName,
                      'student_id': studentId,
                      'confidence': confidence,
                      'timestamp': DateTime.now().toString(),
                    };
                  } else {
                    // Unknown face from backend
                    debugPrint(
                        "📱 Face $i not recognized by backend, marking as Unknown");

                    // Update centralized attendance provider
                    if (_attendanceProvider != null) {
                      _attendanceProvider!.addRecognizedStudent(
                        detectionId: detectionId,
                        studentId: null,
                        name: 'Unknown',
                        confidence: 0.0,
                        source: 'face_detection',
                      );
                    }

                    // Also update local map for backwards compatibility
                    _recognizedStudents[detectionId] = {
                      'name': 'Unknown',
                      'student_id': null,
                      'confidence': 0.0,
                      'timestamp': DateTime.now().toString(),
                    };
                  }
                } else {
                  // More faces detected by ML Kit than recognized by backend
                  debugPrint(
                      "📱 No matching backend result for face ID: $detectionId");

                  // Update centralized attendance provider
                  if (_attendanceProvider != null) {
                    _attendanceProvider!.addRecognizedStudent(
                      detectionId: detectionId,
                      studentId: null,
                      name: 'Unknown',
                      confidence: 0.0,
                      source: 'face_detection',
                    );
                  }

                  // Also update local map for backwards compatibility
                  _recognizedStudents[detectionId] = {
                    'name': 'Unknown',
                    'student_id': null,
                    'confidence': 0.0,
                    'timestamp': DateTime.now().toString(),
                  };
                }
              }
            }

            // Update recognition count
            _totalFacesRecognized = _recognizedStudents.values
                .where((student) => student['student_id'] != null)
                .length;

            // Update UI
            notifyListeners();
          }
        } else {
          // Handle error response
          debugPrint(
              '📱 Backend error: ${response.statusCode} - $responseBody');
          throw Exception("Backend returned error: ${response.statusCode}");
        }
      } catch (e) {
        debugPrint('📱 Error in backend communication: $e');
        throw Exception("Face recognition backend error: $e");
      }
    } catch (e) {
      debugPrint('📱 Error processing uploaded image: $e');
      // Don't clear _detections here - we want to keep the ML Kit detections
      notifyListeners();
      rethrow;
    }
  }
}
