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

  bool _isModelLoaded = false;
  bool _isProcessing = false;

  DateTime _lastApiCallTime =
      DateTime.now().subtract(const Duration(seconds: 10));
  final Duration _minApiCallInterval =
      const Duration(milliseconds: 1500); // 1.5 seconds
  Map<String, DateTime> _lastProcessedFaces = {};

  List<Map<String, dynamic>> _detections = [];
  Map<String, Map<String, dynamic>> _recognizedStudents = {};

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

      // Increase padding significantly to capture more face context
      // This helps the face_recognition library detect facial features
      final int paddingX = (w * 0.6).toInt(); // 60% padding horizontally
      final int paddingY = (h * 0.6).toInt(); // 60% padding vertically

      // Make sure we don't go out of bounds
      final int safeX = max(0, x - paddingX);
      final int safeY = max(0, y - paddingY);
      final int safeW = min(image.width - safeX, w + (paddingX * 2));
      final int safeH = min(image.height - safeY, h + (paddingY * 2));

      print(
          "📱 Cropping face at ($safeX,$safeY,$safeW,$safeH) from ${image.width}x${image.height}");

      // Convert YUV to RGB
      final convertedImage = _convertYUVtoRGB(image);

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
      final int width = image.width;
      final int height = image.height;

      // Get image planes
      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      print("📱 Converting YUV: $width x $height");

      // Create output image
      final img.Image outputImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          // UV values are sampled at half resolution compared to Y values
          final int uvY = (y / 2).floor();
          final int uvX = (x / 2).floor();
          final int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

          final int yValue = yPlane[yIndex];
          final int uValue = uPlane.length > uvIndex ? uPlane[uvIndex] : 128;
          final int vValue = vPlane.length > uvIndex ? vPlane[uvIndex] : 128;

          // YUV to RGB conversion
          int r = (yValue + 1.402 * (vValue - 128)).round();
          int g =
              (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                  .round();
          int b = (yValue + 1.772 * (uValue - 128)).round();

          // Clamp RGB values
          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          outputImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return outputImage;
    } catch (e) {
      print("📱 YUV conversion error: $e");
      // Return a small blank image in case of error
      return img.Image(width: 1, height: 1);
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

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print("📱 API response: ${response.statusCode} - $responseBody");

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          final firstResult = results[0];
          final detectionId = "${detection['box'][0]}_${detection['box'][1]}";

          if (firstResult['student_id'] != null) {
            // Student recognized
            _recognizedStudents[detectionId] = {
              'name': firstResult['name'],
              'student_id': firstResult['student_id'],
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
      notifyListeners();

      // Only process one face at a time to reduce API calls
      if (_detections.isNotEmpty) {
        // Sort by size (largest first) to prioritize closer/more prominent faces
        _detections.sort((a, b) {
          final aSize = (a['box'][2] as double) * (a['box'][3] as double);
          final bSize = (b['box'][2] as double) * (b['box'][3] as double);
          return bSize.compareTo(aSize);
        });

        // Only process the first (largest) face
        final detection = _detections.first;
        final detectionId = "${detection['box'][0]}_${detection['box'][1]}";

        // Check if this face was recently processed
        final now = DateTime.now();
        final lastProcessed = _lastProcessedFaces[detectionId];
        final faceDebounceTime = const Duration(seconds: 5);

        if (lastProcessed == null ||
            now.difference(lastProcessed) > faceDebounceTime) {
          // Check if we should call the API based on global rate limiting
          if (now.difference(_lastApiCallTime) > _minApiCallInterval) {
            final face = await _cropAndSaveFace(image, detection);
            await _recognizeFace(face, detection);

            // Update timestamps
            _lastApiCallTime = now;
            _lastProcessedFaces[detectionId] = now;

            // Clean up old entries in _lastProcessedFaces
            _lastProcessedFaces.removeWhere((key, time) =>
                now.difference(time) > const Duration(minutes: 1));
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void resetAttendance() {
    _recognizedStudents.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _vision.closeYoloModel();
    super.dispose();
  }
}
