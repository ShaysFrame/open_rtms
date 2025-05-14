import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/face_detection_provider.dart';
import 'providers/student_provider.dart';
import 'providers/person_detection_provider.dart';
import 'providers/attendance_provider.dart';
import 'services/camera_service.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.camera.request();

  cameras = await availableCameras();

  // Add other permissions your app needs
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('💥 FLUTTER ERROR: ${details.exception}');
    debugPrint(details.stack.toString());
  };

  runApp(
    MultiProvider(
      providers: [
        // Register the centralized attendance provider first
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),

        // Register other providers that depend on it
        ChangeNotifierProxyProvider<AttendanceProvider, FaceDetectionProvider>(
          create: (_) => FaceDetectionProvider(),
          update: (_, attendanceProvider, faceProvider) =>
              faceProvider!..updateAttendanceProvider(attendanceProvider),
        ),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProxyProvider<AttendanceProvider,
            PersonDetectionProvider>(
          create: (_) => PersonDetectionProvider(),
          update: (_, attendanceProvider, personProvider) =>
              personProvider!..updateAttendanceProvider(attendanceProvider),
        ),
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
