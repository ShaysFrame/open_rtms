import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_rtms/providers/student_provider.dart';
import 'package:open_rtms/services/camera_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late CameraController _cameraController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isInitialized = false;
  bool _isTakingPicture = false;
  bool _hasPicture = false;

  @override
  void initState() {
    super.initState();
    final cameraService = Provider.of<CameraService>(context, listen: false);
    _initCamera(cameraService);
  }

  Future<void> _initCamera(CameraService cameraService) async {
    _cameraController = await cameraService.initializeCamera();

    if (!mounted) return;

    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _takePicture() async {
    try {
      setState(() {
        _isTakingPicture = true;
      });

      final XFile image = await _cameraController.takePicture();

      if (!mounted) return;

      final studentProvider =
          Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.setCurrentImage(image);

      setState(() {
        _isTakingPicture = false;
        _hasPicture = true;
      });
    } catch (e) {
      setState(() {
        _isTakingPicture = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking picture: $e')),
      );
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200, // Limit image size for better performance
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (pickedFile == null) return; // User canceled the picker

      if (!mounted) return;

      final studentProvider =
          Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.setCurrentImage(pickedFile);

      setState(() {
        _hasPicture = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> _registerStudent() async {
    if (_nameController.text.isEmpty || _idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out all fields')),
      );
      return;
    }

    if (!_hasPicture) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take a picture first')),
      );
      return;
    }

    final studentProvider =
        Provider.of<StudentProvider>(context, listen: false);

    try {
      await studentProvider.registerStudent(
        name: _nameController.text,
        id: _idController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student registered successfully')),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register New Student')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register New Student')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Student Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            const Text(
              'Student Photo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Consumer<StudentProvider>(
              builder: (context, provider, child) {
                return AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: provider.currentImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              provider.currentImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CameraPreview(_cameraController),
                          ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _hasPicture
                ? ElevatedButton.icon(
                    onPressed: () => setState(() => _hasPicture = false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake Photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isTakingPicture ? null : _takePicture,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Photo'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickImageFromGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Select Photo'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _registerStudent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Register Student'),
            ),
          ],
        ),
      ),
    );
  }
}
