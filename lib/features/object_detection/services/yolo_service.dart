import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import '../models/detection_result.dart';

/// Service for handling YOLO model operations
class YoloService {
  // static const String MODEL_PATH = 'face/yolov11n-face_int8';
  // static const String MODEL_PATH =
  //     'face/yolov11n-face_full_integer_quant'; // didn't crash
  static const String MODEL_PATH = 'face/yolov8n-face-lindevs_int8';
  // static const String MODEL_PATH = 'object/yolov8n_int8';

  late YOLO _yolo;
  bool _isInitialized = false;

  /// Initialize the YOLO model
  Future<void> initialize(
      {String? customModelPath, YOLOTask task = YOLOTask.detect}) async {
    final modelPath = customModelPath ?? MODEL_PATH;
    _yolo = YOLO(modelPath: modelPath, task: task);
    await _yolo.loadModel();
    _isInitialized = true;
    debugPrint('YOLO model initialized with path: $modelPath');
  }

  /// Check if the YOLO model is initialized
  bool get isInitialized => _isInitialized;

  /// Predict objects in an image
  Future<Map<String, dynamic>> predictImage(Uint8List imageBytes) async {
    if (!_isInitialized) {
      debugPrint('YOLO model not initialized, initializing now...');
      await initialize();
    }

    try {
      final result = await _yolo.predict(imageBytes);
      return result;
    } catch (e) {
      debugPrint('Error during YOLO prediction: $e');
      return {'boxes': [], 'error': e.toString()};
    }
  }

  /// Process YOLO results into standard detection results
  List<DetectionResult> processResults(List<YOLOResult> results) {
    return results
        .map((result) => DetectionResult.fromYOLOResult(result))
        .toList();
  }

  /// Create a new YOLO controller
  YoloViewController createController() {
    return YoloViewController();
  }

  /// Configure controller with default thresholds
  Future<void> configureController(
    YoloViewController controller, {
    double confidenceThreshold = 0.5,
    double iouThreshold = 0.45,
  }) async {
    await controller.setImageSize(
      width: 320,
      height: 320,
    );

    await controller.setThresholds(
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
  }
}
