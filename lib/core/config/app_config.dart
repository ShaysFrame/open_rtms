import 'package:flutter/foundation.dart';

/// Global configuration settings for the application
class AppConfig {
  /// Default confidence threshold for object detection
  static const double defaultConfidenceThreshold = 0.5;

  /// Default IoU threshold for object detection
  static const double defaultIouThreshold = 0.45;

  /// App name
  static const String appName = 'YOLO Attendance';

  /// Debug mode flag
  static final bool isDebugMode = kDebugMode;

  /// Toggles whether to show debugging information in the UI
  static const bool showDebugInfo = true;

  /// Face recognition settings
  static const double faceMatchThreshold =
      0.7; // Minimum confidence for a face match

  /// Attendance settings
  static const Duration attendanceValidDuration =
      Duration(hours: 8); // How long an attendance record is valid
}
