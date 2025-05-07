import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:open_rtms/providers/face_detection_provider.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

// In your RecognitionScreen
class _RecognitionScreenState extends State<RecognitionScreen> {
  late CameraController _cameraController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Get available cameras
    final cameras = await availableCameras();

    // Use the first camera (usually the back camera)
    final camera = cameras.first;

    // Initialize controller
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // Initialize the controller
    await _cameraController.initialize();

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });

      // Start processing frames when camera is ready
      final provider =
          Provider.of<FaceDetectionProvider>(context, listen: false);
      provider.startProcessing(_cameraController);
    }
  }

  late FaceDetectionProvider _faceDetectionProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _faceDetectionProvider =
        Provider.of<FaceDetectionProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _faceDetectionProvider.stopProcessing();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Camera preview
          Expanded(
            child: Stack(
              children: [
                // Camera preview
                _isInitialized
                    ? CameraPreview(_cameraController)
                    : const Center(child: CircularProgressIndicator()),

                // Face boxes overlay
                Consumer<FaceDetectionProvider>(
                  builder: (context, provider, _) {
                    return CustomPaint(
                      painter: FaceBoxesPainter(
                        provider.faceBoxes,
                        provider.recognizedStudents,
                      ),
                      size: Size.infinite,
                    );
                  },
                ),

                // Statistics overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Consumer<FaceDetectionProvider>(
                    builder: (context, provider, _) {
                      return Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Faces: ${provider.totalFacesDetected} | '
                          'Recognized: ${provider.totalRecognizedStudents}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scanClassroomFab',
        onPressed: () {
          final provider =
              Provider.of<FaceDetectionProvider>(context, listen: false);
          provider.scanClassroom(_cameraController);
        },
        icon: const Icon(Icons.groups_rounded),
        label: const Text('Scan Class'),
      ),
    );
  }
}

// Painter for face boxes
class FaceBoxesPainter extends CustomPainter {
  final List<Map<String, dynamic>> faceBoxes;
  final Map<String, Map<String, dynamic>> recognizedStudents;

  FaceBoxesPainter(this.faceBoxes, this.recognizedStudents);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      backgroundColor: Colors.black54,
    );

    for (final box in faceBoxes) {
      final faceRect = Rect.fromLTWH(
        box['box'][0].toDouble(),
        box['box'][1].toDouble(),
        box['box'][2].toDouble(),
        box['box'][3].toDouble(),
      );

      // Draw rectangle around face
      canvas.drawRect(faceRect, paint);

      // Find if this face is recognized
      final faceIndex = box['face_index'];
      String? name;

      for (final student in recognizedStudents.values) {
        if (student['face_index'] == faceIndex) {
          name = student['name'];
          break;
        }
      }

      // Draw name if recognized
      if (name != null) {
        final textSpan = TextSpan(text: name, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(faceRect.left, faceRect.bottom + 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
