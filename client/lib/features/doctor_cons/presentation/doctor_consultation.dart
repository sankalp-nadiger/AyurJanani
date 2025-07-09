import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DoctorConsultationPage extends StatefulWidget {
  const DoctorConsultationPage({super.key});

  @override
  State<DoctorConsultationPage> createState() => _DoctorConsultationPageState();
}

class _DoctorConsultationPageState extends State<DoctorConsultationPage>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _doctorsFuture;

  final FlutterSecureStorage secureStorage = FlutterSecureStorage();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _doctorsFuture = _fetchDoctors();
    _checkStoredToken(); // Add this line to check stored token

    _fadeController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchDoctors() async {
    try {
      print('=== FETCHING DOCTORS FROM API ===');
      debugPrint('=== FETCHING DOCTORS FROM API ===');

      final response = await http.get(
        Uri.parse('https://fitfull.onrender.com/api/doctor'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('Doctor API Status Code: ${response.statusCode}');
      print('Doctor API Headers: ${response.headers}');
      print('Doctor API Body: ${response.body}');
      debugPrint('Doctor API Status Code: ${response.statusCode}');
      debugPrint('Doctor API Headers: ${response.headers}');
      debugPrint('Doctor API Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Parsed Doctor Data: ${jsonEncode(data)}');
        debugPrint('Parsed Doctor Data: ${jsonEncode(data)}');

        List<Map<String, dynamic>> doctors = [];

        // Handle different possible response structures
        if (data is List) {
          doctors = data.cast<Map<String, dynamic>>();
        } else if (data is Map && data.containsKey('doctors')) {
          doctors = (data['doctors'] as List).cast<Map<String, dynamic>>();
        } else if (data is Map && data.containsKey('data')) {
          doctors = (data['data'] as List).cast<Map<String, dynamic>>();
        } else {
          doctors = [];
        }

        print('Loaded ${doctors.length} doctors');
        debugPrint('Loaded ${doctors.length} doctors');

        // Log each doctor's structure for debugging
        for (int i = 0; i < doctors.length; i++) {
          final doctor = doctors[i];
          print('Doctor $i: ${jsonEncode(doctor)}');
          debugPrint('Doctor $i: ${jsonEncode(doctor)}');
        }

        return doctors;
      } else {
        print('Failed to load doctors: ${response.statusCode}');
        debugPrint('Failed to load doctors: ${response.statusCode}');
        return [];
      }
    } catch (error) {
      print("Error fetching doctors: $error");
      debugPrint("Error fetching doctors: $error");
      return [];
    }
  }

  void _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      print('Could not launch $url');
      _showSnackBar("Could not initiate call", AppPallete.errorColor);
    }
  }

  void _startWhatsAppChat(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      _showSnackBar("Phone number not available", AppPallete.errorColor);
      return;
    }

    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    if (cleanedNumber.startsWith('0')) {
      cleanedNumber = cleanedNumber.substring(1);
    }

    if (cleanedNumber.startsWith('+91')) {
      cleanedNumber = cleanedNumber.substring(3);
    } else if (cleanedNumber.startsWith('91') && cleanedNumber.length > 10) {
      cleanedNumber = cleanedNumber.substring(2);
    }

    if (cleanedNumber.length == 10) {
      cleanedNumber = '91$cleanedNumber';
    } else if (!cleanedNumber.startsWith('91')) {
      cleanedNumber = '91$cleanedNumber';
    }

    print('Original: $phoneNumber, Cleaned: $cleanedNumber');

    final List<String> whatsappUrls = [
      'whatsapp://send?phone=$cleanedNumber&text=${Uri.encodeComponent("Hello Doctor, I would like to consult with you.")}',
      'https://wa.me/$cleanedNumber?text=${Uri.encodeComponent("Hello Doctor, I would like to consult with you.")}',
      'https://api.whatsapp.com/send?phone=$cleanedNumber&text=${Uri.encodeComponent("Hello Doctor, I would like to consult with you.")}'
    ];

    bool launched = false;

    for (String urlString in whatsappUrls) {
      try {
        final Uri url = Uri.parse(urlString);
        print('Trying URL: $urlString');

        if (await canLaunchUrl(url)) {
          await launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          );
          launched = true;
          print('Successfully launched: $urlString');
          break;
        }
      } catch (e) {
        print('Failed to launch $urlString: $e');
      }
    }

    if (!launched) {
      try {
        final Uri whatsappUri = Uri.parse('whatsapp://');
        if (await canLaunchUrl(whatsappUri)) {
          await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
          _showSnackBar("WhatsApp opened. Please search for: $cleanedNumber",
              AppPallete.gradient1);
        } else {
          throw Exception('WhatsApp not found');
        }
      } catch (e) {
        print('Could not launch WhatsApp: $e');
        _showSnackBar("WhatsApp not found. Please install WhatsApp.",
            AppPallete.errorColor);
      }
    }
  }

  void _bookAppointment(Map<String, dynamic> doctor) {
    print('=== BOOKING APPOINTMENT FOR DOCTOR ===');
    debugPrint('=== BOOKING APPOINTMENT FOR DOCTOR ===');
    print('Doctor object: ${jsonEncode(doctor)}');
    debugPrint('Doctor object: ${jsonEncode(doctor)}');
    print('Doctor _id: ${doctor['_id']}');
    debugPrint('Doctor _id: ${doctor['_id']}');

    // Extract doctor information
    final String doctorName = doctor['fullName'] ??
        doctor['name'] ??
        doctor['doctor_name'] ??
        "Unknown";

    final String doctorEmail = doctor['email'] ?? "";

    // Handle specification field which is an array
    String specialization = "General Practitioner";
    if (doctor['specification'] != null) {
      if (doctor['specification'] is List) {
        List<dynamic> specs = doctor['specification'];
        if (specs.isNotEmpty) {
          List<String> specStrings = [];
          for (var spec in specs) {
            if (spec is String) {
              specStrings.add(spec);
            } else if (spec is List) {
              specStrings.addAll(spec.cast<String>());
            }
          }
          if (specStrings.isNotEmpty) {
            specialization = specStrings.join(", ");
          }
        }
      } else if (doctor['specification'] is String) {
        specialization = doctor['specification'];
      }
    } else {
      specialization = doctor['specialization'] ??
          doctor['speciality'] ??
          doctor['department'] ??
          "General Practitioner";
    }

    // Show appointment booking dialog
    _showAppointmentDialog(doctor, doctorName, specialization, doctorEmail);
  }

  void _showAppointmentDialog(Map<String, dynamic> doctor, String doctorName,
      String specialization, String doctorEmail) {
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final reasonController = TextEditingController();
    bool isLoading = false;

    // Set initial date and time
    final now = DateTime.now();
    final initialDate = now.add(Duration(days: 1)); // Start from tomorrow
    dateController.text =
        "${initialDate.year}-${initialDate.month.toString().padLeft(2, '0')}-${initialDate.day.toString().padLeft(2, '0')}";
    timeController.text = "09:00";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppPallete.gradient1.withOpacity(0.1),
                      AppPallete.gradient2.withOpacity(0.05)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.calendar, color: AppPallete.gradient1),
              ),
              SizedBox(width: 12),
              Text(
                'Book Appointment',
                style: TextStyle(
                  color: AppPallete.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Doctor info card
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppPallete.gradient1.withOpacity(0.1),
                        AppPallete.gradient2.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppPallete.gradient1.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctorName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.textColor,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        specialization,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppPallete.textColor.withOpacity(0.7),
                        ),
                      ),
                      if (doctorEmail.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          doctorEmail,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPallete.textColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 20),
                _buildDatePickerField(dateController),
                SizedBox(height: 16),
                _buildTimePickerField(timeController),
                SizedBox(height: 16),
                _buildDialogTextField(
                    reasonController, 'Reason for Visit', LucideIcons.fileText,
                    maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                    color: AppPallete.textColor.withOpacity(0.6),
                    fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppPallete.gradient1, AppPallete.gradient2],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppPallete.gradient1.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoading
                      ? null
                      : () async {
                          if (dateController.text.isEmpty ||
                              timeController.text.isEmpty ||
                              reasonController.text.isEmpty) {
                            _showSnackBar("Please fill all required fields",
                                AppPallete.errorColor);
                            return;
                          }

                          setState(() {
                            isLoading = true;
                          });

                          try {
                            // Here you would typically send the appointment request to your backend
                            // For now, we'll just show the payment modal
                            await Future.delayed(
                                Duration(seconds: 1)); // Simulate API call

                            if (mounted) {
                              Navigator.pop(context);
                              final doctorId =
                                  doctor['_id'] ?? doctor['id'] ?? "unknown";
                              print('Extracted doctor ID: $doctorId');
                              debugPrint('Extracted doctor ID: $doctorId');

                              _showPaymentDialog(
                                doctorName: doctorName,
                                doctorId: doctorId,
                                date: dateController.text,
                                time: timeController.text,
                              );
                            }
                          } catch (error) {
                            print("Error booking appointment: $error");
                            _showSnackBar("Failed to book appointment",
                                AppPallete.errorColor);
                          } finally {
                            if (mounted) {
                              setState(() {
                                isLoading = false;
                              });
                            }
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Book Appointment',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildDialogTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        color: AppPallete.textColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppPallete.gradient1, size: 20),
        labelStyle: TextStyle(
          color: AppPallete.gradient1,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppPallete.gradient1.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppPallete.gradient1,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppPallete.errorColor,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField(TextEditingController controller) {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now().add(Duration(days: 1)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(Duration(days: 365)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppPallete.gradient1,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppPallete.textColor,
                ),
                dialogBackgroundColor: Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          controller.text =
              "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppPallete.gradient1.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, color: AppPallete.gradient1, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preferred Date',
                    style: TextStyle(
                      color: AppPallete.gradient1,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    controller.text.isEmpty ? 'Select a date' : controller.text,
                    style: TextStyle(
                      color: controller.text.isEmpty
                          ? AppPallete.textColor.withOpacity(0.5)
                          : AppPallete.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronDown,
                color: AppPallete.gradient1, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerField(TextEditingController controller) {
    return InkWell(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: 9, minute: 0),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppPallete.gradient1,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppPallete.textColor,
                ),
                dialogBackgroundColor: Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          final hour = picked.hour.toString().padLeft(2, '0');
          final minute = picked.minute.toString().padLeft(2, '0');
          controller.text = "$hour:$minute";
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppPallete.gradient1.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, color: AppPallete.gradient1, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preferred Time',
                    style: TextStyle(
                      color: AppPallete.gradient1,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    controller.text.isEmpty ? 'Select a time' : controller.text,
                    style: TextStyle(
                      color: controller.text.isEmpty
                          ? AppPallete.textColor.withOpacity(0.5)
                          : AppPallete.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronDown,
                color: AppPallete.gradient1, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Doctor Consultation',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPallete.gradient1, AppPallete.gradient2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: AppPallete.gradient1.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppPallete.backgroundColor,
              AppPallete.gradient1.withOpacity(0.03),
              AppPallete.backgroundColor,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _doctorsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: AppPallete.gradient1,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Loading doctors...",
                          style: TextStyle(
                            color: AppPallete.textColor.withOpacity(0.7),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildErrorState();
                }

                final doctors = snapshot.data ?? [];
                if (doctors.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildDoctorsList(doctors);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(32),
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppPallete.gradient1.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPallete.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                LucideIcons.alertCircle,
                size: 48,
                color: AppPallete.errorColor,
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Error Loading Doctors",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppPallete.textColor,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Something went wrong while fetching the doctors list",
              style: TextStyle(
                fontSize: 14,
                color: AppPallete.textColor.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppPallete.gradient1, AppPallete.gradient2],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _doctorsFuture = _fetchDoctors();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.refreshCw,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Retry",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(32),
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppPallete.gradient1.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppPallete.gradient1.withOpacity(0.1),
                    AppPallete.gradient2.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                LucideIcons.stethoscope,
                size: 64,
                color: AppPallete.gradient1,
              ),
            ),
            SizedBox(height: 24),
            Text(
              "No Doctors Available",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppPallete.textColor,
              ),
            ),
            SizedBox(height: 12),
            Text(
              "Add your first doctor to start consultations and keep track of your healthcare providers",
              style: TextStyle(
                fontSize: 16,
                color: AppPallete.textColor.withOpacity(0.7),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppPallete.gradient1, AppPallete.gradient2],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppPallete.gradient1.withOpacity(0.3),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _doctorsFuture = _fetchDoctors();
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.refreshCw,
                            color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text(
                          "Refresh Doctors",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorsList(List<Map<String, dynamic>> doctors) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppPallete.gradient1.withOpacity(0.1),
                  AppPallete.gradient2.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPallete.gradient1.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPallete.gradient1.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.stethoscope,
                    color: AppPallete.gradient1,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Your Healthcare Providers",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.textColor,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "${doctors.length} doctor${doctors.length == 1 ? '' : 's'} available for consultation",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppPallete.textColor.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              physics: BouncingScrollPhysics(),
              itemCount: doctors.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppPallete.gradient1.withOpacity(0.08),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _buildDoctorCard(doctors[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    // Extract doctor information with proper field mapping
    final String doctorName = doctor['fullName'] ??
        doctor['name'] ??
        doctor['doctor_name'] ??
        "Unknown";

    final String doctorEmail = doctor['email'] ?? "";

    // Handle specification field which is an array
    String specialization = "General Practitioner";
    if (doctor['specification'] != null) {
      if (doctor['specification'] is List) {
        List<dynamic> specs = doctor['specification'];
        if (specs.isNotEmpty) {
          // Handle case where specs might be strings or arrays
          List<String> specStrings = [];
          for (var spec in specs) {
            if (spec is String) {
              specStrings.add(spec);
            } else if (spec is List) {
              specStrings.addAll(spec.cast<String>());
            }
          }
          if (specStrings.isNotEmpty) {
            specialization = specStrings.join(", ");
          }
        }
      } else if (doctor['specification'] is String) {
        specialization = doctor['specification'];
      }
    } else {
      // Fallback to other possible field names
      specialization = doctor['specialization'] ??
          doctor['speciality'] ??
          doctor['department'] ??
          "General Practitioner";
    }

    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppPallete.gradient1.withOpacity(0.8),
                      AppPallete.gradient2.withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: doctor['image'] != null && doctor['image'].isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          doctor['image'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              LucideIcons.userCircle,
                              color: Colors.white,
                              size: 32,
                            );
                          },
                        ),
                      )
                    : Icon(
                        LucideIcons.userCircle,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppPallete.textColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppPallete.gradient1.withOpacity(0.1),
                            AppPallete.gradient2.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        specialization,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPallete.gradient1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (doctorEmail.isNotEmpty) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.mail,
                            size: 14,
                            color: AppPallete.textColor.withOpacity(0.6),
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doctorEmail,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppPallete.textColor.withOpacity(0.7),
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((doctor['details'] ??
                                doctor['description'] ??
                                doctor['bio']) !=
                            null &&
                        (doctor['details'] ??
                                doctor['description'] ??
                                doctor['bio'])
                            .isNotEmpty) ...[
                      SizedBox(height: 8),
                      Text(
                        doctor['details'] ??
                            doctor['description'] ??
                            doctor['bio'] ??
                            '',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppPallete.textColor.withOpacity(0.7),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppPallete.gradient1, AppPallete.gradient2],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppPallete.gradient1.withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _bookAppointment(doctor),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.calendar, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Book Appointment",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog({
    required String doctorName,
    required String doctorId,
    required String date,
    required String time,
    String upiLink = "upi://pay?pa=yourupi@bank&pn=FitFull&am=500&cu=INR",
    String amount = "₹500",
    String txnId = "TXN_C0AOQ9200",
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Center(
          child: Text(
            "Complete Payment",
            style: TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Please scan the QR code to pay for your appointment\nwith $doctorName",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black87),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Image.asset(
                'assets/images/static_qr.jpg',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: Text("Amount",
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Text(amount, style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child: Text("Transaction ID",
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Text(txnId,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Replace these with your own asset paths for payment icons
                Icon(Icons.account_balance_wallet,
                    color: Colors.black54, size: 28),
                SizedBox(width: 8),
                Icon(Icons.payment, color: Colors.blue, size: 28),
                SizedBox(width: 8),
                Icon(Icons.account_balance, color: Colors.green, size: 28),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              try {
                final token = await secureStorage.read(key: 'nodejs_token');
                print('=== BOOKING APPOINTMENT ===');
                debugPrint('=== BOOKING APPOINTMENT ===');
                print('Nodejs token from secure storage (at booking): '
                    '${token == null ? 'NULL' : (token.isEmpty ? 'EMPTY' : token)}');
                debugPrint('Nodejs token from secure storage (at booking): '
                    '${token == null ? 'NULL' : (token.isEmpty ? 'EMPTY' : token)}');

                if (token == null || token.isEmpty) {
                  print('❌ No token available for booking');
                  debugPrint('❌ No token available for booking');
                  if (context.mounted) {
                    _showSnackBar("Authentication failed. Please log in again.",
                        Colors.red);
                  }
                  return;
                }

                print('✅ Token available, proceeding with booking');
                debugPrint('✅ Token available, proceeding with booking');

                final requestBody = {
                  "doctorId": doctorId,
                  "date": date,
                  "time": time,
                  "issueDetails": "Appointment booking for consultation",
                };

                print('Booking request body: ${jsonEncode(requestBody)}');
                debugPrint('Booking request body: ${jsonEncode(requestBody)}');
                print(
                    'Authorization header: Bearer ${token.substring(0, 20)}...');
                debugPrint(
                    'Authorization header: Bearer ${token.substring(0, 20)}...');

                final response = await http.post(
                  Uri.parse('https://fitfull.onrender.com/api/doctor/book'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $token',
                  },
                  body: jsonEncode(requestBody),
                );
                print('Doctor Book API Status: ${response.statusCode}');
                print('Doctor Book API Body: ${response.body}');
                debugPrint('Doctor Book API Status: ${response.statusCode}');
                debugPrint('Doctor Book API Body: ${response.body}');
                if (response.statusCode == 200 || response.statusCode == 201) {
                  if (context.mounted) {
                    Navigator.pop(context); // Close dialog only on success
                    _showSnackBar(
                        "Payment confirmed! Your appointment is booked.",
                        Colors.green);
                  }
                } else {
                  if (context.mounted) {
                    _showSnackBar(
                        "Failed to book appointment. Please try again.",
                        Colors.red);
                  }
                }
              } catch (e, stack) {
                print("Booking error: $e");
                print("Stack trace: $stack");
                if (context.mounted) {
                  _showSnackBar("Failed to book appointment. Please try again.",
                      Colors.red);
                }
              }
            },
            child: Text("I've Paid"),
          ),
        ],
      ),
    );
  }

  void _checkStoredToken() async {
    final token = await secureStorage.read(key: 'nodejs_token');
    print('=== CHECKING STORED TOKEN ===');
    debugPrint('=== CHECKING STORED TOKEN ===');
    print('Nodejs token from secure storage (at init): '
        '${token == null ? 'NULL' : (token.isEmpty ? 'EMPTY' : token)}');
    debugPrint('Nodejs token from secure storage (at init): '
        '${token == null ? 'NULL' : (token.isEmpty ? 'EMPTY' : token)}');

    if (token != null && token.isNotEmpty) {
      print('✅ Token is stored and not empty');
      debugPrint('✅ Token is stored and not empty');
    } else {
      print('❌ Token is NULL or empty');
      debugPrint('❌ Token is NULL or empty');
    }
  }
}
