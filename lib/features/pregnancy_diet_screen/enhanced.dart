import 'dart:convert';
import 'dart:developer';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:prenova/core/constants/api_contants.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:prenova/features/auth/auth_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class EnhancedPregnancyDietScreen extends StatefulWidget {
  @override
  _EnhancedPregnancyDietScreenState createState() =>
      _EnhancedPregnancyDietScreenState();
}

class _EnhancedPregnancyDietScreenState
    extends State<EnhancedPregnancyDietScreen> with TickerProviderStateMixin {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController healthController = TextEditingController();
  final TextEditingController dietController = TextEditingController();
  final AuthService _authService = AuthService();
  
  String trimester = "First";
  bool isLoading = false;
  String? latestDietPlan;
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    weightController.dispose();
    healthController.dispose();
    dietController.dispose();
    super.dispose();
  }

  Future<void> createNewDietPlan() async {
    if (weightController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your weight');
      return;
    }
    setState(() {
      isLoading = true;
      latestDietPlan = null;
    });
    try {
      final session = _authService.currentSession;
      if (session == null) {
        _showErrorSnackBar('Please log in to create diet plans');
        return;
      }
      final token = session.accessToken;
      final requestBody = {
        "trimester": trimester,
        "weight": weightController.text.trim(),
        "health_conditions": healthController.text.trim(),
        "dietary_preference": dietController.text.trim(),
      };
      final response = await http
          .post(
            Uri.parse("${ApiContants.baseUrl}/diet/plan"),
        headers: {
          "Content-Type": "application/json", 
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: 20));
      log('Diet API response status: ${response.statusCode}');
      log('Diet API response body: ${response.body}');
      if (response.statusCode == 200) {
        setState(() {
          latestDietPlan = jsonDecode(response.body)["diet_plan"] ??
              "No diet plan received.";
        });
        } else {
        _showErrorSnackBar('Failed to generate diet plan. Please try again.');
      }
    } on http.ClientException catch (e) {
      _showErrorSnackBar('Network error. Please check your connection.');
    } on TimeoutException catch (_) {
      _showErrorSnackBar(
          'The server took too long to respond. Please try again later.');
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(LucideIcons.alertCircle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppPallete.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPallete.backgroundColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPallete.gradient1.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: trimester,
          isExpanded: true,
          dropdownColor: AppPallete.backgroundColor,
          style: TextStyle(color: AppPallete.textColor, fontSize: 16),
          icon: Icon(LucideIcons.chevronDown, color: AppPallete.gradient1),
          items: ["First", "Second", "Third"].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text("$value Trimester"),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                trimester = newValue;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.w600, 
                  color: AppPallete.textColor)),
          SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppPallete.gradient1.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              style: TextStyle(color: AppPallete.textColor, fontSize: 16),
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: AppPallete.gradient1),
                hintText: "Enter ${label.toLowerCase()}",
                hintStyle: TextStyle(
                  color: AppPallete.textColor.withOpacity(0.5),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppPallete.backgroundColor.withOpacity(0.8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppPallete.gradient1, width: 2),
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      appBar: AppBar(
        title: Text('Pregnancy Diet Plan',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: AppPallete.gradient1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(24),
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
                    border: Border.all(
                        color: AppPallete.gradient1.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.utensils,
                      size: 48,
                      color: AppPallete.gradient1,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Create Your Personalized Diet Plan",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppPallete.textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Get AI-powered nutrition recommendations tailored to your pregnancy journey",
                      style: TextStyle(
                        fontSize: 14,
                        color: AppPallete.textColor.withOpacity(0.7),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32),
              Text("Select Trimester:", 
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppPallete.textColor)),
              SizedBox(height: 8),
              _buildDropdown(),
              SizedBox(height: 24),
                _buildTextField(
                    "Weight (kg) *", weightController, LucideIcons.scale),
                _buildTextField("Health Conditions (if any)", healthController,
                    LucideIcons.heart),
                _buildTextField(
                    "Dietary Preferences", dietController, LucideIcons.leaf),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
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
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLoading ? null : createNewDietPlan,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: isLoading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Text(
                                    "Generating Diet Plan...",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    Icon(LucideIcons.sparkles,
                                        color: Colors.white),
                                  SizedBox(width: 12),
                                  Text(
                                    "Generate Diet Plan",
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32),
                if (latestDietPlan != null)
                Container(
                    width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppPallete.gradient1.withOpacity(0.2)),
                  ),
                  child: Text(
                      latestDietPlan!,
                      style:
                          TextStyle(color: AppPallete.textColor, fontSize: 16),
                    ),
                  ),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}
