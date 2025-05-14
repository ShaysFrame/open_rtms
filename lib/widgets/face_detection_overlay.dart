import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class FaceDetectionOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> detections;
  final Map<String, Map<String, dynamic>> recognizedStudents;
  final Size previewSize;
  final Size screenSize;
  final bool isFrontCamera;

  const FaceDetectionOverlay({
    super.key,
    required this.detections,
    required this.recognizedStudents,
    required this.previewSize,
    required this.screenSize,
    this.isFrontCamera = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: screenSize,
      painter: FaceDetectionPainter(
        detections: detections,
        recognizedStudents: recognizedStudents,
        previewSize: previewSize,
        screenSize: screenSize,
      ),
    );
  }
}

class FaceDetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final Map<String, Map<String, dynamic>> recognizedStudents;
  final Size previewSize;
  final Size screenSize;

  FaceDetectionPainter({
    required this.detections,
    required this.recognizedStudents,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Print debug info
    debugPrint("📱 Painting overlay with ${detections.length} detections");
    debugPrint("📱 Preview size: ${previewSize.width}x${previewSize.height}");
    debugPrint("📱 Screen size: ${screenSize.width}x${screenSize.height}");

    if (detections.isEmpty) return;

    // Calculate scale factors between camera and display coordinates
    // This is similar to the YOLO example code you shared
    final double scaleX = screenSize.width / previewSize.width;
    final double scaleY = screenSize.height / previewSize.height;

    debugPrint("📱 Scale factors: $scaleX, $scaleY");

    final Paint recognizedBoxPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint unknownBoxPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      background: Paint()..color = Colors.black.withOpacity(0.6),
    );

    for (final detection in detections) {
      // Get box coordinates (x, y, w, h)
      final double x = detection['box'][0] as double;
      final double y = detection['box'][1] as double;
      final double w = detection['box'][2] as double;
      final double h = detection['box'][3] as double;

      // Scale the coordinates to the screen size
      final double scaledX = x * scaleX;
      final double scaledY = y * scaleY;
      final double scaledW = w * scaleX;
      final double scaledH = h * scaleY;

      // Create the rectangle
      final Rect rect = Rect.fromLTWH(scaledX, scaledY, scaledW, scaledH);

      // Check if this face is recognized
      final detectionId = "${detection['box'][0]}_${detection['box'][1]}";
      final studentInfo = recognizedStudents[detectionId];
      final bool isRecognized =
          studentInfo != null && studentInfo['student_id'] != null;

      // Draw the detection box
      canvas.drawRect(
        rect,
        isRecognized ? recognizedBoxPaint : unknownBoxPaint,
      );

      // Draw name label if recognized
      if (isRecognized) {
        final textSpan = TextSpan(
          text: " ${studentInfo!['name']} ",
          style: textStyle,
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(minWidth: 0, maxWidth: 200);

        // Position the text above the box
        textPainter.paint(
          canvas,
          Offset(scaledX, scaledY - textPainter.height - 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return detections != oldDelegate.detections ||
        recognizedStudents != oldDelegate.recognizedStudents;
  }
}
