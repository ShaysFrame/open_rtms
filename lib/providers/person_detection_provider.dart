import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'attendance_provider.dart';

class PersonDetectionProvider with ChangeNotifier {
  final FlutterVision _vision = FlutterVision();
  final String _backendUrl = 'http://10.134.30.235:8000/api/recognize/';

  // Reference to centralized attendance provider
  AttendanceProvider? _attendanceProvider;

  // Update attendance provider reference
  void updateAttendanceProvider(AttendanceProvider attendanceProvider) {
    _attendanceProvider = attendanceProvider;
  }

  // Update these properties in your class
  int maxFacesToProcess = 3; // Process 3 faces at once
  Set<String> facesInProcessing = {}; // Track faces being processed
  int _totalFacesDetected = 0;
  int _totalFacesRecognized = 0;

  bool _isModelLoaded = false;
  bool _isProcessing = false;

  // We'll use the session ID from the centralized attendance provider
  // This field is kept for backward compatibility
  String get _currentSessionId =>
      _attendanceProvider?.sessionId ?? const Uuid().v4();

  Set<String> recognizedStudentIdsThisSession =
      {}; // Persistent across detections

  DateTime _lastApiCallTime =
      DateTime.now().subtract(const Duration(seconds: 10));
  final Duration _minApiCallInterval =
      const Duration(milliseconds: 1500); // 1.5 seconds
  Map<String, DateTime> lastProcessedFaces = {};

  // Add getters
  int get totalFacesDetected => _totalFacesDetected;
  int get totalFacesRecognized => _totalFacesRecognized;

  List<Map<String, dynamic>> _detections = [];
  final Map<String, Map<String, dynamic>> _recognizedStudents = {};

  Map<String, Map<String, dynamic>> get recognizedStudents =>
      _recognizedStudents;

  Future<void> loadModel() async {
    // If model is already loaded, just verify it's working
    if (_isModelLoaded) {
      debugPrint("📱 YOLO model already loaded, verifying...");
      try {
        // Simple check by creating an empty image and running detection to verify model
        final testImage = img.Image(width: 320, height: 240);
        img.fill(testImage, color: img.ColorRgb8(255, 255, 255));
        final testBytes = img.encodeJpg(testImage);

        await _vision.yoloOnImage(
          bytesList: testBytes,
          imageHeight: testImage.height,
          imageWidth: testImage.width,
          iouThreshold: 0.4,
          confThreshold: 0.5,
          classThreshold: 0.5,
        );

        debugPrint("📱 YOLO model verification successful");
        return;
      } catch (e) {
        // Model was loaded but seems corrupted or disconnected, reload it
        debugPrint("📱 YOLO model verification failed, reloading: $e");
        _isModelLoaded = false;
      }
    }

    try {
      debugPrint("📱 Attempting to load YOLO model...");

      // First try to close any existing model to clear resources
      try {
        await _vision.closeYoloModel();
        debugPrint("📱 Closed any existing YOLO model");
      } catch (e) {
        // Ignore errors from closing, it might not be loaded
        debugPrint("📱 No existing model to close");
      }

      // Now load the model with a timeout
      try {
        await _vision
            .loadYoloModel(
          labels: 'assets/models/labels.txt',
          modelPath: 'assets/models/yolov8n-face-lindevs_float32.tflite',
          modelVersion: "yolov8",
          quantization: false,
        )
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception("Model loading timed out after 10 seconds");
          },
        );
      } catch (e) {
        debugPrint("📱 Exception during model loading: $e");
        rethrow;
      }

      _isModelLoaded = true;
      debugPrint("📱 YOLO model loaded successfully!");
    } catch (e) {
      debugPrint("📱 Error loading model: $e");
      _isModelLoaded = false;
      rethrow;
    }
  }

  img.Image _convertYUVtoRGB(CameraImage image) {
    try {
      // For higher quality, use a library that properly handles YUV conversion
      // This is a simplified version that might work better:
      final int width = image.width;
      final int height = image.height;

      final img.Image outputImage = img.Image(width: width, height: height);
      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      // More stable conversion with bounds checking
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          if (yIndex >= yPlane.length) continue;

          final int uvY = (y / 2).floor();
          final int uvX = (x / 2).floor();
          final int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

          if (uvIndex >= uPlane.length || uvIndex >= vPlane.length) continue;

          // YUV to RGB standard conversion
          final int yValue = yPlane[yIndex];
          final int uValue = uPlane[uvIndex];
          final int vValue = vPlane[uvIndex];

          // Standard YUV to RGB formula
          int r = (yValue + 1.402 * (vValue - 128)).round();
          int g =
              (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                  .round();
          int b = (yValue + 1.772 * (uValue - 128)).round();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          outputImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      // Verify image isn't corrupted
      if (outputImage.width <= 1 || outputImage.height <= 1) {
        throw Exception("Failed to convert image");
      }

      return outputImage;
    } catch (e) {
      print("📱 YUV conversion error: $e");
      // Return a larger blank image to make the error more obvious
      final errorImage = img.Image(width: 320, height: 240);
      img.fill(errorImage, color: img.ColorRgb8(255, 0, 0));
      return errorImage;
    }
  }

  Future<void> _recognizeFace(
      File faceImage, Map<String, dynamic> detection) async {
    try {
      // Check if file exists and has content
      if (!await faceImage.exists()) {
        debugPrint("📱 Face image file doesn't exist");
        throw Exception("Face image file not found");
      }

      final fileSize = await faceImage.length();
      if (fileSize < 100) {
        debugPrint("📱 Face image too small: $fileSize bytes");
        throw Exception("Face image too small: $fileSize bytes");
      }

      debugPrint(
          "📱 Sending face image for recognition: ${faceImage.path}, size: $fileSize bytes");

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      try {
        // Use 'image' as field name to match backend expectation
        request.files
            .add(await http.MultipartFile.fromPath('image', faceImage.path));
      } catch (e) {
        debugPrint("📱 Error creating MultipartFile: $e");
        throw Exception("Error preparing image for upload: $e");
      }

      // Add device info as recognized_by
      request.fields['recognized_by'] = 'Flutter Mobile App';

      // Add quality flag to tell backend this is potentially a high quality image
      request.fields['high_quality'] = 'true';

      // Add already recognized student IDs to avoid duplicates
      // Use the centralized provider if available, otherwise fall back to local set
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

      // Add session ID to help backend group attendance records - use the centralized one if available
      request.fields['session_id'] = _currentSessionId;

      // Send the request with timeout
      http.StreamedResponse? response;
      try {
        // Use a timeout to avoid hanging if the backend is not responding
        response = await request.send().timeout(const Duration(seconds: 30),
            onTimeout: () {
          throw Exception("Backend request timed out after 30 seconds");
        });
      } catch (e) {
        debugPrint("📱 Error sending request to backend: $e");
        throw Exception("Failed to contact face recognition service: $e");
      }

      // Process the response
      String responseBody = "";
      try {
        responseBody = await response.stream.bytesToString();
        debugPrint("📱 API response: ${response.statusCode} - $responseBody");
      } catch (e) {
        debugPrint("📱 Error reading response: $e");
        throw Exception("Error reading server response");
      }

      // Handle successful response
      if (response.statusCode == 200) {
        // Parse response
        Map<String, dynamic> data;
        try {
          data = jsonDecode(responseBody);
        } catch (e) {
          debugPrint("📱 Error parsing JSON response: $e");
          throw Exception("Invalid response format from server");
        }

        // Process results
        if (data.containsKey('results') && data['results'] is List) {
          final results = data['results'] as List;

          if (results.isNotEmpty) {
            // Get first result
            final firstResult = results[0];
            // Make sure the detection ID is consistent by using integer values
            final double boxLeft = detection['box'][0];
            final double boxTop = detection['box'][1];
            final detectionId = "${boxLeft.toInt()}_${boxTop.toInt()}";
            debugPrint(
                "📱 Using detection ID for recognition result: $detectionId");

            if (firstResult.containsKey('student_id') &&
                firstResult['student_id'] != null) {
              // Student recognized
              final studentId = firstResult['student_id'] as String;
              final String studentName = firstResult['name'] ?? "Unknown Name";

              debugPrint(
                  "📱 Student recognized: $studentName (ID: $studentId)");

              // Store in session tracking
              recognizedStudentIdsThisSession.add(studentId);

              // Calculate confidence (distance is inversely proportional to confidence)
              double confidence = 1.0;
              if (firstResult.containsKey('distance')) {
                confidence = 1.0 - (firstResult['distance'] ?? 0.0);
                // Normalize confidence to 0.0-1.0 range
                confidence = confidence.clamp(0.0, 1.0);

                // Log confidence level
                final confidencePercent = (confidence * 100).toStringAsFixed(1);
                debugPrint("📱 Recognition confidence: $confidencePercent%");
              }

              // Update the centralized attendance provider if available
              if (_attendanceProvider != null) {
                _attendanceProvider!.addRecognizedStudent(
                  detectionId: detectionId,
                  studentId: studentId,
                  name: studentName,
                  confidence: confidence,
                  source: 'person_detection',
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
              // Unknown face
              debugPrint("📱 Face not recognized as any known student");
              _recognizedStudents[detectionId] = {
                'name': 'Unknown',
                'student_id': null,
                'confidence': 0.0,
                'timestamp': DateTime.now().toString(),
              };
            }

            // Update UI
            notifyListeners();
          } else {
            debugPrint("📱 No results returned from recognition API");
          }
        } else {
          debugPrint("📱 Invalid response format: missing 'results' array");
        }
      } else {
        // Handle error response
        debugPrint('📱 Backend error: ${response.statusCode} - $responseBody');
        throw Exception("Backend returned error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('📱 Error sending face to backend: $e');
      throw Exception("Face recognition failed: $e");
    }
  }

  // Update the processCameraImage method to handle multiple faces
  Future<void> processCameraImage(CameraImage image) async {
    if (_isProcessing || !_isModelLoaded) return;
    _isProcessing = true;

    try {
      final results = await _vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.5,
        classThreshold: 0.5,
      );

      _detections = List<Map<String, dynamic>>.from(results);
      _totalFacesDetected = _detections.length;

      notifyListeners();

      final now = DateTime.now();
      if (_detections.isEmpty ||
          now.difference(_lastApiCallTime) <= _minApiCallInterval) {
        _isProcessing = false;
        return;
      }

      _lastApiCallTime = now;

      await sendFullImageForRecognition(image);
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Add this helper method to determine if two detections are likely the same person
  bool _isLikelySameStudent(String detectionIdA, String detectionIdB) {
    // Parse detection IDs to get coordinates
    final coordsA = detectionIdA.split('_');
    final coordsB = detectionIdB.split('_');

    if (coordsA.length < 2 || coordsB.length < 2) return false;

    try {
      final xA = double.parse(coordsA[0]);
      final yA = double.parse(coordsA[1]);
      final xB = double.parse(coordsB[0]);
      final yB = double.parse(coordsB[1]);

      // Calculate distance between detection centers
      final distance = sqrt(pow(xA - xB, 2) + pow(yA - yB, 2));

      // If detections are close, likely the same person
      // Increased threshold for better matching
      return distance < 100; // Was 50, increased to 100
    } catch (e) {
      return false;
    }
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

  @override
  void dispose() {
    _vision.closeYoloModel();
    super.dispose();
  }

  // Add these properties to your class
  bool _isBatchProcessing = false;
  double _batchProgress = 0.0;

  // Add these getters
  bool get isBatchProcessing => _isBatchProcessing;
  double get batchProgress => _batchProgress;

  // Complete implementation of scanClassroom method
  Future<void> scanClassroom(CameraController controller) async {
    if (_isBatchProcessing || !_isModelLoaded) return;

    _isBatchProcessing = true;
    _batchProgress = 0.0;

    // Start a new session in the attendance provider if available
    if (_attendanceProvider != null) {
      _attendanceProvider!.startNewSession(
          name: 'Classroom Scan ${DateTime.now().toString().substring(0, 16)}');
      debugPrint('📱 Started new attendance session for classroom scan');
    }

    notifyListeners();

    try {
      // Take a high-resolution photo
      print("📱 Capturing high-resolution photo...");
      final XFile photo = await controller.takePicture();
      print("📱 Photo captured: ${photo.path}");

      // Load the image into memory
      final Uint8List bytes = await photo.readAsBytes();

      // Get image dimensions
      final img.Image? decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception("Failed to decode captured image");
      }

      // Run detection on the image using FlutterVision
      print(
          "📱 Running detection on photo with dimensions ${decodedImage.width}x${decodedImage.height}...");
      final results = await _vision.yoloOnImage(
        bytesList: bytes,
        imageHeight: decodedImage.height,
        imageWidth: decodedImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.5,
        classThreshold: 0.5,
      );

      final detections = List<Map<String, dynamic>>.from(results);
      _totalFacesDetected = detections.length;
      print("📱 Found ${_totalFacesDetected} faces in classroom image");

      // Sort detections by size (largest faces first)
      detections.sort((a, b) {
        final aSize = (a['box'][2] as double) * (a['box'][3] as double);
        final bSize = (b['box'][2] as double) * (b['box'][3] as double);
        return bSize.compareTo(aSize);
      });

      // Track which students we've already processed in this batch
      final Set<String> processedDetectionIds = {};
      int recognizedInBatch = 0;

      notifyListeners();

      // Process each face in sequence
      for (int i = 0; i < detections.length; i++) {
        final detection = detections[i];
        final detectionId = "${detection['box'][0]}_${detection['box'][1]}";

        // Skip if we've already processed this detection
        if (processedDetectionIds.contains(detectionId)) {
          print("📱 Skipping already processed detection");
          continue;
        }

        // Check if this detection is likely a student we've already recognized
        bool alreadyRecognizedStudent = false;
        for (final entry in _recognizedStudents.entries) {
          if (_isLikelySameStudent(detectionId, entry.key) &&
              entry.value['student_id'] != null) {
            final studentId = entry.value['student_id'];
            if (studentId != null &&
                recognizedStudentIdsThisSession.contains(studentId)) {
              // Already recognized this student in this session
              print(
                  "📱 Skipping already recognized student: ${entry.value['name']}");
              alreadyRecognizedStudent = true;
              break;
            }
          }
        }

        if (!alreadyRecognizedStudent) {
          try {
            // Extract and process the face
            print("📱 Processing face ${i + 1}/${detections.length}");
            final face = await _cropFaceFromImage(decodedImage, detection);
            await _recognizeFace(face, detection);

            // Mark this detection as processed
            processedDetectionIds.add(detectionId);

            // Check if recognition was successful
            bool wasRecognized = false;
            for (final entry in _recognizedStudents.entries) {
              if (_isLikelySameStudent(detectionId, entry.key) &&
                  entry.value['student_id'] != null) {
                wasRecognized = true;
                recognizedInBatch++;
                break;
              }
            }

            if (wasRecognized) {
              print("📱 Successfully recognized face ${i + 1}");
            } else {
              print("📱 Face ${i + 1} was not recognized");
            }

            // Add a small delay to avoid overloading the backend
            await Future.delayed(const Duration(milliseconds: 800));
          } catch (e) {
            print("📱 Error processing face $i: $e");
          }
        }

        // Update progress (even for skipped faces)
        _batchProgress = (i + 1) / detections.length;
        _totalFacesRecognized = _recognizedStudents.values
            .where((student) => student['student_id'] != null)
            .length;

        notifyListeners();
      }

      print(
          "📱 Batch processing complete. Recognized $recognizedInBatch new students.");
    } catch (e) {
      print("📱 Error in batch processing: $e");
    } finally {
      _isBatchProcessing = false;
      _batchProgress = 1.0;
      notifyListeners();

      // Reset progress after a delay
      await Future.delayed(const Duration(seconds: 3));
      _batchProgress = 0.0;
      notifyListeners();
    }
  }

  // Helper method to crop face from a full image
  Future<File> _cropFaceFromImage(
      img.Image fullImage, Map<String, dynamic> detection) async {
    try {
      debugPrint('📱 Cropping face with detection: $detection');

      // Safely extract box coordinates with type checking
      List<dynamic> box = detection['box'];
      if (box.length < 4) {
        throw Exception("Invalid face detection box: $box");
      }

      // Convert values to int, handling any potential type issues
      final x =
          (box[0] is double ? box[0] : double.parse(box[0].toString())).toInt();
      final y =
          (box[1] is double ? box[1] : double.parse(box[1].toString())).toInt();
      final w =
          (box[2] is double ? box[2] : double.parse(box[2].toString())).toInt();
      final h =
          (box[3] is double ? box[3] : double.parse(box[3].toString())).toInt();

      debugPrint('📱 Face coordinates: x=$x, y=$y, w=$w, h=$h');

      // Validate dimensions
      if (w <= 0 || h <= 0) {
        throw Exception("Invalid face dimensions: width=$w, height=$h");
      }

      // Use smaller padding for better face crop quality
      final int paddingX = (w * 0.3).toInt(); // Reduced from 0.6
      final int paddingY = (h * 0.3).toInt(); // Reduced from 0.6

      // Make sure we don't go out of bounds
      final int safeX = max(0, x - paddingX);
      final int safeY = max(0, y - paddingY);
      final int safeW = min(fullImage.width - safeX, w + (paddingX * 2));
      final int safeH = min(fullImage.height - safeY, h + (paddingY * 2));

      debugPrint(
          '📱 Cropping area: x=$safeX, y=$safeY, w=$safeW, h=$safeH from image size ${fullImage.width}x${fullImage.height}');

      // Crop the face region with padding
      final faceImage = img.copyCrop(
        fullImage,
        x: safeX,
        y: safeY,
        width: safeW,
        height: safeH,
      );

      debugPrint('📱 Initial crop successful');

      // Simple checks to ensure the face crop was successful
      if (faceImage.width < 10 || faceImage.height < 10) {
        throw Exception(
            "Face crop too small: ${faceImage.width}x${faceImage.height}");
      }

      // Apply image enhancements for better face recognition
      final enhancedImage = img.adjustColor(
        faceImage,
        brightness: 1.1, // Slightly reduce brightness enhancement
        contrast: 1.2, // Slightly reduce contrast enhancement
        saturation: 1.0,
      );

      debugPrint('📱 Image enhancement applied');

      // Standardize size for face recognition (keeping aspect ratio)
      double aspectRatio = enhancedImage.width / enhancedImage.height;
      int targetWidth, targetHeight;

      if (aspectRatio > 1) {
        // Wider than tall
        targetWidth = 640;
        targetHeight = (640 / aspectRatio).round();
      } else {
        // Taller than wide or square
        targetHeight = 640;
        targetWidth = (640 * aspectRatio).round();
      }

      final resizedImage = img.copyResize(enhancedImage,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.cubic);

      debugPrint(
          '📱 Image resized to ${resizedImage.width}x${resizedImage.height}');

      // Save to file
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      final jpegBytes = img.encodeJpg(resizedImage,
          quality: 95); // Slightly reduced quality for better compression
      await file.writeAsBytes(jpegBytes);

      final fileSize = await file.length();
      debugPrint('📱 Face image saved to ${file.path}, size: $fileSize bytes');

      return file;
    } catch (e) {
      debugPrint('📱 Error cropping face from full image: $e');

      // Create a placeholder image in case of error
      // Using a larger placeholder to be more obvious that it's a fallback
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_error_$timestamp.jpg';
      final file = File(path);

      // Create a red placeholder image to make it clear this is a fallback
      final placeholderImage = img.Image(width: 320, height: 320);
      img.fill(placeholderImage,
          color: img.ColorRgb8(255, 200, 200)); // Light red

      // Draw a face-like pattern
      img.drawCircle(placeholderImage,
          x: 160, y: 160, radius: 120, color: img.ColorRgb8(255, 150, 150));

      // Create eyes
      img.drawCircle(placeholderImage,
          x: 120, y: 120, radius: 20, color: img.ColorRgb8(100, 100, 100));
      img.drawCircle(placeholderImage,
          x: 200, y: 120, radius: 20, color: img.ColorRgb8(100, 100, 100));

      // Create mouth
      img.drawLine(placeholderImage,
          x1: 120,
          y1: 200,
          x2: 200,
          y2: 200,
          color: img.ColorRgb8(100, 100, 100),
          thickness: 10);

      await file.writeAsBytes(img.encodeJpg(placeholderImage));

      debugPrint('📱 Created placeholder face image: ${file.path}');

      throw Exception("Failed to crop face from image: $e");
    }
  }

  // Add this new function to your FaceDetectionProvider class
  Future<void> sendFullImageForRecognition(CameraImage cameraImage) async {
    if (!_isModelLoaded) return;

    try {
      // Convert the full YUV camera image to RGB
      final fullImage = _convertYUVtoRGB(cameraImage);

      // Save as JPEG to send to backend
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/full_frame_$timestamp.jpg';
      final file = File(path);

      await file.writeAsBytes(img.encodeJpg(fullImage, quality: 95));
      print("📱 Saving full frame image: $path (${await file.length()} bytes)");

      // Send to backend
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      // Add image
      request.files.add(await http.MultipartFile.fromPath('image', file.path));

      // Add metadata
      request.fields['recognized_by'] = 'Flutter Mobile App';
      request.fields['process_full_image'] = 'true';

      if (recognizedStudentIdsThisSession.isNotEmpty) {
        request.fields['already_recognized'] =
            recognizedStudentIdsThisSession.join(',');
      }
      request.fields['session_id'] = _currentSessionId;

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final results = data['results'] as List;

        // Process each detected face
        for (final result in results) {
          if (result['student_id'] != null) {
            // Store recognized student
            final studentId = result['student_id'] as String;
            recognizedStudentIdsThisSession.add(studentId);

            // Create unique ID for this detection
            final uniqueId = '${timestamp}_${result['face_index'] ?? 0}';

            // Calculate confidence from distance
            final double confidence = 1.0 - (result['distance'] ?? 0.0);
            final name = result['name'] as String? ?? 'Unknown';

            // Update the centralized attendance provider if available
            if (_attendanceProvider != null) {
              _attendanceProvider!.addRecognizedStudent(
                detectionId: uniqueId,
                studentId: studentId,
                name: name,
                confidence: confidence,
                source: 'person_detection',
              );
            }

            // Also update local map for backwards compatibility
            _recognizedStudents[uniqueId] = {
              'name': name,
              'student_id': studentId,
              'confidence': confidence,
              'timestamp': DateTime.now().toString(),
            };
          }
        }

        // Update stats
        _totalFacesDetected = results.length;
        _totalFacesRecognized = _recognizedStudents.values
            .where((student) => student['student_id'] != null)
            .length;

        notifyListeners();
      }
    } catch (e) {
      print("📱 Error sending full image: $e");
      debugPrint('Error sending full image to backend: $e');
    }
  }
}


// import 'dart:io';
// import 'dart:convert';
// import 'dart:ui';
// import 'package:flutter/foundation.dart';
// import 'package:flutter_vision/flutter_vision.dart';
// import 'package:http/http.dart' as http;
// import 'package:image/image.dart' as img;
// import 'package:open_rtms/models/detection_result.dart';
// import 'package:camera/camera.dart';

// class PersonDetectionProvider with ChangeNotifier {
//   final FlutterVision _vision = FlutterVision();
//   final String _backendUrl = 'http://10.134.30.235:8000/api/recognize/';

//   bool _isModelLoaded = false;
//   bool _isProcessing = false;
//   bool _isLiveDetectionActive = false;

//   final String _currentSessionId =
//       DateTime.now().millisecondsSinceEpoch.toString();

//   Set<String> recognizedStudentIdsThisSession = {};
//   Map<String, DateTime> lastProcessedPersons = {};

//   List<MLResult> _detections = [];
//   final Map<String, Map<String, dynamic>> _recognizedStudents = {};

//   // Camera related fields
//   CameraController? _cameraController;
//   int _cameraFrameSkip = 10; // Process every 10th frame
//   int _frameCount = 0;

//   List<MLResult> get detections => _detections;
//   Map<String, Map<String, dynamic>> get recognizedStudents =>
//       _recognizedStudents;
//   bool get isProcessing => _isProcessing;
//   bool get isLiveDetectionActive => _isLiveDetectionActive;
//   CameraController? get cameraController => _cameraController;

//   // Method to update detections directly
//   void updateDetections(List<MLResult> detections) {
//     _detections = detections;
//     notifyListeners();
//   }

//   // Initialize camera controller
//   Future<void> initializeCamera() async {
//     final cameras = await availableCameras();
//     if (cameras.isEmpty) {
//       throw Exception('No cameras available');
//     }

//     // Use the first available back camera
//     final backCamera = cameras.firstWhere(
//       (camera) => camera.lensDirection == CameraLensDirection.back,
//       orElse: () => cameras.first,
//     );

//     _cameraController = CameraController(
//       backCamera,
//       ResolutionPreset.medium,
//       enableAudio: false,
//       imageFormatGroup: ImageFormatGroup.jpeg,
//     );

//     await _cameraController!.initialize();
//     notifyListeners();
//   }

//   Future<void> loadModel() async {
//     if (_isModelLoaded) {
//       debugPrint("📱 YOLO model already loaded, verifying...");
//       return;
//     }

//     try {
//       debugPrint("📱 Attempting to load YOLO object detection model...");

//       // First try to close any existing model to clear resources
//       try {
//         await _vision.closeYoloModel();
//         debugPrint("📱 Closed any existing YOLO model");
//       } catch (e) {
//         debugPrint("📱 No existing model to close");
//       }

//       // Now load the model with a timeout
//       await _vision
//           .loadYoloModel(
//         labels: 'assets/models/object/metadata.yaml',
//         modelPath: 'assets/models/object/yolov8n_int8.tflite',
//         modelVersion: "yolov8",
//         quantization: true,
//       )
//           .timeout(
//         const Duration(seconds: 10),
//         onTimeout: () {
//           throw Exception("Model loading timed out after 10 seconds");
//         },
//       );

//       _isModelLoaded = true;
//       debugPrint("📱 YOLO model loaded successfully!");
//     } catch (e) {
//       debugPrint("📱 Error loading model: $e");
//       _isModelLoaded = false;
//       rethrow;
//     }
//   }

//   void toggleLiveDetection() {
//     _isLiveDetectionActive = !_isLiveDetectionActive;

//     if (_isLiveDetectionActive) {
//       _startLiveDetection();
//     } else {
//       _stopLiveDetection();
//     }

//     notifyListeners();
//   }

//   Future<void> _startLiveDetection() async {
//     if (!_isModelLoaded) {
//       await loadModel();
//     }

//     if (_cameraController == null || !_cameraController!.value.isInitialized) {
//       await initializeCamera();
//     }

//     // Start the camera stream if not already streaming
//     if (!_cameraController!.value.isStreamingImages) {
//       await _cameraController!
//           .startImageStream((image) => _processFrame(image));
//     }
//   }

//   void _stopLiveDetection() {
//     if (_cameraController?.value.isStreamingImages ?? false) {
//       _cameraController!.stopImageStream();
//     }
//     _isLiveDetectionActive = false;
//     notifyListeners();
//   }

//   Future<void> _processFrame(CameraImage image) async {
//     if (_isProcessing) return;

//     // Process every few frames to reduce CPU load
//     _frameCount++;
//     if (_frameCount % _cameraFrameSkip != 0) return;

//     _isProcessing = true;

//     try {
//       // Convert CameraImage to format needed by flutter_vision
//       final bytesList = await _vision.yoloOnFrame(
//         bytesList: image.planes.map((plane) => plane.bytes).toList(),
//         imageHeight: image.height,
//         imageWidth: image.width,
//         iouThreshold: 0.3, // Lower IOU threshold to detect overlapping objects
//         confThreshold: 0.2, // Lower confidence threshold to detect more objects
//         classThreshold: 0.2, // Lower class threshold
//       );

//       debugPrint('📱 YOLO detection found ${bytesList.length} objects');
//       if (bytesList.isNotEmpty) {
//         // Print first detection for debugging
//         debugPrint('📱 First detection: ${bytesList.first}');
//       }

//       // Convert to our standard detection format
//       final results = bytesList.map((detection) {
//         final double left = detection['box'][0];
//         final double top = detection['box'][1];
//         final double width = detection['box'][2];
//         final double height = detection['box'][3];

//         final name = detection['name'] ?? 'unknown';
//         final confidence = detection['confidence'] ?? 0.0;

//         debugPrint(
//             '📱 Detected: $name (${(confidence * 100).toStringAsFixed(1)}%)');

//         return MLResult(
//           classIndex: detection['class'],
//           className: name,
//           confidence: confidence,
//           boundingBox: Rect.fromLTWH(left, top, width, height),
//           normalizedBox: Rect.fromLTRB(
//             left / image.width,
//             top / image.height,
//             (left + width) / image.width,
//             (top + height) / image.height,
//           ),
//         );
//       }).toList();

//       // Don't filter initially - let's see what classes the model is detecting
//       final allDetections = results;

//       // Also create a filtered list for people only
//       final personDetections = results.where((result) {
//         // Check for various person-related class names
//         final className = result.className.toLowerCase();
//         return className.contains('person') ||
//             className.contains('human') ||
//             className.contains('people') ||
//             className == '0'; // Sometimes class 0 is person
//       }).toList();

//       debugPrint(
//           '📱 Found ${personDetections.length} person detections out of ${results.length} total');

//       // Use all detections initially to see what's detected
//       _detections = allDetections;

//       // Update the detections
//       _detections = personDetections;

//       // If we have at least one person detected, try to identify them
//       if (personDetections.isNotEmpty) {
//         await _processLiveAttendance(image);
//       }

//       notifyListeners();
//     } catch (e) {
//       debugPrint('📱 Error processing camera frame: $e');
//     } finally {
//       _isProcessing = false;
//     }
//   }

//   Future<void> _processLiveAttendance(CameraImage image) async {
//     try {
//       // Convert camera image to a JPEG bytestream
//       final bytes = await _convertImageToJpeg(image);

//       // Create a temporary file for the image
//       final tempDir = await Directory.systemTemp.createTemp('attendance_');
//       final tempFile = File('${tempDir.path}/temp_frame.jpg');
//       await tempFile.writeAsBytes(bytes);

//       // Send to backend for recognition
//       final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

//       request.files
//           .add(await http.MultipartFile.fromPath('image', tempFile.path));
//       request.fields['recognized_by'] = 'Flutter Mobile App - Live Detection';
//       request.fields['session_id'] = _currentSessionId;

//       if (recognizedStudentIdsThisSession.isNotEmpty) {
//         request.fields['already_recognized'] =
//             recognizedStudentIdsThisSession.join(',');
//       }

//       final response = await request.send().timeout(
//         const Duration(seconds: 10),
//         onTimeout: () {
//           throw Exception("Backend request timed out");
//         },
//       );

//       // Process the response
//       if (response.statusCode == 200) {
//         final responseBody = await response.stream.bytesToString();
//         final data = jsonDecode(responseBody);

//         if (data.containsKey('results') && data['results'] is List) {
//           final results = data['results'] as List;

//           if (results.isNotEmpty && _detections.isNotEmpty) {
//             // Map the backend results to the detections
//             for (int i = 0; i < _detections.length; i++) {
//               final detection = _detections[i];
//               final String detectionId =
//                   "${detection.boundingBox.left.toInt()}_${detection.boundingBox.top.toInt()}";

//               // Find matching result
//               if (i < results.length) {
//                 final result = results[i];

//                 if (result.containsKey('student_id') &&
//                     result['student_id'] != null) {
//                   // Student recognized
//                   final studentId = result['student_id'] as String;
//                   final String studentName = result['name'] ?? "Unknown Name";

//                   // Track recognized students
//                   recognizedStudentIdsThisSession.add(studentId);

//                   // Calculate confidence
//                   double confidence = 1.0;
//                   if (result.containsKey('distance')) {
//                     confidence = 1.0 - (result['distance'] ?? 0.0);
//                     confidence = confidence.clamp(0.0, 1.0);
//                   }

//                   // Update the recognizedStudents map
//                   _recognizedStudents[detectionId] = {
//                     'name': studentName,
//                     'student_id': studentId,
//                     'confidence': confidence,
//                     'timestamp': DateTime.now().toString(),
//                   };
//                 } else {
//                   // Unknown person
//                   _recognizedStudents[detectionId] = {
//                     'name': 'Unknown',
//                     'student_id': null,
//                     'confidence': 0.0,
//                     'timestamp': DateTime.now().toString(),
//                   };
//                 }
//               }
//             }
//           }
//         }
//       }

//       // Clean up temp file
//       await tempFile.delete();
//       await tempDir.delete();
//     } catch (e) {
//       debugPrint('📱 Error processing live attendance: $e');
//     }
//   }

//   // Helper method to convert a CameraImage to JPEG bytes
//   Future<Uint8List> _convertImageToJpeg(CameraImage image) async {
//     try {
//       // Convert YUV420 format to RGB format
//       final img.Image convertedImage = _convertYUV420ToImage(image);

//       // Encode to JPEG
//       final jpegBytes = img.encodeJpg(convertedImage, quality: 80);
//       return Uint8List.fromList(jpegBytes);
//     } catch (e) {
//       debugPrint('📱 Error converting camera image: $e');
//       rethrow;
//     }
//   }

//   // Convert YUV420 to RGB image
//   img.Image _convertYUV420ToImage(CameraImage cameraImage) {
//     debugPrint(
//         '📱 Converting YUV420 image: ${cameraImage.width}x${cameraImage.height}');

//     try {
//       final width = cameraImage.width;
//       final height = cameraImage.height;

//       // Create a new image
//       final rgbImage = img.Image(width: width, height: height);

//       // Process YUV data
//       final yPlane = cameraImage.planes[0].bytes;
//       final uPlane = cameraImage.planes[1].bytes;
//       final vPlane = cameraImage.planes[2].bytes;

//       final yRowStride = cameraImage.planes[0].bytesPerRow;
//       final uvRowStride = cameraImage.planes[1].bytesPerRow;
//       final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

//       for (int y = 0; y < height; y++) {
//         int yIndex = y * yRowStride;
//         final int uvRowIndex = (y / 2).floor() * uvRowStride;

//         for (int x = 0; x < width; x++) {
//           final int uvIndex = uvRowIndex + (x / 2).floor() * uvPixelStride;

//           final int yValue = yPlane[yIndex++];
//           final int uValue = uPlane[uvIndex];
//           final int vValue = vPlane[uvIndex];

//           // Convert YUV to RGB
//           int r = (yValue + 1.370705 * (vValue - 128)).round().clamp(0, 255);
//           int g =
//               (yValue - 0.698001 * (vValue - 128) - 0.337633 * (uValue - 128))
//                   .round()
//                   .clamp(0, 255);
//           int b = (yValue + 1.732446 * (uValue - 128)).round().clamp(0, 255);

//           // Set pixel in rgbImage
//           rgbImage.setPixel(x, y, img.ColorRgb8(r, g, b));
//         }
//       }

//       debugPrint('📱 Image conversion complete');
//       return rgbImage;
//     } catch (e) {
//       debugPrint('📱 Error in YUV conversion: $e');
//       // Fallback to simpler conversion method
//       final img.Image simpleImage =
//           img.Image(width: cameraImage.width, height: cameraImage.height);
//       final yPlane = cameraImage.planes[0].bytes;
//       final yRowStride = cameraImage.planes[0].bytesPerRow;

//       // Just use Y plane for luminance only (grayscale)
//       for (int y = 0; y < cameraImage.height; y++) {
//         for (int x = 0; x < cameraImage.width; x++) {
//           final int yIdx = y * yRowStride + x;
//           if (yIdx < yPlane.length) {
//             final int gray = yPlane[yIdx];
//             simpleImage.setPixel(x, y, img.ColorRgb8(gray, gray, gray));
//           }
//         }
//       }

//       debugPrint('📱 Fallback image conversion complete');
//       return simpleImage;
//     }
//   }

//   void resetAttendance() {
//     _recognizedStudents.clear();
//     recognizedStudentIdsThisSession.clear();
//     lastProcessedPersons.clear();
//     notifyListeners();
//   }

//   @override
//   void dispose() {
//     _cameraController?.dispose();
//     _vision.closeYoloModel();
//     super.dispose();
//   }
// }
