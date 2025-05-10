import 'package:permission_handler/permission_handler.dart';

class CameraService {
  /// Check if the app has camera permission
  static Future<bool> hasCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  /// Request camera permission
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Ensure the app has camera permission, requesting if necessary
  static Future<bool> ensureCameraPermission() async {
    if (await hasCameraPermission()) {
      return true;
    }
    return await requestCameraPermission();
  }
}
