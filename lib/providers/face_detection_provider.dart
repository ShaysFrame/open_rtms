import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class FaceDetectionProvider with ChangeNotifier {
  final FlutterVision _vision = FlutterVision();
  final String _backendUrl = 'http://10.134.13.24:8000/api/recognize/';

  // Update these properties in your class
  int maxFacesToProcess = 3; // Process 3 faces at once
  Set<String> facesInProcessing = {}; // Track faces being processed
  int _totalFacesDetected = 0;
  int _totalFacesRecognized = 0;

  bool _isModelLoaded = false;
  bool _isProcessing = false;

  final String _currentSessionId =
      DateTime.now().millisecondsSinceEpoch.toString();

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

  List<Map<String, dynamic>> get detections => _detections;
  Map<String, Map<String, dynamic>> get recognizedStudents =>
      _recognizedStudents;

  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      print("📱 Attempting to load YOLO model...");
      await _vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/yolov8n-face-lindevs_float32.tflite',
        modelVersion: "yolov8",
        quantization: false,
      );
      _isModelLoaded = true;
      print("📱 YOLO model loaded successfully!");
    } catch (e) {
      print("📱 Error loading model: $e");
      debugPrint('Error loading model: $e');
      rethrow;
    }
  }

  Future<File> _cropAndSaveFace(
      CameraImage image, Map<String, dynamic> detection) async {
    try {
      final x = (detection['box'][0] as double).toInt();
      final y = (detection['box'][1] as double).toInt();
      final w = (detection['box'][2] as double).toInt();
      final h = (detection['box'][3] as double).toInt();

      final int paddingX = (w * 0.1).toInt(); // 60% padding horizontally
      final int paddingY = (h * 0.1).toInt(); // 60% padding vertically

      // Make sure we don't go out of bounds
      final int safeX = max(0, x - paddingX);
      final int safeY = max(0, y - paddingY);
      final int safeW = min(image.width - safeX, w + (paddingX * 2));
      final int safeH = min(image.height - safeY, h + (paddingY * 2));

      print(
          "📱 Cropping face at ($safeX,$safeY,$safeW,$safeH) from ${image.width}x${image.height}");

      // Convert YUV to RGB
      final convertedImage = _convertYUVtoRGB(image);

      // Skip if conversion failed (image size check)
      if (convertedImage.width <= 1 || convertedImage.height <= 1) {
        throw Exception("Image conversion failed");
      }

      // Check if face area is valid
      if (safeW < 20 || safeH < 20) {
        throw Exception("Face area too small: ${safeW}x${safeH}");
      }

      // Crop the face region with padding
      final faceImage = img.copyCrop(
        convertedImage,
        x: safeX,
        y: safeY,
        width: safeW,
        height: safeH,
      );

      // Apply image enhancements to make face more recognizable
      final enhancedImage = img.adjustColor(
        faceImage,
        brightness: 1.2, // Brighter
        contrast: 1.3, // More contrast
        saturation: 1.0, // Normal saturation
      );

      // Try to normalize the image size to something face_recognition works well with
      final resizedImage = img.copyResize(enhancedImage,
          width: 640, // Standard width that works well
          height: 480, // Standard height that works well
          interpolation: img.Interpolation.cubic);

      // Save the face image to a file with higher quality
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      await file.writeAsBytes(
          img.encodeJpg(resizedImage, quality: 100)); // Use highest quality

      print(
          "📱 Enhanced face image saved: ${file.path}, size: ${await file.length()} bytes");
      return file;
    } catch (e) {
      debugPrint('Error cropping face: $e');
      // Create a blank image in case of error
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      // Create a simple 1x1 white pixel image
      final blankImage = img.Image(width: 1, height: 1);
      img.fill(blankImage, color: img.ColorRgb8(255, 255, 255));
      await file.writeAsBytes(img.encodeJpg(blankImage));

      return file;
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
        print("📱 Face image file doesn't exist");
        return;
      }

      final fileSize = await faceImage.length();
      if (fileSize < 100) {
        print("📱 Face image too small: $fileSize bytes");
        return;
      }

      print(
          "📱 Sending face image for recognition: ${faceImage.path}, size: $fileSize bytes");

      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      // Use 'image' as field name to match backend expectation
      request.files
          .add(await http.MultipartFile.fromPath('image', faceImage.path));

      // Add device info as recognized_by
      request.fields['recognized_by'] = 'Flutter Mobile App';

      // Add already recognized student IDs to avoid duplicates
      // This tells backend which students are already recognized in this session
      if (recognizedStudentIdsThisSession.isNotEmpty) {
        request.fields['already_recognized'] =
            recognizedStudentIdsThisSession.join(',');
      }

      // Add session ID to help backend group attendance records
      request.fields['session_id'] = _currentSessionId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print("📱 API response: ${response.statusCode} - $responseBody");

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          final firstResult = results[0];
          final detectionId = "${detection['box'][0]}_${detection['box'][1]}";

          // Update _recognizeFace method to add this code after a successful recognition:
          if (firstResult['student_id'] != null) {
            // Student recognized
            final studentId = firstResult['student_id'] as String;

            // Store in session tracking
            recognizedStudentIdsThisSession.add(studentId);

            _recognizedStudents[detectionId] = {
              'name': firstResult['name'],
              'student_id': studentId,
              'confidence': 1.0 - (firstResult['distance'] ?? 0.0),
              'timestamp': DateTime.now().toString(),
            };
          } else {
            // Unknown face
            _recognizedStudents[detectionId] = {
              'name': 'Unknown',
              'student_id': null,
              'confidence': 0.0,
              'timestamp': DateTime.now().toString(),
            };
          }

          notifyListeners();
        }
      } else {
        debugPrint('Backend error: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      debugPrint('Error sending face to backend: $e');
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

      // // Update total detected faces count
      // _totalFacesDetected = _detections.length;
      // _totalFacesRecognized = _recognizedStudents.values
      //     .where((student) => student['student_id'] != null)
      //     .length;

      notifyListeners();

      final now = DateTime.now();
      if (_detections.isEmpty ||
          now.difference(_lastApiCallTime) <= _minApiCallInterval) {
        _isProcessing = false;
        return;
      }

      _lastApiCallTime = now;

      await sendFullImageForRecognition(image);

      // if (_detections.isNotEmpty) {
      //   // Sort by size (largest first) to prioritize closer/more prominent faces
      //   _detections.sort((a, b) {
      //     final aSize = (a['box'][2] as double) * (a['box'][3] as double);
      //     final bSize = (b['box'][2] as double) * (b['box'][3] as double);
      //     return bSize.compareTo(aSize);
      //   });

      // // Only process if we're not at the API rate limit
      // if (now.difference(_lastApiCallTime) > _minApiCallInterval) {
      //   // Find faces that haven't been processed recently and aren't currently being processed
      //   final facesToProcess = _detections
      //       .where((detection) {
      //         final detectionId =
      //             "${detection['box'][0]}_${detection['box'][1]}";

      //         // Skip if this student was already recognized in this session
      //         for (final entry in _recognizedStudents.entries) {
      //           if (_isLikelySameStudent(detectionId, entry.key) &&
      //               entry.value['student_id'] != null) {
      //             return false; // Skip this face
      //           }
      //         }

      //         return true; // Process this face
      //       })
      //       .take(maxFacesToProcess)
      //       .toList();

      //   if (facesToProcess.isNotEmpty) {
      //     _lastApiCallTime = now; // Update API call timestamp

      //     // Process each face asynchronously
      //     for (final detection in facesToProcess) {
      //       final detectionId =
      //           "${detection['box'][0]}_${detection['box'][1]}";
      //       facesInProcessing.add(detectionId);

      //       // Process the face in the background
      //       _processSingleFace(image, detection, detectionId).then((_) {
      //         facesInProcessing.remove(detectionId);
      //       });
      //     }
      //   }
      // }
      // }
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

  // New helper method to process a single face
  Future<void> _processSingleFace(CameraImage image,
      Map<String, dynamic> detection, String detectionId) async {
    try {
      final face = await _cropAndSaveFace(image, detection);
      await _recognizeFace(face, detection);

      // Update timestamps
      lastProcessedFaces[detectionId] = DateTime.now();

      // Clean up old entries
      lastProcessedFaces.removeWhere((key, time) =>
          DateTime.now().difference(time) > const Duration(minutes: 1));

      // Update recognized count
      _totalFacesRecognized = _recognizedStudents.values
          .where((student) => student['student_id'] != null)
          .length;

      notifyListeners();
    } catch (e) {
      print("📱 Error processing individual face: $e");
    }
  }

  void resetAttendance() {
    _recognizedStudents.clear();
    recognizedStudentIdsThisSession.clear();
    lastProcessedFaces.clear();
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
      final x = (detection['box'][0] as double).toInt();
      final y = (detection['box'][1] as double).toInt();
      final w = (detection['box'][2] as double).toInt();
      final h = (detection['box'][3] as double).toInt();

      // Same padding as your existing method
      final int paddingX = (w * 0.6).toInt();
      final int paddingY = (h * 0.6).toInt();

      // Make sure we don't go out of bounds
      final int safeX = max(0, x - paddingX);
      final int safeY = max(0, y - paddingY);
      final int safeW = min(fullImage.width - safeX, w + (paddingX * 2));
      final int safeH = min(fullImage.height - safeY, h + (paddingY * 2));

      // Crop the face region with padding
      final faceImage = img.copyCrop(
        fullImage,
        x: safeX,
        y: safeY,
        width: safeW,
        height: safeH,
      );

      // Apply image enhancements just like in _cropAndSaveFace
      final enhancedImage = img.adjustColor(
        faceImage,
        brightness: 1.2,
        contrast: 1.3,
        saturation: 1.0,
      );

      final resizedImage = img.copyResize(enhancedImage,
          width: 640, height: 480, interpolation: img.Interpolation.cubic);

      // Save to file
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      await file.writeAsBytes(img.encodeJpg(resizedImage, quality: 100));
      return file;
    } catch (e) {
      debugPrint('Error cropping face from full image: $e');
      // Create a blank image in case of error
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      final blankImage = img.Image(width: 1, height: 1);
      img.fill(blankImage, color: img.ColorRgb8(255, 255, 255));
      await file.writeAsBytes(img.encodeJpg(blankImage));

      return file;
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

            _recognizedStudents[uniqueId] = {
              'name': result['name'],
              'student_id': studentId,
              'confidence': 1.0 - (result['distance'] ?? 0.0),
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
