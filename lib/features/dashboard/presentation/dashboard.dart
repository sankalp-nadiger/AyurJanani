import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:prenova/core/utils/loader.dart';
import 'package:prenova/core/utils/pregnancy_utils.dart';
import 'package:prenova/core/widgets/services_modal.dart';
import 'package:prenova/features/BabyStatus/models/pregnancy_stage_model.dart';
import 'package:prenova/features/BabyStatus/presentation/pregnancy_week_screen.dart';
import 'package:prenova/features/BabyStatus/presentation/pregnancy_stages_screen.dart';
import 'package:prenova/features/BabyStatus/services/pregnancy_stage_service.dart';
import 'package:prenova/features/MedicalDocuments/medical_documents.dart';
import 'package:prenova/features/auth/auth_service.dart';
import 'package:prenova/features/auth/presentation/Profilepage.dart';
import 'package:prenova/features/ctg/presentation/ctg_analysis.dart';
import 'package:prenova/features/contraction/presentation/contraction_timer.dart';
import 'package:prenova/features/medicine_tracker/models/medication_model.dart';
import 'package:prenova/features/medicine_tracker/presentation/medicine_tracker_screen.dart';
import 'package:prenova/features/medicine_tracker/services/medication_storage_service.dart';
import 'package:prenova/features/pregnancy_diet_screen/enhanced.dart';
import 'package:prenova/features/pregnancy_risk/presentation/pregnancy_risk.dart';
import 'package:prenova/features/kick_tracker/presentation/kick_tracker.dart';
import 'package:prenova/features/chatbot/presentation/chatbot.dart';
import 'package:prenova/features/pregnancy_diet_screen/pregnancy_diet_screen.dart';
import 'package:prenova/features/doctor_cons/presentation/doctor_consultation.dart';
import 'package:prenova/features/services/presentation/services_hub.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:prenova/features/remedyrecommendation/remedyrecommendation.dart';
import 'package:prenova/features/pending_appointments/presentation/pending_appointments_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final authService = AuthService();
  final SupabaseClient supabase = Supabase.instance.client;
  final MedicationStorageService _storageService = MedicationStorageService();

  String userName = "Mom to be.....";
  PregnancyStageModel? currentBabyStage;
  bool isLoadingBabyState = true;
  late AnimationController _animationController;
  List<Medication> _medications = [];
  List<MedicationLog> _todayLogs = [];
  late Future<List<Map<String, dynamic>>> _pendingAppointmentsFuture;
  // List<String> _recommendations = [];
  // bool _isLoadingRecommendations = false;
  // String? _recommendationsError;
  // Map<String, dynamic>? _recommendationsData;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );
    _fetchUserData();
    _loadMedicationData();
    _pendingAppointmentsFuture = _fetchPendingAppointments();
    // _fetchRecommendations();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    await _fetchUserName();
    await _fetchCurrentBabyState();
  }

  Future<void> _loadMedicationData() async {
    final medications = await _storageService.getMedications();
    final logs = await _storageService.getLogsForDate(DateTime.now());

    setState(() {
      _medications = medications.where((med) => med.isActive).toList();
      _todayLogs = logs;
    });
  }

  Future<void> _fetchUserName() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('profiles')
        .select('user_name')
        .eq('UID', user.id)
        .maybeSingle();

    if (response != null) {
      setState(() {
        userName = response['user_name'] ?? "Unknown";
      });
    }
  }

  Future<void> _fetchCurrentBabyState() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('profiles')
          .select('expected_due_date, pregnancy_trimester')
          .eq('UID', user.id)
          .maybeSingle();

      if (response != null) {
        int currentWeek = 1;

        // Try to calculate from due date first
        if (response['expected_due_date'] != null) {
          currentWeek = PregnancyUtils.getCurrentPregnancyWeek(
              response['expected_due_date']);
        } else if (response['pregnancy_trimester'] != null) {
          // Fallback to trimester-based calculation
          currentWeek = PregnancyUtils.getWeekFromTrimester(
              response['pregnancy_trimester']);
        }

        // Load pregnancy stages and find current week
        final stages = await PregnancyStagesService.loadPregnancyStages();
        final currentStage = stages.firstWhere(
          (stage) => stage.week == currentWeek,
          orElse: () => stages.first,
        );

        setState(() {
          currentBabyStage = currentStage;
          isLoadingBabyState = false;
        });
      }
    } catch (e) {
      print('Error fetching baby state: $e');
      setState(() {
        isLoadingBabyState = false;
      });
    }
  }

  // Future<void> _fetchRecommendations() async {
  //   setState(() {
  //     _isLoadingRecommendations = true;
  //     _recommendationsError = null;
  //   });
  //   try {
  //     final user = supabase.auth.currentSession;
  //     final token = user?.accessToken;
  //     final response = await http.get(
  //       Uri.parse('https://prenova.onrender.com/recommendations/'),
  //       headers: {
  //         if (token != null) 'Authorization': 'Bearer $token',
  //       },
  //     );
  //     print('=== RECOMMENDATIONS API RESPONSE ===');
  //     print('Status: \\${response.statusCode}');
  //     print('Body: \\${response.body}');
  //     debugPrint('=== RECOMMENDATIONS API RESPONSE ===');
  //     debugPrint('Status: \\${response.statusCode}');
  //     debugPrint('Body: \\${response.body}');
  //     debugPrint('====================================');
  //     if (response.statusCode == 200) {
  //       final data = jsonDecode(response.body);
  //       setState(() {
  //         _recommendationsData = data;
  //         _isLoadingRecommendations = false;
  //       });
  //     } else {
  //       setState(() {
  //         _recommendationsError = 'Failed to load recommendations.';
  //         _isLoadingRecommendations = false;
  //       });
  //     }
  //   } catch (e) {
  //     setState(() {
  //       _recommendationsError = 'Error: \\${e.toString()}';
  //       _isLoadingRecommendations = false;
  //     });
  //   }
  // }

  int _currentIndex = 2;

  @override
  Widget build(BuildContext context) {
    setState(() {
      _fetchUserName();
    });

    final List<Map<String, dynamic>> dashboardItems = [
      {
        'title': 'Fetal Health\nMonitoring',
        'icon': LucideIcons.baby,
        'color': AppPallete.gradient1,
        'onPressed': () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => CTGAnalysisScreen()));
        }
      },
      {
        'title': 'Vitals\nMonitoring',
        'icon': LucideIcons.heartPulse,
        'color': AppPallete.gradient2,
        'onPressed': () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => PregnancyRiskScreen()));
        }
      },
      {
        'title': 'Kick\nTracker',
        'icon': LucideIcons.footprints,
        'color': AppPallete.gradient3,
        'onPressed': () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => KickTrackerScreen()));
        }
      },
      {
        'title': 'Contraction\nTracker',
        'icon': LucideIcons.timer,
        'color': AppPallete.gradient2,
        'onPressed': () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => ContractionTrackerScreen()));
        }
      },
      // Removed 'Your Pending Appointments' from grid, will show inline below baby status
    ];

    final List<Widget> bottomNavScreens = [
      PregnancyChatScreen(),
      EnhancedPregnancyDietScreen(),
      DashboardScreen(),
      PregnancyStagesScreen(),
      // Remove ServicesHub() since we're using modal instead
      DashboardScreen(), // Placeholder to maintain index consistency
    ];

    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPallete.gradient1, AppPallete.gradient2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: AppPallete.gradient1.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 28,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.account_circle, size: 32, color: Colors.white),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => ProfilePage()));
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppPallete.backgroundColor,
              AppPallete.gradient3.withOpacity(0.05),
              AppPallete.backgroundColor,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 24),

                  // Today's Medication Overview
                  FadeTransition(
                    opacity: _animationController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(-0.3, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOutBack,
                      )),
                      child: _buildTodayOverview(),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Current baby state card
                  FadeTransition(
                    opacity: _animationController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(0.3, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOutBack,
                      )),
                      child: _buildCurrentBabyStateCard(),
                    ),
                  ),

                  FadeTransition(
                    opacity: _animationController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOutBack,
                      )),
                      child: _buildPendingAppointmentsInline(context),
                    ),
                  ),

                  // Recommendations Section removed for now
                  SizedBox(height: 20),
                  FadeTransition(
                    opacity: _animationController,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOutBack,
                      )),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: dashboardItems.length,
                        itemBuilder: (context, index) {
                          // Skip the first 4 features (now in menu)
                          if (index < 4) return SizedBox.shrink();
                          return _buildDashboardCard(
                              dashboardItems[index], index);
                        },
                      ),
                    ),
                  ),

                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      drawer: _FeatureDrawer(dashboardItems: dashboardItems.sublist(0, 4)),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [
            BoxShadow(
              color: AppPallete.gradient1.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              // Special handling for Smart Med tab (index 4)
              if (index == 4) {
                // Show services modal instead of navigating
                ServicesModal.show(context);
                return;
              }

              // For other tabs, navigate normally
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => bottomNavScreens[index],
                  transitionsBuilder: (_, animation, __, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
              );
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppPallete.gradient1,
            unselectedItemColor: AppPallete.borderColor,
            selectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentIndex == 0
                        ? AppPallete.gradient1.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.bot, size: 24),
                ),
                label: 'Ask Nova',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentIndex == 1
                        ? AppPallete.gradient1.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.utensils, size: 24),
                ),
                label: 'Diet Plan',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentIndex == 2
                        ? AppPallete.gradient1.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.home, size: 24),
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentIndex == 3
                        ? AppPallete.gradient1.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.calendar, size: 24),
                ),
                label: 'Miracle Map',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentIndex == 4
                        ? AppPallete.gradient1.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.local_hospital, size: 24),
                ),
                label: 'Smart Med',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayOverview() {
    final totalDoses = _getTotalDosesForToday();
    final takenDoses = _todayLogs.where((log) => log.isTaken).length;
    final adherenceRate =
        totalDoses > 0 ? (takenDoses / totalDoses * 100) : 0.0;

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppPallete.gradient1, AppPallete.gradient2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppPallete.gradient1.withOpacity(0.3),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => MedicineTrackerScreen()),
          );
          if (result == true) _loadMedicationData();
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(LucideIcons.pill, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Today\'s Medication Progress',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Icon(
                  LucideIcons.arrowRight,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOverviewStat('Taken', '$takenDoses', LucideIcons.check),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.3),
                ),
                _buildOverviewStat('Total', '$totalDoses', LucideIcons.pill),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.3),
                ),
                _buildOverviewStat(
                    'Rate', '${adherenceRate.toInt()}%', LucideIcons.target),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  int _getTotalDosesForToday() {
    int total = 0;
    for (var medication in _medications) {
      total += medication.times.length;
    }
    return total;
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
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
      child: Column(
        children: [
          // // Text(
          // //   "Hello, $userName 👋",
          // //   style: TextStyle(
          // //     fontSize: 26,
          // //     fontWeight: FontWeight.bold,
          // //     color: AppPallete.gradient1,
          // //     letterSpacing: 0.5,
          // //   ),
          // //   textAlign: TextAlign.center,
          // // ),
          // SizedBox(height: 8),
          // Text(
          //   "What would you like to do today?",
          //   style: TextStyle(
          //     fontSize: 16,
          //     color: AppPallete.borderColor,
          //     fontWeight: FontWeight.w500,
          //   ),
          //   textAlign: TextAlign.center,
          // ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(Map<String, dynamic> item, int index) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 600 + (index * 100)),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Transform.scale(
          scale: value,
          child: GestureDetector(
            onTap: item['onPressed'],
            child: Container(
              decoration: BoxDecoration(
                //
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: item['color'].withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: item['onPressed'],
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                item['color'].withOpacity(0.1),
                                item['color'].withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            item['icon'],
                            size: 32,
                            color: item['color'],
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          item['title'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppPallete.textColor,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentBabyStateCard() {
    // Show loader if data is still being fetched
    if (isLoadingBabyState) {
      return Container(
        height: 140,
        width: double.infinity,
        decoration: _buildCardDecoration(),
        child: const Center(
          child: CustomLoader(color: Colors.white),
        ),
      );
    }

    // If no baby stage data available, return empty widget
    if (currentBabyStage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 140,
      width: double.infinity,
      decoration: _buildCardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PregnancyWeekDetailScreen(stage: currentBabyStage!),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildBabyImage(),
                const SizedBox(width: 20),
                Expanded(child: _buildBabyDetails()),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppPallete.gradient1,
          AppPallete.gradient2,
          AppPallete.gradient3,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppPallete.gradient1.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildBabyImage() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: currentBabyStage!.imagePath.isNotEmpty
            ? Image.asset(
                currentBabyStage!.imagePath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackImage();
                },
              )
            : _buildFallbackImage(),
      ),
    );
  }

  Widget _buildFallbackImage() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.baby_changing_station,
        color: Colors.white,
        size: 36,
      ),
    );
  }

  Widget _buildBabyDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Current Baby status',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          currentBabyStage!.title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Size: ${currentBabyStage!.babySize}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // Widget _buildRecommendationsSection() { /* ...commented out... */ }

  Widget _buildPendingAppointmentsInline(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _pendingAppointmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.symmetric(vertical: 16),
            padding: EdgeInsets.all(24),
            decoration: _buildCardDecoration(),
            child: Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 16),
                Text('Loading pending appointments...',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Container(
            margin: EdgeInsets.symmetric(vertical: 16),
            padding: EdgeInsets.all(24),
            decoration: _buildCardDecoration(),
            child: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 28),
                SizedBox(width: 16),
                Text('Error loading appointments',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          );
        }
        final appointments = snapshot.data ?? [];
        if (appointments.isEmpty) {
          return Container(
            margin: EdgeInsets.symmetric(vertical: 16),
            padding: EdgeInsets.all(24),
            decoration: _buildCardDecoration(),
            child: Row(
              children: [
                Icon(LucideIcons.calendarClock, color: Colors.white, size: 28),
                SizedBox(width: 16),
                Text('No pending appointments',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          );
        }
        // Show up to 2 upcoming appointments
        final upcoming = appointments.take(2).toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              margin: EdgeInsets.symmetric(vertical: 16),
              padding: EdgeInsets.all(24),
              decoration: _buildCardDecoration(),
              width: constraints.maxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.calendarClock,
                          color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('Your Pending Appointments',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      PendingAppointmentsScreen()));
                        },
                        child: Text('View All',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              AppPallete.gradient2.withOpacity(0.2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...upcoming.map((appt) {
                          final dateTime =
                              DateTime.tryParse(appt['startTime'] ?? '') ??
                                  DateTime.now();
                          final dateStr =
                              '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
                          final timeStr =
                              '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
                          final doctor = appt['doctor'] ?? {};
                          final doctorName =
                              doctor['fullName'] ?? doctor['name'] ?? 'Unknown';
                          final issueDetails = appt['issueDetails'] ?? '';
                          return Container(
                            margin: EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppPallete.gradient1.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Dr. $doctorName',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppPallete.textColor,
                                        fontSize: 16)),
                                SizedBox(height: 4),
                                Text('Date: $dateStr',
                                    style: TextStyle(
                                        color: AppPallete.textColor
                                            .withOpacity(0.7))),
                                Text('Time: $timeStr',
                                    style: TextStyle(
                                        color: AppPallete.textColor
                                            .withOpacity(0.7))),
                                if (issueDetails.isNotEmpty)
                                  Text('Reason: $issueDetails',
                                      style: TextStyle(
                                          color: AppPallete.textColor
                                              .withOpacity(0.7))),
                                SizedBox(height: 2),
                                Text('Status: ${appt['status']}',
                                    style: TextStyle(
                                        color: AppPallete.gradient2,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPendingAppointments() async {
    try {
      final storage = FlutterSecureStorage();
      final token = await storage.read(key: 'nodejs_token');
      if (token == null || token.isEmpty) return [];
      final response = await http.get(
        Uri.parse('https://fitfull.onrender.com/api/doctor/active'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
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
        return [];
      }
    } catch (e) {
      return [];
    }
  }
}

// Drawer for feature menu
class _FeatureDrawer extends StatelessWidget {
  final List<Map<String, dynamic>> dashboardItems;
  const _FeatureDrawer({required this.dashboardItems});

  @override
  Widget build(BuildContext context) {
    // Add Remedy Recommendation feature
    final List<Map<String, dynamic>> features = [
      ...dashboardItems,
      {
        'title': 'Remedy Recommendation',
        'icon': Icons.healing, // You can use LucideIcons.medkit if imported
        'color': AppPallete.gradient3,
        'onPressed': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RemedyRecommendation()),
          );
        },
      },
    ];
    return Drawer(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppPallete.gradient1, AppPallete.gradient2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(28),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.10),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.favorite,
                          color: AppPallete.gradient1, size: 32),
                    ),
                    SizedBox(width: 18),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ayu',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Quick Access',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18),
              ...features.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Material(
                      color: Colors.transparent,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.pop(context);
                          item['onPressed']();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: item['color'].withOpacity(0.13),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: item['color'].withOpacity(0.08),
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.symmetric(
                              vertical: 18, horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: item['color'].withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(item['icon'],
                                    color: item['color'], size: 28),
                              ),
                              SizedBox(width: 18),
                              Expanded(
                                child: Text(
                                  item['title']
                                      .toString()
                                      .replaceAll('\\n', ' '),
                                  style: TextStyle(
                                    color: AppPallete.gradient1,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  color: AppPallete.gradient2, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              Spacer(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                child: Text(
                  'Ayu Dashboard',
                  style: TextStyle(
                    color: AppPallete.gradient2,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
