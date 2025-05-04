import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class FaceDetectionOverlay extends StatelessWidget {
  final List<Map<String, dynamic>> detections;
  final Map<String, Map<String, dynamic>> recognizedStudents;
  final Size previewSize;
  final Size screenSize;

  const FaceDetectionOverlay({
    super.key,
    required this.detections,
    required this.recognizedStudents,
    required this.previewSize,
    required this.screenSize,
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
    final double scaleX = screenSize.width / previewSize.width;
    final double scaleY = screenSize.height / previewSize.height;

    final Paint unknownBoxPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint recognizedBoxPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    for (final detection in detections) {
      final x = (detection['box'][0] as double) * scaleX;
      final y = (detection['box'][1] as double) * scaleY;
      final w = (detection['box'][2] as double) * scaleX;
      final h = (detection['box'][3] as double) * scaleY;

      final rect = Rect.fromLTWH(x, y, w, h);
      final detectionId = "${detection['box'][0]}_${detection['box'][1]}";
      final studentInfo = recognizedStudents[detectionId];
      final bool isRecognized =
          studentInfo != null && studentInfo['student_id'] != null;

      // Draw the bounding box
      canvas.drawRect(
        rect,
        isRecognized ? recognizedBoxPaint : unknownBoxPaint,
      );

      // Draw a background for the text
      if (studentInfo != null) {
        final studentName = studentInfo['name'] ?? 'Unknown';
        final confidence = studentInfo['confidence'] != null
            ? (studentInfo['confidence'] * 100).toInt().toString() + '%'
            : '';
        final studentId = studentInfo['student_id'] ?? '';

        final displayText =
            isRecognized ? '$studentName ($studentId) $confidence' : 'Unknown';

        final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.left,
          maxLines: 2,
          ellipsis: '...',
        ))
          ..pushStyle(ui.TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ))
          ..addText(displayText);

        final paragraph = paragraphBuilder.build()
          ..layout(ui.ParagraphConstraints(width: w));

        final textHeight = isRecognized ? 40.0 : 24.0;
        final textRect = Rect.fromLTWH(x, y - textHeight, w, textHeight);
        canvas.drawRect(textRect, backgroundPaint);
        canvas.drawParagraph(paragraph, Offset(x + 5, y - textHeight + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
