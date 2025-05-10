// import 'package:flutter/material.dart';
// import 'package:ultralytics_yolo/yolo.dart';
// import 'package:ultralytics_yolo/yolo_view.dart';
// import '../services/yolo_service.dart';
// import '../../../shared/widgets/confidence_slider.dart';
// import '../../../shared/widgets/iou_slider.dart';
// import '../../../core/config/app_config.dart';

// class CameraScreen extends StatefulWidget {
//   const CameraScreen({Key? key}) : super(key: key);

//   @override
//   State<CameraScreen> createState() => _CameraScreenState();
// }

// class _CameraScreenState extends State<CameraScreen> {
//   int _detectionCount = 0;
//   double _confidenceThreshold = AppConfig.defaultConfidenceThreshold;
//   double _iouThreshold = AppConfig.defaultIouThreshold;
//   String _lastDetection = "";

//   // YOLO service and controller
//   final _yoloService = YoloService();
//   late final YoloViewController _yoloController;

//   void _onDetectionResults(List<YOLOResult> results) {
//     for (var result in results) {
//       debugPrint(
//           'Detected class: ${result.className} with confidence: ${result.confidence}');
//     }

//     // Then apply filter if needed
//     results = results
//         .where((result) => ['face', '0', 'face_0', 'person']
//             .contains(result.className.toLowerCase()))
//         .toList();

//     if (!mounted) return;

//     debugPrint('_onDetectionResults called with ${results.length} results');

//     // Print details of the first few detections for debugging
//     for (var i = 0; i < results.length && i < 3; i++) {
//       final r = results[i];
//       debugPrint(
//           '  Detection $i: ${r.className} (${(r.confidence * 100).toStringAsFixed(1)}%) at ${r.boundingBox}');
//     }

//     // Update the state
//     setState(() {
//       _detectionCount = results.length;
//       if (results.isNotEmpty) {
//         // Get detection with highest confidence
//         final topDetection =
//             results.reduce((a, b) => a.confidence > b.confidence ? a : b);
//         _lastDetection =
//             "${topDetection.className} (${(topDetection.confidence * 100).toStringAsFixed(1)}%)";

//         debugPrint(
//             'Updated state: count=$_detectionCount, top=$_lastDetection');
//       } else {
//         _lastDetection = "None";
//         debugPrint('Updated state: No detections');
//       }
//     });
//   }

//   @override
//   void initState() {
//     super.initState();
//     debugPrint("Initializing Camera Screen...");

//     _initializeYolo();
//   }

//   Future<void> _initializeYolo() async {
//     try {
//       // Create controller
//       _yoloController = _yoloService.createController();

//       // Initialize in a try-catch to handle errors
//       await _yoloService.initialize();

//       if (mounted) {
//         await _yoloController.setThresholds(
//           confidenceThreshold: _confidenceThreshold,
//           iouThreshold: _iouThreshold,
//         );
//       }
//     } catch (e) {
//       debugPrint('Failed to initialize YOLO: $e');
//       // Show error to user if needed
//     }
//   }

//   @override
//   void dispose() {
//     try {
//       // Simply catch any errors during disposal
//       _yoloService.dispose();
//     } catch (e) {
//       debugPrint('Error disposing YOLO service: $e');
//     }
//     _yoloService.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Camera Detection'),
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back),
//           onPressed: () => Navigator.of(context).pop(),
//         ),
//       ),
//       body: Column(
//         children: [
//           const SizedBox(height: 10),
//           // Panel to display detection count and last detection class
//           Container(
//             padding: const EdgeInsets.all(8.0),
//             color: Colors.black.withOpacity(0.1),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text('Detection count: $_detectionCount'),
//                 Text('Top detection: $_lastDetection'),
//               ],
//             ),
//           ),
//           // Confidence threshold slider
//           ConfidenceSlider(
//             value: _confidenceThreshold,
//             onChanged: (value) {
//               setState(() {
//                 _confidenceThreshold = value;
//                 _yoloController.setConfidenceThreshold(value);
//               });
//             },
//           ),
//           // IoU threshold slider
//           IoUSlider(
//             value: _iouThreshold,
//             onChanged: (value) {
//               setState(() {
//                 if (value >= 0.0 && value <= 1.0) {
//                   _iouThreshold = value;
//                   _yoloController.setIoUThreshold(value);
//                 } else {
//                   debugPrint('Invalid IoU threshold: $value');
//                 }
//               });
//             },
//           ),
//           // Camera view
//           Expanded(
//             child: Container(
//               color: Colors.black12,
//               child: YoloView(
//                 controller: _yoloController,
//                 modelPath: YoloService.MODEL_PATH,
//                 task: YOLOTask.detect,
//                 onResult: _onDetectionResults,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// The main code that works with the object detection perfectly.
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import '../services/yolo_service.dart';
import '../../../shared/widgets/confidence_slider.dart';
import '../../../shared/widgets/iou_slider.dart';
import '../../../core/config/app_config.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  int _detectionCount = 0;
  double _confidenceThreshold = AppConfig.defaultConfidenceThreshold;
  double _iouThreshold = AppConfig.defaultIouThreshold;
  String _lastDetection = "";

  // YOLO service and controller
  final _yoloService = YoloService();
  late final YoloViewController _yoloController;

  void _onDetectionResults(List<YOLOResult> results) {
    if (!mounted) return;

    debugPrint('_onDetectionResults called with ${results.length} results');

    // Print details of the first few detections for debugging
    for (var i = 0; i < results.length && i < 3; i++) {
      final r = results[i];
      debugPrint(
          '  Detection $i: ${r.className} (${(r.confidence * 100).toStringAsFixed(1)}%) at ${r.boundingBox}');
    }

    // Update the state
    setState(() {
      _detectionCount = results.length;
      if (results.isNotEmpty) {
        // Get detection with highest confidence
        final topDetection =
            results.reduce((a, b) => a.confidence > b.confidence ? a : b);
        _lastDetection =
            "${topDetection.className} (${(topDetection.confidence * 100).toStringAsFixed(1)}%)";

        debugPrint(
            'Updated state: count=$_detectionCount, top=$_lastDetection');
      } else {
        _lastDetection = "None";
        debugPrint('Updated state: No detections');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    debugPrint("Initializing Camera Screen...");

    _initializeYolo();
  }

  Future<void> _initializeYolo() async {
    try {
      // Create controller
      _yoloController = _yoloService.createController();

      await _yoloController.setImageSize(width: 320, height: 320);
      // Initialize in a try-catch to handle errors
      await _yoloService.initialize();

      if (mounted) {
        await _yoloController.setThresholds(
          confidenceThreshold: _confidenceThreshold,
          iouThreshold: _iouThreshold,
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize YOLO: $e');
      // Show error to user if needed
    }
  }

  @override
  void dispose() {
    try {
      // Simply catch any errors during disposal
      _yoloService.dispose();
    } catch (e) {
      debugPrint('Error disposing YOLO service: $e');
    }
    _yoloService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Detection'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          // Panel to display detection count and last detection class
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.black.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Detection count: $_detectionCount'),
                Text('Top detection: $_lastDetection'),
              ],
            ),
          ),
          // Confidence threshold slider
          ConfidenceSlider(
            value: _confidenceThreshold,
            onChanged: (value) {
              setState(() {
                _confidenceThreshold = value;
                _yoloController.setConfidenceThreshold(value);
              });
            },
          ),
          // IoU threshold slider
          IoUSlider(
            value: _iouThreshold,
            onChanged: (value) {
              setState(() {
                if (value >= 0.0 && value <= 1.0) {
                  _iouThreshold = value;
                  _yoloController.setIoUThreshold(value);
                } else {
                  debugPrint('Invalid IoU threshold: $value');
                }
              });
            },
          ),
          // Camera view
          Expanded(
            child: Container(
              color: Colors.black12,
              child: YoloView(
                controller: _yoloController,
                modelPath: YoloService.MODEL_PATH,
                task: YOLOTask.detect,
                onResult: _onDetectionResults,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
