import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:prenova/core/constants/api_contants.dart';
import 'package:prenova/core/utils/loader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:prenova/core/theme/app_pallete.dart';
import 'dart:convert';
import 'package:prenova/features/auth/auth_service.dart';

class PregnancyRiskScreen extends StatefulWidget {
  @override
  _PregnancyRiskScreenState createState() => _PregnancyRiskScreenState();
}

class _PregnancyRiskScreenState extends State<PregnancyRiskScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final TextEditingController ageController = TextEditingController();
  final TextEditingController systolicBPController = TextEditingController();
  final TextEditingController diastolicBPController = TextEditingController();
  final TextEditingController bloodGlucoseController = TextEditingController();
  final TextEditingController bodyTempController = TextEditingController();
  final TextEditingController heartRateController = TextEditingController();
  final AuthService _authService = AuthService();

  String _prediction = "";
  bool _isLoading = false;
  String _selectedTempUnit = 'Celsius';
  late Future<List<Map<String, dynamic>>> _previousSubmissions;

  @override
  void initState() {
    super.initState();
    _previousSubmissions = _fetchPreviousSubmissions();
  }

  double _convertToFahrenheit(double temp, String unit) {
    if (unit == 'Celsius') {
      return (temp * 9 / 5) + 32;
    }
    return temp; // Already in Fahrenheit
  }

  Future<void> _predictAndSave() async {
    // Validate inputs
    if (!_validateInputs()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _prediction = "";
    });

    const int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final url = Uri.parse('https://prenova.onrender.com/maternal/predict');
        final session = _authService.currentSession;
        final token = session?.accessToken;
        log('Supabase JWT token: ' + (token ?? 'NULL'));

        if (token == null) {
          setState(() {
            _prediction = "Error: User not authenticated (no JWT token)";
            _isLoading = false;
          });
          return;
        }

        // Convert temperature to Fahrenheit
        double tempInCelsius = double.tryParse(bodyTempController.text) ?? 0.0;
        double tempInFahrenheit =
            _convertToFahrenheit(tempInCelsius, _selectedTempUnit);

        // Prepare request body as per backend model
        final requestBody = {
          "age": double.tryParse(ageController.text) ?? 0.0,
          "systolic_bp": double.tryParse(systolicBPController.text) ?? 0.0,
          "diastolic_bp": double.tryParse(diastolicBPController.text) ?? 0.0,
          "blood_glucose": double.tryParse(bloodGlucoseController.text) ?? 0.0,
          "body_temp": tempInFahrenheit,
          "heart_rate": double.tryParse(heartRateController.text) ?? 0.0,
        };
        log('Request payload: ' + jsonEncode(requestBody));

        final response = await http
            .post(
              url,
              headers: {
                "Content-Type": "application/json",
                'Authorization': 'Bearer $token',
                'Connection': 'keep-alive',
              },
              body: jsonEncode(requestBody),
            )
            .timeout(Duration(seconds: 30));

        // Print the full backend response for debugging
        print('Backend response status: \\${response.statusCode}');
        print('Backend response body: \\${response.body}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          log('API Response: ${response.body}');

          // Show all fields from the API response in the prediction card
          String result = data['prediction']?.toString() ?? 'Unknown';
          Map<String, int> predictionMapping = {
            'Normal': 0,
            'Suspect': 1,
            'Pathological': 2,
          };
          int numericResult = predictionMapping[result] ?? 0;

          // Get current user ID for UID field
          final userId = _authService.currentUser?.id;
          if (userId != null) {
            await supabase.from('vitals').insert({
              "UID": userId,
              "systolic_bp": double.tryParse(systolicBPController.text) ?? 0.0,
              "diastolic_bp":
                  double.tryParse(diastolicBPController.text) ?? 0.0,
              "blood_glucose":
                  double.tryParse(bloodGlucoseController.text) ?? 0.0,
              "body_temp": tempInFahrenheit,
              "heart_rate": double.tryParse(heartRateController.text) ?? 0.0,
              "prediction": numericResult,
              "created_at": DateTime.now().toIso8601String(),
            });

            setState(() {
              _prediction =
                  data.entries.map((e) => "${e.key}: ${e.value}").join("\n");
              _previousSubmissions = _fetchPreviousSubmissions();
              _isLoading = false;
            });
            return;
          } else {
            setState(() {
              _prediction = "Error: User not authenticated";
              _isLoading = false;
            });
            return;
          }
        } else {
          setState(() {
            _prediction = "Error: ${response.statusCode}";
            _isLoading = false;
          });
          return;
        }
      } on http.ClientException catch (e) {
        retryCount++;
        log('Connection error (attempt $retryCount/$maxRetries): ${e.message}');

        if (retryCount >= maxRetries) {
          setState(() {
            _prediction =
                "Connection failed. Please check your network and try again.";
            _isLoading = false;
          });
          return;
        }

        // Wait before retrying
        await Future.delayed(Duration(seconds: 2 * retryCount));
      } catch (e) {
        setState(() {
          _prediction =
              "Network error. Please check your connection and try again.";
          _isLoading = false;
        });
        log('Unexpected error: ${e.toString()}');
        return;
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  bool _validateInputs() {
    if (ageController.text.isEmpty ||
        systolicBPController.text.isEmpty ||
        diastolicBPController.text.isEmpty ||
        bloodGlucoseController.text.isEmpty ||
        bodyTempController.text.isEmpty ||
        heartRateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Additional validation for reasonable ranges
    double? age = double.tryParse(ageController.text);
    if (age == null || age < 10 || age > 60) {
      _showValidationError('Age should be between 10-60 years');
      return false;
    }

    double? systolic = double.tryParse(systolicBPController.text);
    if (systolic == null || systolic < 70 || systolic > 300) {
      _showValidationError('Systolic BP should be between 70-300 mmHg');
      return false;
    }

    return true;
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPreviousSubmissions() async {
    final userId = _authService.currentUser?.id;
    if (userId == null) {
      return [];
    }

    final response = await supabase
        .from('vitals')
        .select("*")
        .eq('UID', userId)
        .order('created_at', ascending: false);

    return response.map<Map<String, dynamic>>((data) => data).toList();
  }

  String formatDate(String dateString) {
    DateTime dateTime = DateTime.parse(dateString);
    return "${dateTime.day.toString().padLeft(2, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    String? suffix,
    Widget? suffixWidget,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: TextStyle(
          color: AppPallete.textColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            color: AppPallete.textColor.withOpacity(0.8),
            fontSize: 14,
          ),
          hintStyle: TextStyle(
            color: AppPallete.textColor.withOpacity(0.5),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: AppPallete.primaryColor,
            size: 20,
          ),
          suffixText: suffix,
          suffix: suffixWidget,
          suffixStyle: TextStyle(
            color: AppPallete.textColor.withOpacity(0.7),
            fontSize: 12,
          ),
          filled: true,
          fillColor: AppPallete.backgroundColor.withOpacity(0.8),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.grey.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppPallete.primaryColor,
              width: 2.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.red,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemperatureField() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: bodyTempController,
        keyboardType: TextInputType.number,
        style: TextStyle(
          color: AppPallete.textColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: 'Body Temperature',
          hintText: _selectedTempUnit == 'Celsius' ? '36.5' : '98.6',
          labelStyle: TextStyle(
            color: AppPallete.textColor.withOpacity(0.8),
            fontSize: 14,
          ),
          hintStyle: TextStyle(
            color: AppPallete.textColor.withOpacity(0.5),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.thermostat,
            color: AppPallete.primaryColor,
            size: 20,
          ),
          suffix: Container(
            padding: EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppPallete.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedTempUnit,
              underline: SizedBox(),
              icon: Icon(Icons.arrow_drop_down,
                  color: AppPallete.primaryColor, size: 16),
              style: TextStyle(color: AppPallete.textColor, fontSize: 12),
              items: ['Celsius', 'Fahrenheit'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value == 'Celsius' ? '°C' : '°F'),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedTempUnit = newValue!;
                });
              },
            ),
          ),
          filled: true,
          fillColor: AppPallete.backgroundColor.withOpacity(0.8),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.grey.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppPallete.primaryColor,
              width: 2.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> vitals) {
    Map<int, String> riskMapping = {
      0: "Normal",
      1: "Suspect",
      2: "Pathological"
    };

    Map<int, Color> riskColors = {
      0: Colors.green,
      1: Colors.orange,
      2: Colors.red,
    };

    if (vitals.isEmpty) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppPallete.backgroundColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.history, color: Colors.grey, size: 48),
            SizedBox(height: 12),
            Text(
              'No previous submissions found',
              style: TextStyle(
                color: AppPallete.textColor.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            Text(
              'Your pregnancy risk assessments will appear here',
              style: TextStyle(
                color: AppPallete.textColor.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(
                AppPallete.primaryColor.withOpacity(0.1)),
            dataRowColor: MaterialStateProperty.resolveWith((states) {
              return Colors.white;
            }),
            columnSpacing: 16,
            horizontalMargin: 16,
            columns: [
              DataColumn(
                label: Text(
                  'Date',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Sys BP\n(mmHg)',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              DataColumn(
                label: Text(
                  'Dia BP\n(mmHg)',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              DataColumn(
                label: Text(
                  'Glucose\n(mg/dL)',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              DataColumn(
                label: Text(
                  'Temp\n(°F)',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              DataColumn(
                label: Text(
                  'HR\n(bpm)',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              DataColumn(
                label: Text(
                  'Risk Level',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            rows: vitals.take(10).map((vital) {
              int prediction = vital['prediction'] ?? 0;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      formatDate(vital['created_at'].toString()),
                      style: TextStyle(color: Colors.black87, fontSize: 11),
                    ),
                  ),
                  DataCell(
                    Text(
                      vital['systolic_bp'].toString(),
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      vital['diastolic_bp'].toString(),
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      vital['blood_glucose'].toString(),
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      vital['body_temp'].toStringAsFixed(1),
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      vital['heart_rate'].toString(),
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: riskColors[prediction]?.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: riskColors[prediction] ?? Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        riskMapping[prediction] ??
                            vital['prediction'].toString(),
                        style: TextStyle(
                          color: riskColors[prediction] ?? Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
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
          'Pregnancy Risk Assessment',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppPallete.primaryColor,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppPallete.primaryColor, AppPallete.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _previousSubmissions = _fetchPreviousSubmissions();
          });
          return Future<void>.value();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppPallete.primaryColor.withOpacity(0.1),
                      AppPallete.highlightColor.withOpacity(0.05)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppPallete.primaryColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.health_and_safety,
                        color: AppPallete.primaryColor, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Health Vitals Input',
                            style: TextStyle(
                              color: AppPallete.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Please enter your current health measurements',
                            style: TextStyle(
                              color: AppPallete.textColor.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Input fields
              _buildTextField(
                label: 'Age',
                controller: ageController,
                icon: Icons.cake,
                hint: 'Enter your age',
                suffix: 'years',
              ),
              _buildTextField(
                label: 'Systolic Blood Pressure',
                controller: systolicBPController,
                icon: Icons.favorite,
                hint: 'Normal: 90-120',
                suffix: 'mmHg',
              ),
              _buildTextField(
                label: 'Diastolic Blood Pressure',
                controller: diastolicBPController,
                icon: Icons.favorite_border,
                hint: 'Normal: 60-80',
                suffix: 'mmHg',
              ),
              _buildTextField(
                label: 'Blood Glucose Level',
                controller: bloodGlucoseController,
                icon: Icons.water_drop,
                hint: 'Normal: 70-100',
                suffix: 'mg/dL',
              ),
              _buildTemperatureField(),
              _buildTextField(
                label: 'Heart Rate',
                controller: heartRateController,
                icon: Icons.monitor_heart,
                hint: 'Normal: 60-100',
                suffix: 'bpm',
              ),

              SizedBox(height: 32),

              // Predict button
              Container(
                width: double.infinity,
                height: 56,
                child: _isLoading
                    ? Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              AppPallete.primaryColor.withOpacity(0.7),
                              AppPallete.accentColor.withOpacity(0.7)
                            ],
                          ),
                        ),
                        child: CustomLoader(
                          size: 30,
                          message: "Analyzing your vitals...",
                          color: Colors.white,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _predictAndSave,
                        icon: Icon(Icons.analytics, color: Colors.white),
                        label: Text(
                          'Analyze Risk Level',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ).copyWith(
                          backgroundColor:
                              MaterialStateProperty.all(Colors.transparent),
                        ),
                      ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppPallete.primaryColor, AppPallete.accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Prediction result
              if (_prediction.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _prediction.contains('Normal')
                        ? Colors.green.withOpacity(0.1)
                        : _prediction.contains('Suspect')
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _prediction.contains('Normal')
                          ? Colors.green
                          : _prediction.contains('Suspect')
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _prediction.contains('Normal')
                            ? Icons.check_circle
                            : _prediction.contains('Suspect')
                                ? Icons.warning
                                : Icons.error,
                        color: _prediction.contains('Normal')
                            ? Colors.green
                            : _prediction.contains('Suspect')
                                ? Colors.orange
                                : Colors.red,
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        _prediction,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppPallete.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 40),

              // Previous submissions header
              Row(
                children: [
                  Icon(Icons.history, color: AppPallete.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Previous Assessments',
                    style: TextStyle(
                      color: AppPallete.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // Previous submissions table
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _previousSubmissions,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 200,
                      child: Center(
                        child: SimpleCustomLoader(
                          size: 40,
                          message: "Loading previous assessments...",
                          color: AppPallete.gradient1,
                        ),
                      ),
                    );
                  }
                  return _buildTable(snapshot.data ?? []);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
