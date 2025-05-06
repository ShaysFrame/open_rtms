import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/face_detection_provider.dart';
import 'providers/student_provider.dart';
import 'services/camera_service.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();

  await Permission.camera.request();

  // Add other permissions your app needs
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('💥 FLUTTER ERROR: ${details.exception}');
    debugPrint(details.stack.toString());
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FaceDetectionProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        Provider(create: (_) => CameraService(cameras)),
      ],
      child: const OpenRTMSApp(),
    ),
  );
}

class OpenRTMSApp extends StatelessWidget {
  const OpenRTMSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open RTMS',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
