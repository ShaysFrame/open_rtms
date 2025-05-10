import 'package:flutter/material.dart';
import '../../features/object_detection/models/detection_result.dart';

/// A widget that draws bounding boxes over detected objects
class DetectionOverlay extends StatelessWidget {
  final List<DetectionResult> detections;
  final Size imageSize;
  final bool showLabels;
  final bool showConfidence;
  final Color boxColor;
  final double lineWidth;
  final double minConfidence;

  const DetectionOverlay({
    Key? key,
    required this.detections,
    required this.imageSize,
    this.showLabels = true,
    this.showConfidence = true,
    this.boxColor = Colors.red,
    this.lineWidth = 2.0,
    this.minConfidence = 0.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: imageSize,
      painter: DetectionPainter(
        detections: detections
            .where((detection) => detection.confidence >= minConfidence)
            .toList(),
        imageSize: imageSize,
        showLabels: showLabels,
        showConfidence: showConfidence,
        boxColor: boxColor,
        lineWidth: lineWidth,
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size imageSize;
  final bool showLabels;
  final bool showConfidence;
  final Color boxColor;
  final double lineWidth;

  DetectionPainter({
    required this.detections,
    required this.imageSize,
    required this.showLabels,
    required this.showConfidence,
    required this.boxColor,
    required this.lineWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth;

    final Paint textBackgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (final detection in detections) {
      // Scale the bounding box to the canvas size
      final Rect scaledBox = Rect.fromLTWH(
        detection.boundingBox.left * scaleX,
        detection.boundingBox.top * scaleY,
        detection.boundingBox.width * scaleX,
        detection.boundingBox.height * scaleY,
      );

      // Draw the bounding box
      canvas.drawRect(scaledBox, paint);

      if (showLabels) {
        String label = detection.className;
        if (showConfidence) {
          label += ' ${(detection.confidence * 100).toStringAsFixed(0)}%';
        }

        final textSpan = TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 * scaleX.clamp(0.8, 1.5),
            fontWeight: FontWeight.bold,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        // Draw background for the text
        final textBackgroundRect = Rect.fromLTWH(
          scaledBox.left,
          scaledBox.top - textPainter.height - 4,
          textPainter.width + 8,
          textPainter.height + 4,
        );

        canvas.drawRect(textBackgroundRect, textBackgroundPaint);

        // Draw the label text
        textPainter.paint(
          canvas,
          Offset(scaledBox.left + 4, scaledBox.top - textPainter.height - 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showConfidence != showConfidence ||
        oldDelegate.boxColor != boxColor ||
        oldDelegate.lineWidth != lineWidth;
  }
}
