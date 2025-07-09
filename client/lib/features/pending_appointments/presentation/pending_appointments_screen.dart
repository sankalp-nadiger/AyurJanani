import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PendingAppointmentsScreen extends StatefulWidget {
  @override
  _PendingAppointmentsScreenState createState() =>
      _PendingAppointmentsScreenState();
}

class _PendingAppointmentsScreenState extends State<PendingAppointmentsScreen> {
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  late Future<List<Map<String, dynamic>>> _appointmentsFuture;

  @override
  void initState() {
    super.initState();
    _appointmentsFuture = _fetchAppointments();
  }

  Future<List<Map<String, dynamic>>> _fetchAppointments() async {
    try {
      print('=== FETCHING APPOINTMENTS FROM API ===');
      final token = await secureStorage.read(key: 'nodejs_token');
      if (token == null || token.isEmpty) {
        print('❌ No token available for appointments');
        return [];
      }
      final response = await http.get(
        Uri.parse('https://fitfull.onrender.com/api/doctor/active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      print('Appointments API Status Code: ${response.statusCode}');
      print('Appointments API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('sessions')) {
          return (data['sessions'] as List).cast<Map<String, dynamic>>();
        } else if (data is List) {
          return data.cast<Map<String, dynamic>>();
        } else if (data is Map && data.containsKey('data')) {
          return (data['data'] as List).cast<Map<String, dynamic>>();
        } else {
          return [];
        }
      } else {
        print('Failed to load appointments: ${response.statusCode}');
        return [];
      }
    } catch (error) {
      print("Error fetching appointments: $error");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    print('PendingAppointmentsScreen build called');
    return Scaffold(
      appBar: AppBar(
        title: Text('Your Pending Appointments',
            style: TextStyle(color: Colors.white)),
        backgroundColor: AppPallete.gradient1,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      backgroundColor: AppPallete.backgroundColor,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _appointmentsFuture,
        builder: (context, snapshot) {
          print(
              'FutureBuilder called. Connection: ${snapshot.connectionState}');
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppPallete.gradient1),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading appointments',
                  style: TextStyle(color: Colors.red)),
            );
          }
          final appointments = snapshot.data ?? [];
          if (appointments.isEmpty) {
            return Center(
              child: Text('No pending appointments.',
                  style: TextStyle(color: AppPallete.textColor, fontSize: 16)),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(20),
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final appt = appointments[index];
              final dateTime =
                  DateTime.tryParse(appt['startTime'] ?? '') ?? DateTime.now();
              final dateStr =
                  '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
              final timeStr =
                  '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
              final doctor = appt['doctor'] ?? {};
              final doctorName =
                  doctor['fullName'] ?? doctor['name'] ?? 'Unknown';
              final issueDetails = appt['issueDetails'] ?? '';
              final status = appt['status'] ?? '';
              final now = DateTime.now();
              final canJoin = status.toLowerCase() == 'pending' &&
                  now.isAfter(dateTime.subtract(Duration(minutes: 10))) &&
                  now.isBefore(dateTime.add(Duration(minutes: 10)));

              return Container(
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.08),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.calendarClock,
                            color: AppPallete.gradient1, size: 32),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Dr. $doctorName',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppPallete.textColor,
                                  fontSize: 16)),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('Date: $dateStr',
                        style: TextStyle(
                            color: AppPallete.textColor.withOpacity(0.7))),
                    Text('Time: $timeStr',
                        style: TextStyle(
                            color: AppPallete.textColor.withOpacity(0.7))),
                    if (issueDetails.isNotEmpty)
                      Text('Reason: $issueDetails',
                          style: TextStyle(
                              color: AppPallete.textColor.withOpacity(0.7))),
                    SizedBox(height: 2),
                    Text('Status: $status',
                        style: TextStyle(
                            color: AppPallete.gradient2,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            print(
                                'Join pressed for appointment ${appt['_id']}');
                            final sessionId = appt['_id'];
                            final token =
                                await secureStorage.read(key: 'nodejs_token');
                            if (token == null || token.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Authentication failed. Please log in again.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            try {
                              final response = await http.post(
                                Uri.parse(
                                    'https://fitfull.onrender.com/api/doctor/$sessionId/join-session'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Authorization': 'Bearer $token',
                                },
                              );
                              if (response.statusCode == 200 ||
                                  response.statusCode == 201) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Successfully joined the session!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                final roomName = appt['roomName'] ?? '';
                                if (roomName.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'No room name found for this session.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                // Jitsi Meet code removed here. You may want to add alternative logic if needed.
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Failed to join session. Please try again.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error joining session: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: Icon(Icons.video_call,
                              size: 18, color: AppPallete.gradient2),
                          label: Text('Join',
                              style: TextStyle(
                                  color: AppPallete.gradient2,
                                  fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: AppPallete.gradient2, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                        SizedBox(width: 24),
                        OutlinedButton.icon(
                          onPressed: () {
                            print('Reschedule pressed for ${appt['_id']}');
                            // TODO: Implement reschedule logic
                          },
                          icon: Icon(Icons.schedule,
                              size: 18, color: AppPallete.gradient2),
                          label: Text('Reschedule',
                              style: TextStyle(color: AppPallete.gradient2)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: AppPallete.gradient2, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
