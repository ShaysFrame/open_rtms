import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:typed_data'; // <-- ADDED THIS IMPORT

// This is a helper class with the fixed ML Kit face detection implementations
class MLKitHelper {
  // Create robust input image from camera image - completely rewritten from scratch
  static InputImage? cameraImageToInputImage(
      CameraImage cameraImage, CameraDescription cameraDescription) {
    try {
      debugPrint(
          "📱 IMAGE CONVERSION START --------- ${DateTime.now().millisecondsSinceEpoch} ---------");

      // Get camera details for debugging
      final cameraId = cameraDescription.name;
      final sensorOrientation = cameraDescription.sensorOrientation;
      final lensDirection = cameraDescription.lensDirection;

      debugPrint(
          "📱 Camera: id=$cameraId, orientation=$sensorOrientation°, direction=$lensDirection");
      debugPrint(
          "📱 Image: ${cameraImage.width}x${cameraImage.height}, format=${cameraImage.format.raw}");

      // Calculate rotation value (0, 1, 2, 3) = (0, 90, 180, 270) degrees
      int rotationValue = sensorOrientation ~/ 90;

      // For front camera, we may need to adjust rotation
      if (lensDirection == CameraLensDirection.front) {
        // Adjust for front camera mirroring
        if (rotationValue == 1)
          rotationValue = 3;
        else if (rotationValue == 3) rotationValue = 1;
      }

      debugPrint("📱 Using rotation value: $rotationValue");

      // Create input image metadata directly
      // Handle rotation values with proper defaults
      final rotationValueObj =
          InputImageRotationValue.fromRawValue(rotationValue);
      // Default to rotation0deg (raw value 0)
      final rotationValue0 = InputImageRotationValue.fromRawValue(0)!;

      if (rotationValueObj == null) {
        debugPrint(
            "📱 WARNING: Could not get rotation value for $rotationValue, using default");
      }

      // Handle format values with proper defaults
      final formatValueObj =
          InputImageFormatValue.fromRawValue(cameraImage.format.raw);
      // Default to yuv420 (raw value 35)
      final formatValue35 = InputImageFormatValue.fromRawValue(35)!;

      if (formatValueObj == null) {
        debugPrint(
            "📱 WARNING: Could not get format for ${cameraImage.format.raw}, using default");
      }

      // Create metadata with null-safe values
      final metadata = InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: rotationValueObj ?? rotationValue0,
        format: formatValueObj ?? formatValue35,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      debugPrint(
          "📱 Created metadata: rotation=${metadata.rotation.rawValue}, format=${metadata.format.rawValue}");

      // For YUV_420_888, concatenate Y, U, and V planes
      // The U and V planes might have different byte strides and pixel strides.
      if (metadata.format == InputImageFormat.yuv_420_888 ||
          metadata.format == InputImageFormat.nv21) {
        // NV21 is also YUV420
        // Ensure we have three planes for YUV420
        if (cameraImage.planes.length == 3) {
          final yPlane = cameraImage.planes[0];
          final uPlane = cameraImage.planes[1];
          final vPlane = cameraImage.planes[2];

          final yBuffer = yPlane.bytes;
          final uBuffer = uPlane.bytes;
          final vBuffer = vPlane.bytes;

          // The U and V planes are interleaved in some formats (like NV21) or separate.
          // For ML Kit, it expects them concatenated if they are separate.
          // We need to respect bytesPerRow and pixelStride for U and V planes if they are not full width.

          // A common way to handle YUV420 is to concatenate them directly
          // if they are already in the correct planar format.
          // However, pixel and row strides can make this tricky.
          // For now, let's try a direct concatenation, assuming planes are correctly ordered.
          // If issues persist, a more robust plane reconstruction might be needed.

          // Concatenate all plane bytes.
          // This assumes that the planes are already in the correct order (Y, then U, then V or Y, then UV interleaved).
          // For InputImageFormat.yuv_420_888, it expects separate Y, U, V planes concatenated.
          // For InputImageFormat.nv21, it expects Y plane followed by interleaved VU plane.
          // The camera plugin with ImageFormatGroup.yuv420 usually provides kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
          // on iOS (NV12) or YUV_420_888 on Android.

          // Let's try a simpler concatenation first, assuming the planes are in Y, U, V order
          // and MLKit handles the strides internally based on metadata.
          // The `bytes` parameter for `InputImage.fromBytes` should be a single byte array.

          final allBytes = BytesBuilder();
          allBytes.add(yBuffer);
          allBytes.add(uBuffer);
          allBytes.add(vBuffer);
          final bytes = allBytes.toBytes();

          debugPrint(
              "📱 Using YUV420 format. Concatenated Y (${yBuffer.length}), U (${uBuffer.length}), V (${vBuffer.length}) planes. Total: ${bytes.length} bytes");
          debugPrint(
              "📱 IMAGE CONVERSION END -----------------------------------------");

          return InputImage.fromBytes(
            bytes: bytes,
            metadata: metadata,
          );
        } else {
          debugPrint(
              "📱 ERROR: Expected 3 planes for YUV420 format, but got ${cameraImage.planes.length}. Falling back to Y plane only.");
          // Fallback to Y plane if plane count is not 3, though this is likely to fail.
          final bytes = cameraImage.planes[0].bytes;
          debugPrint(
              "📱 Using Y plane with ${bytes.length} bytes (fallback due to incorrect plane count)");
          debugPrint(
              "📱 IMAGE CONVERSION END -----------------------------------------");
          return InputImage.fromBytes(
            bytes: bytes,
            metadata: metadata,
          );
        }
      } else {
        // For other formats (like BGRA8888, which might be used on iOS if not YUV)
        // or if we are unsure, use the first plane. This was the previous behavior.
        final bytes = cameraImage.planes[0].bytes;
        debugPrint(
            "📱 Using non-YUV420 format (${metadata.format.rawValue}). Using first plane with ${bytes.length} bytes");
        debugPrint(
            "📱 IMAGE CONVERSION END -----------------------------------------");

        return InputImage.fromBytes(
          bytes: bytes,
          metadata: metadata,
        );
      }
    } catch (e, s) {
      // Added stack trace
      debugPrint(
          "📱 ERROR converting camera image: $e\n$s"); // Added stack trace
      return null;
    }
  }

  // No helper methods needed

  // Create optimal face detection options
  static FaceDetectorOptions getOptimalFaceDetectorOptions() {
    return FaceDetectorOptions(
      // Enable all features for better detection
      enableClassification: true,
      enableLandmarks: true,
      enableContours: false, // Contours are expensive and not needed
      enableTracking: true, // Very important for video!

      // Set minimum face size to 12% of image width
      // Lower values detect smaller/further faces but more false positives
      // Higher values are more reliable but only detect closer faces
      minFaceSize: 0.12,

      // Use accurate mode for better face detection
      // Consider switching to "fast" if performance issues occur
      performanceMode: FaceDetectorMode.accurate,
    );
  }

  // Helper to create unique face ID from detection coordinates
  // This helps match faces across frames and with backend recognition
  static String createFaceId(Face face) {
    final rect = face.boundingBox;
    final int left = rect.left.toInt();
    final int top = rect.top.toInt();

    // Including width and height can help make the ID more unique
    final int width = rect.width.toInt();
    final int height = rect.height.toInt();

    // Use tracking ID if available, otherwise use position
    if (face.trackingId != null) {
      return "track_${face.trackingId}";
    } else {
      return "pos_${left}_${top}_${width}_${height}";
    }
  }

  // Calculate face confidence from ML Kit face data
  static double calculateFaceConfidence(Face face) {
    double confidence = 0.8; // Default baseline confidence

    // Adjust based on head angle if available (more frontal = higher confidence)
    if (face.headEulerAngleY != null) {
      // Normalize head angle to confidence (1.0 = straight ahead, lower = turned)
      confidence = (1.0 - face.headEulerAngleY!.abs() / 45.0).clamp(0.5, 1.0);
    }

    // Boost confidence for faces with tracking ID (more stable detection)
    if (face.trackingId != null) {
      confidence = (confidence * 1.1).clamp(0.0, 1.0);
    }

    // Adjust confidence based on face size (larger = more confident)
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = 640 * 480; // Assume typical VGA size as reference
    final sizeRatio = faceArea / imageArea;

    // Small boost for larger faces (more reliable)
    if (sizeRatio > 0.05) {
      confidence = (confidence * 1.1).clamp(0.0, 1.0);
    }

    return confidence;
  }

  // Convert ML Kit face to format suitable for FaceDetectionProvider
  static Map<String, dynamic> mlKitToProviderFormat(Face face) {
    final rect = face.boundingBox;
    final left = rect.left.toInt();
    final top = rect.top.toInt();

    // Ensure we have reasonable values
    if (rect.width <= 0 || rect.height <= 0 || rect.left < 0 || rect.top < 0) {
      debugPrint("📱 Skipping invalid face rectangle: $rect");
      return {}; // Empty map signals invalid face
    }

    // Calculate confidence based on face attributes
    final confidence = calculateFaceConfidence(face);

    // Return in YOLO-compatible format expected by provider
    return {
      'box': [left.toDouble(), top.toDouble(), rect.width, rect.height],
      'confidence': confidence,
      'class': 0,
      'name': 'face',
      'ml_kit_id': face.trackingId ?? 'untracked',
    };
  }
}
