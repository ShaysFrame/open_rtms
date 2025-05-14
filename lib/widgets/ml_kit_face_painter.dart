import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class MLKitFacePainter extends CustomPainter {
  final File? imageFile;
  final ui.Image? uiImage; // Add UI Image property
  final List<Face> faces;
  final Size imageSize;
  final Map<String, Map<String, dynamic>> recognizedStudents;

  MLKitFacePainter({
    required this.imageFile,
    this.uiImage, // Make it optional
    required this.faces,
    required this.imageSize,
    required this.recognizedStudents,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Only return if we have no image at all
    if (imageFile == null && uiImage == null) return;

    // Calculate aspect ratios
    final double imageAspectRatio = imageSize.width / imageSize.height;
    final double containerAspectRatio = size.width / size.height;

    // Scale factors and offsets for drawing
    Size displayedImageSize;
    double scaleX, scaleY;
    double offsetX = 0, offsetY = 0;

    // Determine how to scale the image to fit the canvas (BoxFit.contain logic)
    if (imageAspectRatio > containerAspectRatio) {
      // Image is wider than container - width constrained
      displayedImageSize = Size(size.width, size.width / imageAspectRatio);
      scaleX = displayedImageSize.width / imageSize.width;
      scaleY = scaleX; // Keep aspect ratio
      offsetY = 0; // Align to top
    } else {
      // Image is taller than container - height constrained
      displayedImageSize = Size(size.height * imageAspectRatio, size.height);
      scaleY = displayedImageSize.height / imageSize.height;
      scaleX = scaleY; // Keep aspect ratio
      offsetX =
          (size.width - displayedImageSize.width) / 2; // Center horizontally
    }

    // Draw the image on the canvas if available
    if (uiImage != null) {
      debugPrint(
          "📱 Drawing UI Image on canvas: ${imageSize.width}x${imageSize.height}");
      debugPrint(
          "📱 Display size: ${displayedImageSize.width}x${displayedImageSize.height}");
      debugPrint("📱 Drawing at offset: ($offsetX, $offsetY)");

      final paint = Paint();
      final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      final dst = Rect.fromLTWH(offsetX, offsetY, displayedImageSize.width,
          displayedImageSize.height);
      canvas.drawImageRect(uiImage!, src, dst, paint);
    }

    debugPrint(
        "📱 ML Kit Painter - Image size: ${imageSize.width}x${imageSize.height}, Display size: ${size.width}x${size.height}");
    debugPrint(
        "📱 ML Kit Painter - Scale factors: X=$scaleX, Y=$scaleY, Offsets: X=$offsetX, Y=$offsetY");

    // If we don't have any faces to draw, we're done after drawing the image
    if (faces.isEmpty) return;

    // Paints for face detection boxes
    final Paint recognizedBoxPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint unknownBoxPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Text style for names
    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      background: Paint()..color = Colors.black.withOpacity(0.6),
    );

    for (final face in faces) {
      // Get face bounding box and scale it
      final Rect faceRect = face.boundingBox;
      final scaledRect = Rect.fromLTWH(
        (faceRect.left * scaleX) + offsetX,
        (faceRect.top * scaleY) + offsetY,
        faceRect.width * scaleX,
        faceRect.height * scaleY,
      );

      // Generate unique ID for this face based on position
      final String faceId = "${faceRect.left.toInt()}_${faceRect.top.toInt()}";

      // Debug log to help diagnose recognition mapping
      debugPrint(
          "📱 Painter looking for face ID: $faceId in ${recognizedStudents.keys}");

      // Check if this face is recognized
      Map<String, dynamic>? studentInfo = recognizedStudents[faceId];
      bool isRecognized = false;

      if (studentInfo != null && studentInfo['student_id'] != null) {
        isRecognized = true;
      }

      // Draw the detection box
      canvas.drawRect(
        scaledRect,
        isRecognized ? recognizedBoxPaint : unknownBoxPaint,
      );

      // Draw landmarks if available
      if (face.landmarks.isNotEmpty) {
        final Paint landmarkPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill
          ..strokeWidth = 3.0;

        for (final landmark in face.landmarks.values) {
          canvas.drawCircle(
            Offset(
              (landmark!.position.x * scaleX) + offsetX,
              (landmark.position.y * scaleY) + offsetY,
            ),
            2.0,
            landmarkPaint,
          );
        }
      }

      // Draw name label if recognized
      if (isRecognized && studentInfo != null) {
        final textSpan = TextSpan(
          text: " ${studentInfo['name']} ",
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
          Offset(scaledRect.left, scaledRect.top - textPainter.height - 5),
        );
      }

      // Draw confidence score if recognition is available
      if (isRecognized &&
          studentInfo != null &&
          studentInfo['confidence'] != null) {
        final double confidence = studentInfo['confidence'];
        final confidenceText = "${(confidence * 100).toInt()}%";

        final textSpan = TextSpan(
          text: confidenceText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.normal,
            background: Paint()..color = Colors.black.withOpacity(0.6),
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(minWidth: 0, maxWidth: 200);

        // Position below the name
        textPainter.paint(
          canvas,
          Offset(scaledRect.left, scaledRect.top - 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(MLKitFacePainter oldDelegate) {
    return oldDelegate.imageFile != imageFile ||
        oldDelegate.uiImage != uiImage ||
        oldDelegate.faces != faces ||
        oldDelegate.recognizedStudents != recognizedStudents;
  }
}
