import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_rtms/providers/face_detection_provider.dart';
import 'package:open_rtms/widgets/face_detection_overlay.dart';
import 'package:image/image.dart' as img;

class ImageUploadScreen extends StatefulWidget {
  const ImageUploadScreen({super.key});

  @override
  State<ImageUploadScreen> createState() => _ImageUploadScreenState();
}

class _ImageUploadScreenState extends State<ImageUploadScreen> {
  File? _selectedImage;
  bool _isProcessing = false;
  Size? _imageSize;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920, // High resolution but not too large
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      setState(() {
        _selectedImage = File(pickedFile.path);
      });

      // Get image dimensions
      final bytes = await pickedFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage != null) {
        setState(() {
          _imageSize = Size(
              decodedImage.width.toDouble(), decodedImage.height.toDouble());
        });
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

      // Make sure the model is loaded
      await detectionProvider.loadModel();
      print("📱 Model loaded successfully");

      // Read image bytes
      final bytes = await _selectedImage!.readAsBytes();
      print("📱 Image bytes read: ${bytes.length} bytes");

      // Get image dimensions (for more accuracy)
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        throw Exception("Failed to decode image");
      }
      print(
          "📱 Image decoded successfully: ${decodedImage.width}x${decodedImage.height}");

      // Process the image for face detection
      print("📱 Starting face detection...");
      await detectionProvider.processUploadedImage(_selectedImage!);
      print(
          "📱 Face detection complete. Found ${detectionProvider.detections.length} faces.");

      // Process detected faces for recognition
      if (detectionProvider.detections.isNotEmpty) {
        print(
            "📱 Processing ${detectionProvider.detections.length} detected faces");

        // Process each detected face
        for (final detection in detectionProvider.detections) {
          try {
            print("📱 Cropping face at box: ${detection['box']}");
            final face = await detectionProvider.cropFaceFromImage(
                decodedImage, detection);
            print(
                "📱 Face cropped successfully, file size: ${await face.length()} bytes");

            print("📱 Sending face for recognition...");
            await detectionProvider.recognizeFaceFromImage(face, detection);
            print("📱 Face recognition complete");

            // Small delay to avoid overloading the backend
            await Future.delayed(const Duration(milliseconds: 800));
          } catch (e) {
            print('📱 Error processing face: $e');
            // Don't rethrow, continue with next face
          }
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
                // Image Container
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _selectedImage == null
                          ? Container(
                              color: Colors.grey.shade200,
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
                          : Stack(
                              children: [
                                // Image
                                Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.contain,
                                ),

                                // Face detection overlay
                                if (_imageSize != null)
                                  Consumer<FaceDetectionProvider>(
                                    builder: (context, provider, child) {
                                      if (provider.detections.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      // Calculate the container size based on the image's aspect ratio
                                      final containerWidth =
                                          screenSize.width - 32;
                                      final containerHeight = containerWidth *
                                          (_imageSize!.height /
                                              _imageSize!.width);

                                      return FaceDetectionOverlay(
                                        detections: provider.detections,
                                        recognizedStudents:
                                            provider.recognizedStudents,
                                        previewSize: _imageSize!,
                                        screenSize: Size(
                                            containerWidth, containerHeight),
                                      );
                                    },
                                  ),
                              ],
                            ),
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
                  label: Text(_isProcessing ? 'Processing...' : 'Detect Faces'),
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
