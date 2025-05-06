import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

class CameraService {
  final List<CameraDescription> cameras;

  CameraService(this.cameras);

  Future<CameraController> initializeCamera(
      {CameraLensDirection preferredDirection = CameraLensDirection.front,
      ResolutionPreset resolution = ResolutionPreset.medium}) async {
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    // Try to find the preferred camera direction
    final camera = cameras.firstWhere(
      (camera) => camera.lensDirection == preferredDirection,
      orElse: () => cameras[0],
    );

    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      return controller;
    } catch (e) {
      debugPrint('Failed to initialize camera: $e');
      rethrow;
    }
  }
}
