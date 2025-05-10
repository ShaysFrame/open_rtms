import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

/// Utilities for image processing and handling
class ImageUtils {
  /// Convert an XFile to Uint8List bytes
  static Future<Uint8List> xFileToBytes(XFile file) async {
    return await file.readAsBytes();
  }

  /// Resize an image to the specified dimensions
  static Future<Uint8List> resizeImage(
      Uint8List bytes, int width, int height) async {
    // This is a placeholder implementation
    // In a real app, we'd use image processing libraries to resize the image
    return bytes;
  }

  /// Create an annotated image with bounding boxes
  static Future<Uint8List> drawBoundingBoxes(
      Uint8List imageBytes, List<Map<String, dynamic>> detections) async {
    // In a real implementation, we'd draw the bounding boxes on the image
    // For now, we'll just return the original image
    return imageBytes;
  }

  /// Crop a region from an image given bounding box coordinates
  /// bbox: [left, top, width, height] in pixel values
  static Future<Uint8List> cropImage(Uint8List imageBytes, Rect bbox) async {
    final original = img.decodeImage(imageBytes);
    if (original == null) throw Exception('Failed to decode image');
    final crop = img.copyCrop(
      original,
      x: bbox.left.toInt(),
      y: bbox.top.toInt(),
      width: bbox.width.toInt(),
      height: bbox.height.toInt(),
    );
    return Uint8List.fromList(img.encodeJpg(crop));
  }

  /// Pick an image from gallery
  static Future<XFile?> pickImageFromGallery() async {
    final picker = ImagePicker();
    return await picker.pickImage(source: ImageSource.gallery);
  }

  /// Pick an image from camera
  static Future<XFile?> pickImageFromCamera() async {
    final picker = ImagePicker();
    return await picker.pickImage(source: ImageSource.camera);
  }
}
