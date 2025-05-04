import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:open_rtms/providers/face_detection_provider.dart';
import 'package:open_rtms/widgets/face_detection_overlay.dart';
import 'package:open_rtms/services/camera_service.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen>
    with WidgetsBindingObserver {
  late CameraController _cameraController;
  bool _isInitialized = false;
  bool _isProcessing = false;
  CameraLensDirection _currentDirection = CameraLensDirection.back;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final cameraService = Provider.of<CameraService>(context, listen: false);
    _initCamera(cameraService);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed - handle camera resource properly
    if (state == AppLifecycleState.inactive) {
      _cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController.value.isInitialized) {
        final cameraService =
            Provider.of<CameraService>(context, listen: false);
        _initCamera(cameraService);
      }
    }
  }

  Future<void> _initCamera(CameraService cameraService) async {
    setState(() {
      _isInitialized = false; // Show loading indicator while switching
    });

    try {
      _cameraController =
          await cameraService.initializeCamera(_currentDirection);

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      final detectionProvider =
          Provider.of<FaceDetectionProvider>(context, listen: false);
      await detectionProvider.loadModel();

      await _cameraController.startImageStream((image) {
        if (!_isProcessing) {
          _isProcessing = true;
          detectionProvider.processCameraImage(image).then((_) {
            _isProcessing = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      // Handle error gracefully
      setState(() {
        _isInitialized = true; // Still show UI even if camera fails
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: ${e.toString()}')),
      );
    }
  }

  Future<void> _toggleCamera() async {
    // Stop processing and streaming
    _isProcessing = true;
    await _cameraController.stopImageStream();
    await _cameraController.dispose();

    // Toggle direction
    _currentDirection = _currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // Reinitialize camera
    final cameraService = Provider.of<CameraService>(context, listen: false);
    await _initCamera(cameraService);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recognition Mode')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing camera...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognition Mode'),
        actions: [
          Consumer<FaceDetectionProvider>(
            builder: (context, provider, child) {
              final presentStudents = provider.recognizedStudents.values
                  .where((student) => student['student_id'] != null)
                  .toList();

              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.people),
                      const SizedBox(width: 4),
                      Text(
                        '${presentStudents.length} Present',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AspectRatio(
            aspectRatio: _cameraController.value.aspectRatio,
            child: CameraPreview(_cameraController),
          ),
          Consumer<FaceDetectionProvider>(
            builder: (context, provider, child) {
              return FaceDetectionOverlay(
                detections: provider.detections,
                recognizedStudents: provider.recognizedStudents,
                previewSize: Size(
                  _cameraController.value.previewSize!.height,
                  _cameraController.value.previewSize!.width,
                ),
                screenSize: MediaQuery.of(context).size,
              );
            },
          ),
          // Attendance summary panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.all(8),
              child: Consumer<FaceDetectionProvider>(
                builder: (context, provider, child) {
                  final presentStudents = provider.recognizedStudents.values
                      .where((student) => student['student_id'] != null)
                      .toList();

                  if (presentStudents.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'No students recognized yet',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        child: Text(
                          'Present Students',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: presentStudents.length,
                          itemBuilder: (context, index) {
                            final student = presentStudents[index];
                            return Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Container(
                                width: 120,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.green.withOpacity(0.3),
                                  border: Border.all(color: Colors.green),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'ID: ${student['student_id']}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Add camera toggle button
          FloatingActionButton(
            heroTag:
                'toggleCamera', // Needed to avoid duplicate hero tag errors
            onPressed: _toggleCamera,
            tooltip: 'Switch Camera',
            backgroundColor: Colors.blue,
            child: Icon(_currentDirection == CameraLensDirection.back
                ? Icons.camera_front
                : Icons.camera_rear),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              final provider =
                  Provider.of<FaceDetectionProvider>(context, listen: false);
              provider.resetAttendance();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Attendance data reset')),
              );
            },
            tooltip: 'Reset Attendance',
            backgroundColor: Colors.red,
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 100), // Add space for the attendance panel
        ],
      ),
    );
  }
}
