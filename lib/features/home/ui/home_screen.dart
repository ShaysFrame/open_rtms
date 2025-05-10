import 'package:flutter/material.dart';
import '../../object_detection/ui/camera_screen.dart';
import '../../object_detection/ui/image_screen.dart';
import '../../../core/services/camera_service.dart';
import '../../../core/config/app_config.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.appName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to ${AppConfig.appName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a feature to begin:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            // Grid of feature cards
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                // padding: const EdgeInsets.all(8),
                children: [
                  _buildFeatureCard(
                    context,
                    'Object Detection',
                    'Camera feed detection',
                    Icons.camera_alt,
                    Colors.blue,
                    () => _navigateToCameraScreen(context),
                  ),
                  _buildFeatureCard(
                    context,
                    'Image Detection',
                    'Analyze from gallery',
                    Icons.image,
                    Colors.green,
                    () => _navigateToImageScreen(context),
                  ),
                  // _buildFeatureCard(
                  //   context,
                  //   'Face Recognition',
                  //   'Identify faces',
                  //   Icons.face,
                  //   Colors.purple,
                  //   () => _navigateToFaceScreen(context),
                  // ),
                ],
              ),
            ),

            // Version info and copyright
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                '© 2025 - YOLO Attendance',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToCameraScreen(BuildContext context) async {
    final hasPermission = await CameraService.ensureCameraPermission();
    if (hasPermission) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required for this feature'),
        ),
      );
    }
  }

  Future<void> _navigateToImageScreen(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ImageScreen()),
    );
  }

  // Future<void> _navigateToFaceScreen(BuildContext context) async {
  //   final hasPermission = await CameraService.ensureCameraPermission();
  //   if (hasPermission) {
  //     Navigator.push(
  //       context,
  //       MaterialPageRoute(builder: (context) => const FaceScreen()),
  //     );
  //   } else {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Camera permission is required for this feature'),
  //       ),
  //     );
  //   }
  // }
}
