import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../services/yolo_service.dart';
import '../../../shared/utils/image_utils.dart';

class ImageScreen extends StatefulWidget {
  const ImageScreen({Key? key}) : super(key: key);

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  List<Map<String, dynamic>> _detections = [];
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  // YOLO service
  final _yoloService = YoloService();

  @override
  void initState() {
    super.initState();
    // Initialize the YOLO service
    _initializeYolo();
  }

  Future<void> _initializeYolo() async {
    await _yoloService.initialize();
  }

  Future<void> _pickAndPredict() async {
    // Pick an image from the gallery
    final imageFile = await ImageUtils.pickImageFromGallery();
    if (imageFile == null) return;

    // Read the image bytes
    final bytes = await imageFile.readAsBytes();

    // Run inference on the image
    final result = await _yoloService.predictImage(bytes);

    setState(() {
      // Check if boxes exist and set them as detections
      if (result.containsKey('boxes') && result['boxes'] is List) {
        _detections = List<Map<String, dynamic>>.from(result['boxes']);
      } else {
        _detections = [];
      }

      // Check if annotated image exists
      if (result.containsKey('annotatedImage') &&
          result['annotatedImage'] is Uint8List) {
        _annotatedImage = result['annotatedImage'] as Uint8List;
      } else {
        _annotatedImage = null;
      }

      _imageBytes = bytes;
    });
  }

  @override
  void dispose() {
    _yoloService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Detection'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _pickAndPredict,
            child: const Text('Pick Image & Run Inference'),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_annotatedImage != null)
                    SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: Image.memory(_annotatedImage!),
                    )
                  else if (_imageBytes != null)
                    SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: Image.memory(_imageBytes!),
                    ),
                  const SizedBox(height: 10),
                  const Text('Detections:'),
                  _buildDetectionsList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionsList() {
    if (_detections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No detections found'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _detections.length,
      itemBuilder: (context, index) {
        final detection = _detections[index];
        print('Detection: $detection');
        final className = detection['class'] ?? 'Unknown';
        final confidence = detection['confidence'] as double? ?? 0.0;
        final box = '(${detection['x1']}, ${detection['y1']}), '
            '(${detection['x2']}, ${detection['y2']})';

        return ListTile(
          title: Text('$className (${(confidence * 100).toStringAsFixed(1)}%)'),
          subtitle: Text('Box: $box'),
        );
      },
    );
  }
}
