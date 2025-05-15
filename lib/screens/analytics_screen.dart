import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_rtms/providers/attendance_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Analytics'),
        actions: [
          Consumer<AttendanceProvider>(
            builder: (context, provider, child) {
              final presentStudents = provider.recognizedStudents.values
                  .where((student) => student['student_id'] != null)
                  .toList();

              if (presentStudents.isEmpty) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                tooltip: 'Export to PDF',
                onPressed: _isExporting ? null : () => _exportToPdf(provider),
              );
            },
          ),
        ],
      ),
      body: Consumer<AttendanceProvider>(
        builder: (context, provider, child) {
          final presentStudents = provider.recognizedStudents.values
              .where((student) => student['student_id'] != null)
              .toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildSessionInfoCard(provider)),
              SliverToBoxAdapter(child: _buildStatisticsCard(provider)),
              provider.recognizedStudents.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No attendance data available.\nStart a new attendance session to collect data.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  : SliverFillRemaining(
                      child: _buildStudentList(presentStudents),
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSessionInfoCard(AttendanceProvider provider) {
    final sessionStartFormatted =
        DateFormat('MMM d, yyyy • h:mm a').format(provider.sessionStartTime);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.event_note, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                // Wrap the session name in an Expanded and Text with maxLines and overflow
                Expanded(
                  child: Text(
                    provider.sessionName ?? 'Attendance Session',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  sessionStartFormatted,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.fingerprint, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Session ID: ${provider.sessionId.substring(0, 8)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(AttendanceProvider provider) {
    final presentStudents = provider.recognizedStudents.values
        .where((student) => student['student_id'] != null)
        .toList();

    // Count students by source
    int faceDetectionCount = 0;
    int personDetectionCount = 0;

    for (final student in presentStudents) {
      final source = student['source'] as String? ?? 'unknown';
      if (source == 'face_detection') {
        faceDetectionCount++;
      } else if (source == 'person_detection') {
        personDetectionCount++;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, constraints) {
          // For smaller screens, stack the stats vertically
          if (constraints.maxWidth < 360) {
            return Column(
              children: [
                _buildStatItem(
                    'Total Present',
                    presentStudents.length.toString(),
                    Icons.people,
                    Colors.green),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                          'Face Detection',
                          faceDetectionCount.toString(),
                          Icons.face,
                          Colors.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatItem(
                          'Person Detection',
                          personDetectionCount.toString(),
                          Icons.person_outline,
                          Colors.orange),
                    ),
                  ],
                ),
              ],
            );
          }

          // For larger screens, show side by side
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: _buildStatItem(
                    'Total Present',
                    presentStudents.length.toString(),
                    Icons.people,
                    Colors.green),
              ),
              Expanded(
                child: _buildStatItem('Face Detection',
                    faceDetectionCount.toString(), Icons.face, Colors.blue),
              ),
              Expanded(
                child: _buildStatItem(
                    'Person Detection',
                    personDetectionCount.toString(),
                    Icons.person_outline,
                    Colors.orange),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentList(List<Map<String, dynamic>> students) {
    // Sort students by timestamp (most recent first)
    students.sort((a, b) {
      final aTimestamp = DateTime.parse(a['timestamp'] as String);
      final bTimestamp = DateTime.parse(b['timestamp'] as String);
      return bTimestamp.compareTo(aTimestamp);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Recognized Students (${students.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: students.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final student = students[index];
              final timestamp = DateTime.parse(student['timestamp'] as String);
              final formattedTime = DateFormat('h:mm:ss a').format(timestamp);
              final source = student['source'] as String? ?? 'unknown';

              IconData sourceIcon = Icons.question_mark;
              Color sourceColor = Colors.grey;

              if (source == 'face_detection') {
                sourceIcon = Icons.face;
                sourceColor = Colors.blue;
              } else if (source == 'person_detection') {
                sourceIcon = Icons.person_outline;
                sourceColor = Colors.orange;
              }

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey[200],
                    child: Text(
                      student['name'][0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    student['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${student['student_id']}'),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            formattedTime,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                          Icon(sourceIcon, size: 12, color: sourceColor),
                          const SizedBox(width: 4),
                          Text(
                            _formatSource(source),
                            style: TextStyle(fontSize: 12, color: sourceColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Text(
                    '${((student['confidence'] as double) * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color:
                          _getConfidenceColor(student['confidence'] as double),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatSource(String source) {
    switch (source) {
      case 'face_detection':
        return 'Face';
      case 'person_detection':
        return 'Person';
      default:
        return 'Unknown';
    }
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.9) {
      return Colors.green;
    } else if (confidence >= 0.7) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  Future<void> _exportToPdf(AttendanceProvider provider) async {
    try {
      setState(() {
        _isExporting = true;
      });

      final presentStudents = provider.recognizedStudents.values
          .where((student) => student['student_id'] != null)
          .toList();

      if (presentStudents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students to export')),
        );
        setState(() {
          _isExporting = false;
        });
        return;
      }

      // Sort students by timestamp
      presentStudents.sort((a, b) {
        final aTimestamp = DateTime.parse(a['timestamp'] as String);
        final bTimestamp = DateTime.parse(b['timestamp'] as String);
        return bTimestamp.compareTo(aTimestamp);
      });

      final sessionDate =
          DateFormat('yyyy-MM-dd').format(provider.sessionStartTime);
      final sessionTime = DateFormat('HH:mm').format(provider.sessionStartTime);

      // Create PDF document with default fonts
      final pdf = pw.Document();

      // Add page
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Attendance Report',
                      style: pw.TextStyle(
                          fontSize: 28, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue50,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Text(
                        'Generated ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        provider.sessionName ?? 'Attendance Session',
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Date: $sessionDate | Time: $sessionTime',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Session ID: ${provider.sessionId}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Divider(),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 10,
                ),
              ),
            );
          },
          build: (pw.Context context) => [
            pw.SizedBox(height: 8),

            // Summary statistics
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                _buildPdfStatBox('Total Students Present',
                    '${presentStudents.length}', PdfColors.green),
                _buildPdfStatBox(
                    'Face Detection',
                    '${presentStudents.where((s) => (s['source'] as String?) == 'face_detection').length}',
                    PdfColors.blue),
                _buildPdfStatBox(
                    'Person Detection',
                    '${presentStudents.where((s) => (s['source'] as String?) == 'person_detection').length}',
                    PdfColors.orange),
              ],
            ),

            pw.SizedBox(height: 20),
            pw.Text(
              'Attendance Details',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),

            // Student table
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              children: [
                // Table header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey100,
                  ),
                  children: [
                    _pdfTableCell('Student Name', isHeader: true),
                    _pdfTableCell('Student ID', isHeader: true),
                    _pdfTableCell('Time', isHeader: true),
                    _pdfTableCell('Source', isHeader: true),
                    _pdfTableCell('Confidence', isHeader: true),
                  ],
                ),

                // Table rows with student data
                ...presentStudents.map((student) {
                  final timestamp =
                      DateTime.parse(student['timestamp'] as String);
                  final formattedTime =
                      DateFormat('h:mm:ss a').format(timestamp);
                  final confidencePercent =
                      '${((student['confidence'] as double) * 100).toStringAsFixed(0)}%';

                  return pw.TableRow(
                    children: [
                      _pdfTableCell(student['name'] as String),
                      _pdfTableCell(student['student_id'] as String),
                      _pdfTableCell(formattedTime),
                      _pdfTableCell(_formatSource(
                          student['source'] as String? ?? 'unknown')),
                      _pdfTableCell(confidencePercent),
                    ],
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      );

      // Save the PDF
      final output = await getTemporaryDirectory();
      final filePath =
          "${output.path}/attendance_report_${sessionDate.replaceAll('-', '')}.pdf";
      final file = File(filePath);

      try {
        final pdfData = await pdf.save();
        debugPrint('PDF generated successfully: ${pdfData.length} bytes');

        await file.writeAsBytes(pdfData);
        debugPrint('PDF saved to file: $filePath');

        // Open the PDF
        await _openPdfFile(filePath);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF exported successfully')),
        );
      } catch (e) {
        debugPrint('Error saving PDF: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Error saving PDF: ${e.toString().substring(0, math.min(e.toString().length, 100))}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
      debugPrint('Error exporting PDF: $e');
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  pw.Widget _buildPdfStatBox(String title, String value, PdfColor color) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.white,
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfTableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: isHeader ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isHeader ? pw.FontWeight.bold : null,
          fontSize: 10,
        ),
      ),
    );
  }

  Future<void> _openPdfFile(String filePath) async {
    // First verify that the file exists and is not empty
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('PDF file does not exist: $filePath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: PDF file was not created properly'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      debugPrint('PDF file is empty: $filePath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: PDF file is empty'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    debugPrint('PDF file exists and has size: $fileSize bytes');

    try {
      // Show a temporary success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF generated successfully! Opening...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Use share_plus for cross-platform compatibility
      final xFile = XFile(filePath);
      final sharingResult = await Share.shareXFiles(
        [xFile],
        text: 'Attendance Report',
        subject:
            'Attendance Report ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      );

      debugPrint('Share result: $sharingResult');
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
      // If sharing fails, try direct launch
      try {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          // If we can't launch directly, show the file path
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('PDF saved at: $filePath'),
                action: SnackBarAction(
                  label: 'OK',
                  onPressed: () {},
                ),
                duration: const Duration(seconds: 10),
              ),
            );
          }
        }
      } catch (e2) {
        debugPrint('Error opening PDF: $e2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved but could not be opened: $filePath'),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'OK',
                onPressed: () {},
              ),
            ),
          );
        }
      }
    }
  }
}
