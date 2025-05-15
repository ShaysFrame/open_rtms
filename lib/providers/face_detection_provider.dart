import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:open_rtms/core/config/app_config.dart';
import 'attendance_provider.dart';

class FaceDetectionProvider with ChangeNotifier {
  final FlutterVision _vision = FlutterVision();
  final String _backendUrl = 'http://${AppConfig.serverIp}:8000/api/recognize/';

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
  // Add getters for detection and recognition counts
  int get totalFacesDetected => _totalFacesDetected;
  int get totalFacesRecognized => _totalFacesRecognized;

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
  } // Method to add placeholder entries for ML Kit detected faces

  // This is kept for backward compatibility but now it just clears
  // the recognition data and waits for actual backend results
  void addPlaceholders(Map<String, Map<String, dynamic>> mlKitFaceIds) {
    // Clear all existing entries - we'll only use what the backend returns
    _recognizedStudents.clear();
    _totalFacesRecognized = 0;

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

  // Helper method to process a recognized face
  void _processRecognizedFace(String detectionId, String studentId,
      String studentName, double confidence) {
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
  }

  // Helper method for marking unknown faces
  // DEPRECATED: This method is no longer used as we want to leave unknown faces unlabeled
  // Keeping it for reference in case we need to revert the behavior
  void _markFaceAsUnknown(String detectionId) {
    // Update centralized attendance provider if available
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

          // Get summary info if available
          int newlyMarked = 0;
          int alreadyMarked = 0;
          if (data.containsKey('summary')) {
            final summary = data['summary'];
            newlyMarked = summary['newly_marked'] ?? 0;
            alreadyMarked = summary['already_marked'] ?? 0;
            debugPrint(
                "📱 Recognition summary: newly marked: $newlyMarked, already marked: $alreadyMarked");
          }

          if (data.containsKey('results') && data['results'] is List) {
            final results = data['results'] as List;
            debugPrint(
                "📱 Got ${results.length} recognition results from backend");

            // Clear ALL entries - we'll only add entries for faces recognized by the backend
            _recognizedStudents.clear();

            // First create a list of valid student results (no nulls)
            // Exclude students marked as 'already_marked' from the UI to avoid duplicates
            final validResults = results
                .where((result) =>
                    result.containsKey('student_id') &&
                    result['student_id'] != null &&
                    (result['status'] != 'already_marked'))
                .toList();

            debugPrint(
                "📱 Found ${validResults.length} valid student results to display");

            // Process only these valid backend results - exactly the number returned!
            for (final result in validResults) {
              final String studentId = result['student_id'];
              final String studentName = result['name'] ?? "Unknown";

              // Always add to the tracking set even if already marked
              recognizedStudentIdsThisSession.add(studentId);

              // Calculate confidence
              double confidence = 1.0;
              if (result.containsKey('distance')) {
                confidence = 1.0 - (result['distance'] ?? 0.0);
                confidence = confidence.clamp(0.0, 1.0);
              }

              // Try to find the best matching face detection
              // based on position if available
              String? bestMatchDetectionId;
              int closestDistance = 1000000; // Large number to start

              if (result.containsKey('face_location') &&
                  _detections.isNotEmpty) {
                final faceLocation = result['face_location'];
                final int backendX = faceLocation['x'];
                final int backendY = faceLocation['y'];

                // Find the closest detected face to this backend result
                for (final detection in _detections) {
                  final boxLeft = detection['box'][0];
                  final boxTop = detection['box'][1];
                  final detectedX = boxLeft.toInt();
                  final detectedY = boxTop.toInt();

                  final int xDiff = (detectedX - backendX).abs();
                  final int yDiff = (detectedY - backendY).abs();
                  final int distance = xDiff + yDiff;

                  if (distance < closestDistance && distance < 100) {
                    // Use threshold of 100
                    closestDistance = distance;
                    bestMatchDetectionId = "${detectedX}_${detectedY}";
                  }
                }

                if (bestMatchDetectionId != null) {
                  debugPrint(
                      "📱 Matched student $studentName to detection ID: $bestMatchDetectionId");
                  _processRecognizedFace(
                      bestMatchDetectionId, studentId, studentName, confidence);
                  // ID is already tracked in validResults filtered list and _processRecognizedFace
                } else {
                  debugPrint(
                      "📱 Could not find a matching detection for student $studentName");
                  // If no matching detection found, create a synthetic ID based on backend coords
                  final syntheticId = "${backendX}_${backendY}";
                  _processRecognizedFace(
                      syntheticId, studentId, studentName, confidence);
                  // ID is already tracked in validResults filtered list and _processRecognizedFace
                }
              } else {
                // If no face location in backend result, use index-based matching as fallback
                // but only if we have detections
                if (_detections.isNotEmpty &&
                    validResults.indexOf(result) < _detections.length) {
                  final detection = _detections[validResults.indexOf(result)];
                  final boxLeft = detection['box'][0];
                  final boxTop = detection['box'][1];
                  final detectionId = "${boxLeft.toInt()}_${boxTop.toInt()}";

                  debugPrint(
                      "📱 Using index-based matching for student $studentName");
                  _processRecognizedFace(
                      detectionId, studentId, studentName, confidence);
                  // ID is already tracked in validResults filtered list and _processRecognizedFace
                } else {
                  // If all else fails, create a synthetic ID
                  final syntheticId =
                      "synthetic_${validResults.indexOf(result)}";
                  debugPrint(
                      "📱 Using synthetic ID for student $studentName: $syntheticId");
                  _processRecognizedFace(
                      syntheticId, studentId, studentName, confidence);
                  // ID is already tracked in validResults filtered list and _processRecognizedFace
                }
              }
            }

            // Set total recognized to exactly the number from the backend
            _totalFacesRecognized = _recognizedStudents.length;

            debugPrint(
                "📱 Recognition summary: Found ${_detections.length} faces, recognized ${_totalFacesRecognized} students");
            // Debug: print recognized students
            for (final entry in _recognizedStudents.entries) {
              debugPrint(
                  "📱 Recognized: ${entry.value['name']} (ID: ${entry.value['student_id']})");
            }

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
