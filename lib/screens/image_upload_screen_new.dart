import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_rtms/providers/face_detection_provider.dart';
import 'package:open_rtms/widgets/face_detection_overlay.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:open_rtms/widgets/ml_kit_face_painter.dart';
import 'package:path_provider/path_provider.dart';

class ImageUploadScreen extends StatefulWidget {
  const ImageUploadScreen({super.key});

  @override
  State<ImageUploadScreen> createState() => _ImageUploadScreenState();
}

class _ImageUploadScreenState extends State<ImageUploadScreen> {
  File? _selectedImage;
  bool _isProcessing = false;
  Size? _imageSize;
  ui.Image? _uiImage; // Add UI Image property

  // ML Kit Face Detector
  late FaceDetector _faceDetector;
  List<Face> _mlKitFaces = [];
  final FaceDetectorOptions _faceDetectorOptions = FaceDetectorOptions(
    enableClassification: true, // Detect smiling
    enableLandmarks: true, // Detect landmarks like eyes, ears, nose
    enableContours: false, // No need for facial contours
    enableTracking: false, // Not needed for static images
    minFaceSize: 0.1, // Detect smaller faces (0.1 = 10% of image width)
    performanceMode: FaceDetectorMode.accurate, // More accurate but slower
  );

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Initialize the face detector
    _faceDetector = FaceDetector(options: _faceDetectorOptions);
  }

  @override
  void dispose() {
    // Close the detector when done
    _faceDetector.close();
    super.dispose();
  }

  // Function to convert File to ui.Image
  Future<ui.Image?> fileToUiImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } catch (e) {
      print("📱 Error converting file to UI Image: $e");
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920, // High resolution but not too large
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);

      // Clear any previously detected faces
      _mlKitFaces = [];
      _uiImage = null;

      // Also clear any previous detections in the provider
      final detectionProvider =
          Provider.of<FaceDetectionProvider>(context, listen: false);
      detectionProvider.updateDetections([]);

      // Get image dimensions
      final bytes = await pickedFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);

      // Convert to ui.Image for the painter
      final uiImage = await fileToUiImage(file);

      if (decodedImage != null) {
        setState(() {
          _selectedImage = file;
          _imageSize = Size(
              decodedImage.width.toDouble(), decodedImage.height.toDouble());
          _uiImage = uiImage;
        });

        print("📱 Image converted to UI Image: ${_uiImage != null}");
        print(
            "📱 Image dimensions: ${_imageSize!.width}x${_imageSize!.height}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Get the face detection provider
      final detectionProvider =
          Provider.of<FaceDetectionProvider>(context, listen: false);

      print("📱 Processing image with ML Kit...");

      try {
        // Create an input image from the selected file
        final inputImage = InputImage.fromFile(_selectedImage!);
        print("📱 Created input image from file: ${_selectedImage!.path}");

        // Process the image with ML Kit
        _mlKitFaces = await _faceDetector.processImage(inputImage);
        print(
            "📱 ML Kit face detection complete. Found ${_mlKitFaces.length} faces.");

        // Log details about each detected face
        for (int i = 0; i < _mlKitFaces.length; i++) {
          final face = _mlKitFaces[i];
          final rect = face.boundingBox;
          print(
              "📱 Face #$i - Rect: ${rect.left},${rect.top},${rect.width},${rect.height}");
          print(
              "📱 Face #$i - Landmarks: ${face.landmarks.length}, HeadAngle: ${face.headEulerAngleY}");
        }
      } catch (e) {
        print("📱 Error during ML Kit face detection: $e");
        rethrow;
      }

      // Read image bytes for recognition and UI display
      final bytes = await _selectedImage!.readAsBytes();
      print("📱 Image bytes read: ${bytes.length} bytes");

      // Get image dimensions
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception("Failed to decode image");
      }
      print(
          "📱 Image decoded successfully: ${decodedImage.width}x${decodedImage.height}");

      // Update the image size for UI and ensure we have a UI Image for painting
      final uiImage = await fileToUiImage(_selectedImage!);
      setState(() {
        _imageSize =
            Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
        _uiImage = uiImage; // Update the UI Image
      });

      // Convert ML Kit detections to the format expected by the provider
      List<Map<String, dynamic>> detections = [];
      for (Face face in _mlKitFaces) {
        final rect = face.boundingBox;
        // Make sure we use integer values for the detection ID to match exactly with painter
        final int left = rect.left.toInt();
        final int top = rect.top.toInt();
        detections.add({
          'box': [left.toDouble(), top.toDouble(), rect.width, rect.height],
          'confidence': face.headEulerAngleY != null
              ? (1.0 - face.headEulerAngleY!.abs() / 45.0)
              : 0.9,
          'class': 0,
          'name': 'face'
        });
      }

      // Update the provider with the detected faces
      detectionProvider.updateDetections(detections);

      // Check if we have any faces detected by ML Kit
      if (_mlKitFaces.isNotEmpty) {
        print("📱 Found ${_mlKitFaces.length} faces with ML Kit");

        // Instead of processing individual faces, send the whole image to the backend
        print("📱 Sending full image to backend for recognition...");

        try {
          // Initialize fake detection box IDs to match ML Kit faces
          Map<String, Map<String, dynamic>> mlKitFaceIds = {};
          for (int i = 0; i < _mlKitFaces.length; i++) {
            final face = _mlKitFaces[i];
            final rect = face.boundingBox;
            final faceId = "${rect.left.toInt()}_${rect.top.toInt()}";

            // Create placeholder entries in the recognized students map
            mlKitFaceIds[faceId] = {
              'name': 'Processing...',
              'student_id': null,
              'confidence': 0.0,
              'timestamp': DateTime.now().toString(),
            };
            print("📱 Added placeholder for face ID: $faceId");
          }

          // Update the detections in the provider for UI display
          detectionProvider.updateDetections(detections);

          // Add placeholders for detected faces
          detectionProvider.addPlaceholders(mlKitFaceIds);

          // Send the full image to the backend
          print("📱 Sending full image to backend for recognition");
          await detectionProvider.processUploadedImage(_selectedImage!);
          print("📱 Backend recognition complete");

          // Manually map the results from backend to ML Kit detected faces
          await Future.delayed(
              const Duration(milliseconds: 500)); // Give UI time to update
          setState(() {});
        } catch (e) {
          print('📱 Error sending image to backend: $e');
        }

        // Check if any faces were recognized after processing
        final recognizedFaces = detectionProvider.recognizedStudents.values
            .where((student) => student['student_id'] != null)
            .toList();

        if (recognizedFaces.isEmpty) {
          print("📱 No students were recognized from the detected faces");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No students recognized in the image')),
          );
        } else {
          print(
              "📱 Successfully recognized ${recognizedFaces.length} students");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${recognizedFaces.length} students recognized')),
          );
        }
      } else {
        print("📱 No faces detected in the image");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No faces detected in the image')),
        );
      }
    } catch (e) {
      print("📱 Critical error processing image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Method to crop a detected face from the image
  Future<File> _cropFaceFromImage(img.Image fullImage, Face face) async {
    try {
      print('📱 Cropping face from ML Kit detection');

      // Get face bounding box
      final rect = face.boundingBox;
      final x = rect.left.toInt();
      final y = rect.top.toInt();
      final w = rect.width.toInt();
      final h = rect.height.toInt();

      // Add padding to include more of the face/head
      final int paddingX = (w * 0.3).toInt();
      final int paddingY = (h * 0.3).toInt();

      // Make sure we don't go out of bounds
      final int safeX = x - paddingX < 0 ? 0 : x - paddingX;
      final int safeY = y - paddingY < 0 ? 0 : y - paddingY;
      final int safeW = safeX + w + (paddingX * 2) > fullImage.width
          ? fullImage.width - safeX
          : w + (paddingX * 2);
      final int safeH = safeY + h + (paddingY * 2) > fullImage.height
          ? fullImage.height - safeY
          : h + (paddingY * 2);

      print(
          '📱 Cropping area: x=$safeX, y=$safeY, w=$safeW, h=$safeH from image size ${fullImage.width}x${fullImage.height}');

      // Crop the face region
      final faceImage = img.copyCrop(
        fullImage,
        x: safeX,
        y: safeY,
        width: safeW,
        height: safeH,
      );

      // Enhance the image for better recognition
      final enhancedImage = img.adjustColor(
        faceImage,
        brightness: 1.2,
        contrast: 1.3,
        saturation: 1.0,
      );

      // Standardize the size for face recognition
      final resizedImage = img.copyResize(
        enhancedImage,
        width: 640,
        height: 480,
        interpolation: img.Interpolation.cubic,
      );

      // Save the face image to a temporary file
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/face_$timestamp.jpg';
      final file = File(path);

      await file.writeAsBytes(img.encodeJpg(resizedImage, quality: 100));
      print(
          '📱 Enhanced face image saved: ${file.path}, size: ${await file.length()} bytes');

      return file;
    } catch (e) {
      print('📱 Error cropping face: $e');

      // Create a placeholder image in case of error
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/error_face_$timestamp.jpg';
      final file = File(path);

      final placeholderImage = img.Image(width: 640, height: 480);
      img.fill(placeholderImage, color: img.ColorRgb8(255, 200, 200));
      await file.writeAsBytes(img.encodeJpg(placeholderImage));

      throw Exception('Failed to crop face from image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Image'),
        elevation: 0,
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
                // Image Area
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: _selectedImage == null
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey, width: 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'No Image Selected',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          )
                        : _imageSize != null
                            ? (() {
                                // Calculate available space for consistent display
                                final availableWidth = screenSize.width - 32;
                                final availableHeight = availableWidth * 3 / 4;

                                // Always show the image using CustomPaint, with or without faces
                                return Consumer<FaceDetectionProvider>(
                                  builder: (context, provider, child) {
                                    // Check if we have faces detected by ML Kit
                                    if (_mlKitFaces.isNotEmpty) {
                                      print(
                                          "📱 Rendering ${_mlKitFaces.length} ML Kit faces on image ${_imageSize!.width}x${_imageSize!.height}");
                                      print(
                                          "📱 UI Image available for rendering: ${_uiImage != null}");

                                      return Stack(
                                        children: [
                                          // Display image with face detections
                                          CustomPaint(
                                            size: Size(availableWidth,
                                                availableHeight),
                                            painter: MLKitFacePainter(
                                              imageFile: _selectedImage,
                                              uiImage: _uiImage,
                                              faces: _mlKitFaces,
                                              imageSize: _imageSize!,
                                              recognizedStudents:
                                                  provider.recognizedStudents,
                                            ),
                                          ),

                                          // Add ML Kit label
                                          Positioned(
                                            top: 10,
                                            right: 10,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withOpacity(0.6),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'ML Kit Detection',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    } else if (provider.detections.isNotEmpty) {
                                      // Fallback to YOLO detections
                                      print(
                                          "📱 Falling back to YOLO detections: ${provider.detections.length}");
                                      return FaceDetectionOverlay(
                                        detections: provider.detections,
                                        recognizedStudents:
                                            provider.recognizedStudents,
                                        previewSize: _imageSize!,
                                        screenSize: Size(
                                            availableWidth, availableHeight),
                                      );
                                    } else {
                                      // Just show the image without faces using the same painter
                                      // This ensures consistent image display before face detection
                                      return CustomPaint(
                                        size: Size(
                                            availableWidth, availableHeight),
                                        painter: MLKitFacePainter(
                                          imageFile: _selectedImage,
                                          uiImage: _uiImage,
                                          faces: const [], // Empty faces list
                                          imageSize: _imageSize!,
                                          recognizedStudents: const {}, // Empty recognitions
                                        ),
                                      );
                                    }
                                  },
                                );
                              })()
                            : Image.file(
                                _selectedImage!,
                                fit: BoxFit.contain,
                              ),
                  ),
                ),

                // Processing indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Processing Image...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Select Image'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _selectedImage == null || _isProcessing
                      ? null
                      : _processImage,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.face),
                  label: Text(_isProcessing
                      ? 'Processing...'
                      : 'Detect Faces with ML Kit'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
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
                  color: Colors.grey.shade100,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 5,
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
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
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
                          child: Text('No students recognized yet'),
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
}
