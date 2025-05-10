import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';

/// Model class for standardizing object detection results
class DetectionResult {
  final int classIndex;
  final String className;
  final double confidence;
  final Rect boundingBox;
  final List<List<double>>? mask; // For segmentation
  final List<Point>? keypoints; // For pose estimation

  DetectionResult({
    required this.classIndex,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    this.mask,
    this.keypoints,
  });

  /// Convert a YOLOResult to a DetectionResult
  factory DetectionResult.fromYOLOResult(YOLOResult result) {
    return DetectionResult(
      classIndex: result.classIndex,
      className: result.className,
      confidence: result.confidence,
      boundingBox: result.boundingBox,
      mask: result.mask,
      keypoints: result.keypoints,
    );
  }

  /// Convert a map to a DetectionResult
  factory DetectionResult.fromMap(Map<String, dynamic> map) {
    return DetectionResult(
      classIndex: map['classIndex'] as int,
      className: map['className'] as String,
      confidence: map['confidence'] as double,
      boundingBox: Rect.fromLTWH(
        map['boundingBox']['left'] as double,
        map['boundingBox']['top'] as double,
        map['boundingBox']['width'] as double,
        map['boundingBox']['height'] as double,
      ),
      // Optionally parse mask and keypoints if they exist
    );
  }

  /// Convert a DetectionResult to a map
  Map<String, dynamic> toMap() {
    return {
      'classIndex': classIndex,
      'className': className,
      'confidence': confidence,
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'width': boundingBox.width,
        'height': boundingBox.height,
      },
      // Optionally include mask and keypoints if they exist
    };
  }

  @override
  String toString() {
    return '$className (${(confidence * 100).toStringAsFixed(1)}%) at $boundingBox';
  }
}
