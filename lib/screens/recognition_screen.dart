import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:open_rtms/providers/face_detection_provider.dart';
import 'package:open_rtms/widgets/face_detection_overlay.dart';
import 'package:open_rtms/services/camera_service.dart';
// ML Kit imports
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:open_rtms/screens/fixed_recognition_helper.dart';

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
  bool _recognitionActive = true; // Start with recognition active

  // Zoom level state
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;

  // Add ML Kit Face Detector
  late FaceDetector _faceDetector;

  // Use the helper class for optimal face detector options
  final FaceDetectorOptions _faceDetectorOptions =
      MLKitHelper.getOptimalFaceDetectorOptions();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize ML Kit face detector
    _faceDetector = FaceDetector(options: _faceDetectorOptions);

    // Get camera service
    final cameraService = Provider.of<CameraService>(context, listen: false);
    _initCamera(cameraService);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      _isInitialized = false;
    });

    try {
      _cameraController = await cameraService.initializeCamera(
        preferredDirection: _currentDirection,
        resolution: ResolutionPreset.high,
      );

      if (!mounted) return;

      // Get min and max zoom levels after camera is initialized
      _minZoomLevel = await _cameraController.getMinZoomLevel();
      _maxZoomLevel = await _cameraController.getMaxZoomLevel();
      // Set current zoom to min initially or ensure it's within bounds
      _currentZoomLevel = _minZoomLevel;
      await _cameraController.setZoomLevel(_currentZoomLevel);

      setState(() {
        _isInitialized = true;
      });

      final detectionProvider =
          Provider.of<FaceDetectionProvider>(context, listen: false);
      await detectionProvider.loadModel();

      await _cameraController.startImageStream((image) {
        if (!_isProcessing) {
          _processCameraImage(image);
        }
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      // Handle error gracefully
      setState(() {
        _isInitialized = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: ${e.toString()}')),
      );
    }
  }

  Future<void> _toggleCamera() async {
    // Stop processing first
    _isProcessing = true;

    // Add safety checks before stopping the stream
    if (_cameraController.value.isInitialized &&
        !_cameraController.value.isStreamingImages) {
      try {
        await _cameraController.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping image stream: $e');
        // Continue with disposal anyway
      }
    }

    try {
      await _cameraController.dispose();
    } catch (e) {
      debugPrint('Error disposing camera: $e');
      // Continue with reinitialization anyway
    }

    // Toggle direction
    _currentDirection = _currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // Reinitialize camera
    final cameraService = Provider.of<CameraService>(context, listen: false);
    await _initCamera(cameraService);
  }

  Future<void> _toggleRecognition() async {
    setState(() {
      _recognitionActive = !_recognitionActive;
    });

    if (_recognitionActive) {
      // Resume processing
      await _cameraController.startImageStream((image) {
        if (!_isProcessing) {
          _processCameraImage(image);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Face recognition started'),
            duration: Duration(seconds: 1)),
      );
    } else {
      // Pause processing
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Face recognition paused'),
            duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController.dispose();
    _faceDetector.close(); // Close ML Kit face detector
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Recognition Mode'),
          foregroundColor: Colors.white,
        ),
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

    // Calculate proper dimensions for FaceDetectionOverlay
    final cameraSize = _cameraController.value.previewSize!;

// Calculate AspectRatio for the camera container
    final cameraAspectRatio = cameraSize.height / cameraSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Recognition Mode',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Consumer<FaceDetectionProvider>(
            builder: (context, provider, child) {
              final presentStudents = provider.recognizedStudents.values
                  .where((student) => student['student_id'] != null)
                  .toList();

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '${presentStudents.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Camera Container with border like registration screen
                Center(
                  child: Container(
                    // height: containerSize.height,
                    // width: containerSize.width * (4 / 3),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade800, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio:
                            cameraAspectRatio, // Fixed aspect ratio for container
                        child: Stack(
                          fit: StackFit
                              .expand, // Keep this to ensure overlay covers camera
                          children: [
                            // Camera preview
                            CameraPreview(_cameraController),

                            // Debug outline to see actual area
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                    width: 1),
                              ),
                            ),

                            // Overlay for face detection with improved parameters
                            Consumer<FaceDetectionProvider>(
                              builder: (context, provider, child) {
                                // Debug information about detections
                                if (provider.detections.isNotEmpty) {
                                  debugPrint(
                                      "📱 Detections found: ${provider.detections.length}");
                                  debugPrint(
                                      "📱 First detection: ${provider.detections.first}");
                                }

                                // Create a fixed size for the container
                                final containerWidth =
                                    MediaQuery.of(context).size.width -
                                        32; // Full width minus margins
                                final containerHeight = containerWidth *
                                    (4 / 3); // Using 3:4 aspect ratio

                                // Camera image size
                                final cameraSize =
                                    _cameraController.value.previewSize!;

                                return FaceDetectionOverlay(
                                  detections: provider.detections,
                                  recognizedStudents:
                                      provider.recognizedStudents,
                                  // Use the actual camera dimensions (not swapped)
                                  previewSize:
                                      Size(cameraSize.width, cameraSize.height),
                                  // Use the container dimensions for screen size
                                  screenSize:
                                      Size(containerWidth, containerHeight),
                                );
                              },
                            ),

                            // Optional gradient overlay for better visibility
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.2),
                                    Colors.transparent,
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Add this positioned widget in your Stack
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: Consumer<FaceDetectionProvider>(
                    builder: (context, provider, child) {
                      return FloatingActionButton.extended(
                        heroTag: 'scanClassroomFab',
                        onPressed: provider.isBatchProcessing
                            ? null
                            : () async {
                                // Show explanation dialog
                                final proceed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Scan Classroom'),
                                        content: const Text(
                                          'This will capture a single high-resolution photo of the '
                                          'entire classroom and attempt to recognize all students at once.\n\n'
                                          'For best results, make sure all students are visible and facing the camera.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context)
                                                    .pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text('Proceed'),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false;

                                if (proceed) {
                                  await provider
                                      .scanClassroom(_cameraController);
                                }
                              },
                        icon: provider.isBatchProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.groups_rounded),
                        label: Text(provider.isBatchProcessing
                            ? 'Scanning...'
                            : 'Scan Class'),
                        backgroundColor: Colors.orange.shade700,
                      );
                    },
                  ),
                ),

                // Add progress indicator at the top
                if (_isInitialized)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Consumer<FaceDetectionProvider>(
                      builder: (context, provider, child) {
                        // Only show when faces are detected
                        if (provider.totalFacesDetected == 0)
                          return const SizedBox.shrink();

                        final int detected = provider.totalFacesDetected;
                        final int recognized = provider.totalFacesRecognized;
                        final double progress =
                            detected > 0 ? recognized / detected : 0;

                        return Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Recognition Progress: $recognized/$detected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (provider.isBatchProcessing)
                                    Text(
                                      '${(provider.batchProgress * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: provider.isBatchProcessing
                                    ? provider.batchProgress
                                    : progress,
                                backgroundColor: Colors.grey.shade800,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Camera toggle button (now as overlay on camera)
                Positioned(
                  top: 24,
                  right: 24,
                  child: FloatingActionButton.small(
                    heroTag: 'cameraToggleFab',
                    onPressed: _toggleCamera,
                    backgroundColor: Colors.black.withOpacity(0.6),
                    child: Icon(
                      _currentDirection == CameraLensDirection.back
                          ? Icons.camera_front
                          : Icons.camera_rear,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Add this inside the Stack, as a sibling to the Scan Classroom FAB
                Positioned(
                  bottom: 24,
                  left: 24,
                  child: FloatingActionButton(
                    heroTag: 'toggleRecognitionFab',
                    onPressed: _toggleRecognition,
                    backgroundColor:
                        _recognitionActive ? Colors.red : Colors.green,
                    child: Icon(
                      _recognitionActive ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Zoom Slider
                if (_isInitialized && _maxZoomLevel > _minZoomLevel)
                  Positioned(
                    bottom: 90, // Adjust position as needed
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.zoom_out, color: Colors.white),
                          Expanded(
                            child: Slider(
                              value: _currentZoomLevel,
                              min: _minZoomLevel,
                              max: _maxZoomLevel,
                              activeColor: Colors.white,
                              inactiveColor: Colors.white30,
                              onChanged: (value) async {
                                setState(() {
                                  _currentZoomLevel = value;
                                });
                                await _cameraController.setZoomLevel(value);
                              },
                            ),
                          ),
                          const Icon(Icons.zoom_in, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Attendance summary panel
          Consumer<FaceDetectionProvider>(
            builder: (context, provider, child) {
              final presentStudents = provider.recognizedStudents.values
                  .where((student) => student['student_id'] != null)
                  .toList();

              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recognized Students',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh,
                                color: Colors.white70),
                            onPressed: () {
                              provider.resetAttendance();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Attendance data reset'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            tooltip: 'Reset Attendance',
                          ),
                        ],
                      ),
                    ),
                    if (presentStudents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(
                          child: Text(
                            'No students recognized yet',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: presentStudents.length,
                          itemBuilder: (context, index) {
                            final student = presentStudents[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: Container(
                                width: 140,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.green.shade800,
                                      Colors.green.shade900,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            student['name'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: ${student['student_id']}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.timer,
                                          color: Colors.white.withOpacity(0.7),
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            _formatTime(student['timestamp']),
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.7),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inHours}h ${difference.inMinutes % 60}m ago';
      }
    } catch (e) {
      return 'Just now';
    }
  }

  // Process camera frames with ML Kit face detection
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Convert camera image to ML Kit format
      final inputImage = MLKitHelper.cameraImageToInputImage(
          image, _cameraController.description);

      if (inputImage == null) {
        debugPrint("🚦 Input image is null, skipping processing.");
        _isProcessing = false;
        return;
      }

      debugPrint("🚦 Processing image with ML Kit Face Detector...");
      try {
        final List<Face> faces = await _faceDetector.processImage(inputImage);
        debugPrint(
            "🚦 ML Kit detected ${faces.length} faces."); // <-- ADDED THIS LINE

        if (faces.isNotEmpty) {
          debugPrint("🚦 Detected face details:");
        }

        if (faces.isEmpty) {
          _isProcessing = false;
          return;
        }

        // We just need to convert faces to detections for the provider
        // No need to store the ML Kit faces separately

        // Get detection provider
        final detectionProvider =
            Provider.of<FaceDetectionProvider>(context, listen: false);

        // Convert ML Kit faces to provider format
        List<Map<String, dynamic>> detections = [];
        Map<String, Map<String, dynamic>> mlKitFaceIds = {};

        for (final face in faces) {
          // Convert ML Kit face to provider format
          final detection = MLKitHelper.mlKitToProviderFormat(face);

          if (detection.isEmpty) continue; // Skip invalid faces

          // Add to detections list
          detections.add(detection);

          // Create unique face ID
          final faceId = MLKitHelper.createFaceId(face);

          // Create placeholder entries for faces without recognition data
          if (!detectionProvider.recognizedStudents.containsKey(faceId) ||
              detectionProvider.recognizedStudents[faceId]?['student_id'] ==
                  null) {
            mlKitFaceIds[faceId] = {
              'name': 'Detecting...',
              'student_id': null,
              'confidence': 0.0,
              'timestamp': DateTime.now().toString(),
            };
          }
        }

        // Update provider with detections
        if (detections.isNotEmpty) {
          detectionProvider.updateDetections(detections);

          if (mlKitFaceIds.isNotEmpty) {
            detectionProvider.addPlaceholders(mlKitFaceIds);
          }

          // Process with backend
          try {
            await detectionProvider.processCameraImage(image);
          } catch (e) {
            debugPrint("📱 Error processing with backend: $e");
          }
        }

        // Update UI if needed
        if (mounted && faces.isNotEmpty) {
          setState(() {});
        }
      } catch (e) {
        debugPrint("📱 Error in ML Kit face detection: $e");
      } finally {
        _isProcessing = false;
      }
    } catch (e) {
      debugPrint("📱 Error in ML Kit face detection: $e");
    } finally {
      _isProcessing = false;
    }
  }
}
