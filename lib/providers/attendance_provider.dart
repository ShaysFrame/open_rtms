import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class AttendanceProvider with ChangeNotifier {
  // Central storage of recognized students
  AttendanceProvider()
      : sessionId = const Uuid().v4(),
        sessionStartTime = DateTime.now();

  final Map<String, Map<String, dynamic>> _recognizedStudents = {};

  // Session management
  String sessionId;
  DateTime sessionStartTime;
  String? sessionName;
  final _uuid = const Uuid();
  final Set<String> recognizedStudentIdsThisSession = {};

  // Statistics
  int _totalStudentsDetected = 0;
  int _totalStudentsRecognized = 0;

  // Getters
  Map<String, Map<String, dynamic>> get recognizedStudents =>
      _recognizedStudents;
  int get totalStudentsDetected => _totalStudentsDetected;
  int get totalStudentsRecognized => _totalStudentsRecognized;

  // Starting a new session
  void startNewSession({String? name}) {
    sessionId = _uuid.v4();
    sessionStartTime = DateTime.now();
    sessionName = name;
    resetAttendance();
    notifyListeners();
    debugPrint('📱 Started new attendance session: $sessionId');
    if (name != null) {
      debugPrint('📱 Session name: $name');
    }
  }

  // Get a formatted representation of the session
  String get sessionDisplay {
    final dateStr =
        '${sessionStartTime.year}-${sessionStartTime.month.toString().padLeft(2, '0')}-${sessionStartTime.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${sessionStartTime.hour.toString().padLeft(2, '0')}:${sessionStartTime.minute.toString().padLeft(2, '0')}';
    return sessionName != null
        ? '$sessionName ($dateStr $timeStr)'
        : 'Session $dateStr $timeStr';
  }

  // Add a recognized student from any detection source
  void addRecognizedStudent({
    required String detectionId,
    required String? studentId,
    required String name,
    required double confidence,
    String source = 'unknown', // 'face_detection' or 'person_detection'
  }) {
    // Only track as recognized if we have a valid student ID
    if (studentId != null) {
      recognizedStudentIdsThisSession.add(studentId);
      _totalStudentsRecognized = recognizedStudentIdsThisSession.length;
    }

    _recognizedStudents[detectionId] = {
      'name': name,
      'student_id': studentId,
      'confidence': confidence,
      'timestamp': DateTime.now().toString(),
      'source': source,
    };

    notifyListeners();
  }

  void updateDetectionCount(int count) {
    _totalStudentsDetected = count;
    notifyListeners();
  }

  void resetAttendance() {
    _recognizedStudents.clear();
    recognizedStudentIdsThisSession.clear();
    _totalStudentsDetected = 0;
    _totalStudentsRecognized = 0;
    notifyListeners();
  }

  // Method to get the list of already recognized IDs for API calls
  String getAlreadyRecognizedIdsParam() {
    return recognizedStudentIdsThisSession.isEmpty
        ? ''
        : recognizedStudentIdsThisSession.join(',');
  }
}
