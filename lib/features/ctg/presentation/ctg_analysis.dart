import 'dart:developer';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:prenova/core/constants/api_contants.dart';
import 'package:prenova/core/utils/loader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:prenova/core/theme/app_pallete.dart';
import 'dart:convert';
import 'package:prenova/features/auth/auth_service.dart';

class CTGAnalysisScreen extends StatefulWidget {
  @override
  _CTGAnalysisScreenState createState() => _CTGAnalysisScreenState();
}

class _CTGAnalysisScreenState extends State<CTGAnalysisScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  // CTG feature controllers
  final TextEditingController baselineValueController = TextEditingController();
  final TextEditingController accelerationsController = TextEditingController();
  final TextEditingController fetalMovementController = TextEditingController();
  final TextEditingController uterineContractionsController =
      TextEditingController();
  final TextEditingController lightDecelerationsController =
      TextEditingController();
  final TextEditingController severeDecelerationsController =
      TextEditingController();
  final TextEditingController prolongedDecelerationsController =
      TextEditingController();
  final TextEditingController abnormalShortTermController =
      TextEditingController();
  final TextEditingController meanShortTermController = TextEditingController();
  final TextEditingController abnormalLongTermController =
      TextEditingController();
  final TextEditingController meanValueOfLongTermController =
      TextEditingController();
  final TextEditingController histogramWidthController =
      TextEditingController();
  final TextEditingController histogramMinController = TextEditingController();
  final TextEditingController histogramMaxController = TextEditingController();
  final TextEditingController histogramPeaksController =
      TextEditingController();

  String _prediction = "";
  bool _isLoading = false;
  late Future<List<Map<String, dynamic>>> _previousSubmissions;
  Map<String, dynamic>? _lastApiResponse; // Store last API response

  // CTG feature data
  final List<Map<String, dynamic>> ctgFeatures = [
    {
      'label': 'Baseline Value',
      'controller': null,
      'icon': Icons.timeline,
      'hint': 'Normal: 110-160',
      'suffix': 'bpm',
    },
    {
      'label': 'Accelerations',
      'controller': null,
      'icon': Icons.trending_up,
      'hint': 'Count per hour',
      'suffix': '/hr',
    },
    {
      'label': 'Fetal Movement',
      'controller': null,
      'icon': Icons.child_care,
      'hint': 'Movement count',
      'suffix': 'count',
    },
    {
      'label': 'Uterine Contractions',
      'controller': null,
      'icon': Icons.compress,
      'hint': 'Contractions per hour',
      'suffix': '/hr',
    },
    {
      'label': 'Light Decelerations',
      'controller': null,
      'icon': Icons.trending_down,
      'hint': 'Count',
      'suffix': 'count',
    },
    {
      'label': 'Severe Decelerations',
      'controller': null,
      'icon': Icons.warning,
      'hint': 'Count',
      'suffix': 'count',
    },
    {
      'label': 'Prolonged Decelerations',
      'controller': null,
      'icon': Icons.hourglass_bottom,
      'hint': 'Count',
      'suffix': 'count',
    },
    {
      'label': 'Abnormal Short Term Variability',
      'controller': null,
      'icon': Icons.scatter_plot,
      'hint': 'Percentage',
      'suffix': '%',
    },
    {
      'label': 'Mean Short Term Variability',
      'controller': null,
      'icon': Icons.show_chart,
      'hint': 'Mean value',
      'suffix': 'ms',
    },
    {
      'label': 'Abnormal Long Term Variability',
      'controller': null,
      'icon': Icons.timeline,
      'hint': 'Percentage',
      'suffix': '%',
    },
    {
      'label': 'Mean Value of Long Term Variability',
      'controller': null,
      'icon': Icons.analytics,
      'hint': 'Mean value',
      'suffix': 'ms',
    },
    {
      'label': 'Histogram Width',
      'controller': null,
      'icon': Icons.bar_chart,
      'hint': 'Width value',
      'suffix': 'bpm',
    },
    {
      'label': 'Histogram Min',
      'controller': null,
      'icon': Icons.south,
      'hint': 'Minimum value',
      'suffix': 'bpm',
    },
    {
      'label': 'Histogram Max',
      'controller': null,
      'icon': Icons.north,
      'hint': 'Maximum value',
      'suffix': 'bpm',
    },
    {
      'label': 'Histogram Number of Peaks',
      'controller': null,
      'icon': Icons.signal_cellular_alt,
      'hint': 'Peak count',
      'suffix': 'count',
    },
  ];

  List<TextEditingController> controllers = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _previousSubmissions = _fetchPreviousSubmissions();
  }

  void _initializeControllers() {
    controllers = [
      baselineValueController,
      accelerationsController,
      fetalMovementController,
      uterineContractionsController,
      lightDecelerationsController,
      severeDecelerationsController,
      prolongedDecelerationsController,
      abnormalShortTermController,
      meanShortTermController,
      abnormalLongTermController,
      meanValueOfLongTermController,
      histogramWidthController,
      histogramMinController,
      histogramMaxController,
      histogramPeaksController,
    ];

    // Assign controllers to feature data
    for (int i = 0; i < ctgFeatures.length; i++) {
      ctgFeatures[i]['controller'] = controllers[i];
    }
  }

  Future<void> _predictAndSave() async {
    if (!_validateInputs()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _prediction = "";
    });

    try {
      // Get CTG parameters
      final List<double> features = controllers
          .map((controller) => double.tryParse(controller.text) ?? 0.0)
          .toList();

      // Prepare data for API call (as required by backend: expects {"features": [...]})
      final Map<String, dynamic> requestData = {
        "features": features,
      };

      log('=== API PREDICTION DEBUG ===');
      log('Request Data: $requestData');

      // Get JWT token for authentication
      final jwtToken = _authService.jwtToken;
      log('CTG: JWT Token: ' +
          (jwtToken != null ? jwtToken.substring(0, 20) + '...' : 'null'));
      if (jwtToken == null) {
        setState(() {
          _isLoading = false;
        });
        _showValidationError('Authentication error: Please log in again.');
        log('JWT Token is missing! User must be authenticated.');
        return;
      }
      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };
      log('CTG: Headers: $headers');

      // Make API call to Flask backend
      final response = await http
          .post(
            Uri.parse('https://prenova.onrender.com/fetal/predict'),
            headers: headers,
            body: jsonEncode(requestData),
          )
          .timeout(Duration(seconds: 30));

      log('CTG: Response status: ${response.statusCode}');
      log('CTG: Response body: ${response.body}');

      if (response.statusCode == 401) {
        log('=== 401 UNAUTHORIZED ERROR ===');
        log('Authentication failed: ${response.body}');
        setState(() {
          _prediction = "Error: Authentication failed. Please log in again.";
          _isLoading = false;
        });
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        log('Parsed API Response: $data');
        _processPredictionResponse(data);
      } else {
        throw Exception(
            'API request failed with status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _prediction = "Error: [31m${e.toString()}[0m";
        _isLoading = false;
      });
      log('Error in _predictAndSave: $e');
    }
  }

  // Helper method to process prediction response
  void _processPredictionResponse(Map<String, dynamic> data) {
    String prediction = '';
    String status = '';

    if (data['prediction'] != null) {
      prediction = data['prediction'].toString();
    } else if (data['result'] != null) {
      prediction = data['result'].toString();
    } else if (data['fetal_health'] != null) {
      prediction = data['fetal_health'].toString();
    } else {
      throw Exception('No prediction found in API response');
    }

    switch (prediction) {
      case '1':
      case 'normal':
      case 'Normal':
        status = 'Normal';
        break;
      case '2':
      case 'suspect':
      case 'Suspect':
        status = 'Suspect';
        break;
      case '3':
      case 'pathological':
      case 'Pathological':
        status = 'Pathological';
        break;
      default:
        status = 'Unknown';
    }

    log('Prediction Result: $prediction ($status)');

    setState(() {
      _prediction = "Fetal Health Status: $status (Prediction: $prediction)";
      _isLoading = false;
      _lastApiResponse = data; // Store the full response
    });

    _saveToDatabase(prediction, status);
    _previousSubmissions = _fetchPreviousSubmissions();
  }

  // Save prediction results to database
  Future<void> _saveToDatabase(String prediction, String status) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return;

      final List<double> features = controllers
          .map((controller) => double.tryParse(controller.text) ?? 0.0)
          .toList();

      await supabase.from('ctg').insert({
        'UID': userId,
        'baseline_value': features[0],
        'accelerations': features[1],
        'fetal_movement': features[2],
        'uterine_contractions': features[3],
        'light_decelerations': features[4],
        'severe_decelerations': features[5],
        'prolonged_decelerations': features[6],
        'abnormal_short_term_variability': features[7],
        'mean_short_term_variability': features[8],
        'abnormal_long_term_variability': features[9],
        'mean_value_of_long_term_variability': features[10],
        'histogram_width': features[11],
        'histogram_min': features[12],
        'histogram_max': features[13],
        'histogram_number_of_peaks': features[14],
        'prediction': prediction,
        'status': status,
        'created_at': DateTime.now().toIso8601String(),
      });

      log('CTG prediction saved to database successfully');
    } catch (e) {
      log('Error saving CTG prediction to database: $e');
    }
  }

  bool _validateInputs() {
    for (int i = 0; i < controllers.length; i++) {
      if (controllers[i].text.isEmpty) {
        _showValidationError('Please fill all fields');
        return false;
      }
    }

    // Additional validation for CTG ranges
    double? baseline = double.tryParse(baselineValueController.text);
    if (baseline == null || baseline < 50 || baseline > 200) {
      _showValidationError('Baseline value should be between 50-200 bpm');
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

    try {
      final response = await supabase
          .from('ctg')
          .select("*")
          .eq('UID', userId)
          .order('created_at', ascending: false);

      return response.map<Map<String, dynamic>>((data) => data).toList();
    } catch (e) {
      log('Error fetching previous CTG submissions: $e');
      return [];
    }
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
    required String suffix,
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

  Widget _buildTable(List<Map<String, dynamic>> ctgData) {
    // CORRECTED MAPPING
    Map<int, String> healthMapping = {
      1: "Normal",
      2: "Suspect",
      3: "Pathological"
    };

    Map<int, Color> healthColors = {
      1: Colors.green,
      2: Colors.orange,
      3: Colors.red,
    };

    if (ctgData.isEmpty) {
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
              'No previous CTG analyses found',
              style: TextStyle(
                color: AppPallete.textColor.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            Text(
              'Your fetal health assessments will appear here',
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
                  'Baseline\n(bpm)',
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
                  'Accelerations\n(/hr)',
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
                  'Movements\n(count)',
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
                  'Health Status',
                  style: TextStyle(
                    color: AppPallete.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            rows: ctgData.take(10).map((data) {
              // Handle both string and int prediction values
              int prediction;
              if (data['prediction'] is String) {
                prediction = int.tryParse(data['prediction']) ?? 1;
              } else if (data['prediction'] is int) {
                prediction = data['prediction'];
              } else {
                prediction = 1; // Default to Normal
              }

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      formatDate(data['created_at'].toString()),
                      style: TextStyle(color: Colors.black87, fontSize: 11),
                    ),
                  ),
                  DataCell(
                    Text(
                      data['baseline_value']?.toString() ?? 'N/A',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      data['accelerations']?.toString() ?? 'N/A',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Text(
                      data['fetal_movement']?.toString() ?? 'N/A',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: healthColors[prediction]?.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: healthColors[prediction] ?? Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        healthMapping[prediction] ?? 'Unknown',
                        style: TextStyle(
                          color: healthColors[prediction] ?? Colors.black,
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

  // Debug function to test API connectivity
  Future<void> _testAPI() async {
    log('=== API CONNECTIVITY TEST ===');
    log('Testing CTG API with current form data...');

    // Use current form data for testing
    final List<double> features = controllers
        .map((controller) => double.tryParse(controller.text) ?? 0.0)
        .toList();

    // Prepare test data for API call (as required by backend: expects {"features": [...]})
    final testData = {
      "features": features,
    };

    log('Test Data: $testData');

    final url = Uri.parse('https://prenova.onrender.com/fetal/predict');

    // Get JWT token for authentication
    final jwtToken = _authService.jwtToken;
    if (jwtToken == null) {
      _showValidationError('Authentication error: Please log in again.');
      log('JWT Token is missing! User must be authenticated.');
      return;
    }
    log('Debug - JWT Token length: [32m${jwtToken.length}[0m');
    log('Debug - JWT Token preview: [32m${jwtToken.substring(0, 20)}...[0m');

    // Prepare headers with authentication
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwtToken',
    };
    log('Debug - Headers: $headers');

    // Test 1: Test base URL accessibility
    try {
      log('=== TEST 1: Base URL Test ===');
      final baseResponse = await http
          .get(Uri.parse('https://prenova.onrender.com/'))
          .timeout(Duration(seconds: 10));
      log('Base URL Test - Status: ${baseResponse.statusCode}');
      log('Base URL Test - Body: ${baseResponse.body}');
    } catch (e) {
      log('Base URL Test - Error: $e');
    }

    // Test 2: Test the fetal prediction endpoint
    try {
      log('=== TEST 2: Fetal Prediction API Test ===');
      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode(testData),
          )
          .timeout(Duration(seconds: 30));

      log('API Test - Status: ${response.statusCode}');
      log('API Test - Headers: ${response.headers}');
      log('API Test - Body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          log('API Test - Parsed Response: $data');

          String prediction = '';
          if (data['prediction'] != null) {
            prediction = data['prediction'].toString();
          } else if (data['result'] != null) {
            prediction = data['result'].toString();
          } else if (data['fetal_health'] != null) {
            prediction = data['fetal_health'].toString();
          } else {
            prediction = 'Unknown';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ API Test: SUCCESS! Prediction: $prediction'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        } catch (e) {
          log('API Test - Error parsing response: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ API Test: SUCCESS! (Response parsing failed)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ API Test: FAILED! Status: ${response.statusCode}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      log('API Test - Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ API Test: ERROR! $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      appBar: AppBar(
        title: Text(
          'CTG Analysis',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppPallete.primaryColor,
        elevation: 0,
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
                    Icon(Icons.monitor_heart,
                        color: AppPallete.primaryColor, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fetal CTG Analysis',
                            style: TextStyle(
                              color: AppPallete.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Enter CTG measurements for fetal health assessment',
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
              ...ctgFeatures.map((feature) => _buildTextField(
                    label: feature['label'],
                    controller: feature['controller'],
                    icon: feature['icon'],
                    hint: feature['hint'],
                    suffix: feature['suffix'],
                  )),

              SizedBox(height: 32),

              // Analyze button
              Container(
                width: double.infinity,
                height: 56,
                child: _isLoading
                    ? Container(
                        child: CircularProgressIndicator(
                          // size: 30,
                          // message: "Analyzing CTG data...",
                          color: Colors.white,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _predictAndSave,
                        icon: Icon(Icons.analytics, color: Colors.white),
                        label: Text(
                          'Analyze Fetal Health',
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
                  color: AppPallete.primaryColor,
                  // gradient: LinearGradient(
                  //   colors: [Colors.pinkAccent, Colors.blue.shade400],
                  //   begin: Alignment.topLeft,
                  //   end: Alignment.bottomRight,
                  // ),
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

              // Debug button (for testing API connectivity)
              if (kDebugMode)
                Container(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _testAPI,
                    icon: Icon(Icons.bug_report, color: Colors.white),
                    label: Text(
                      'Debug API Connection',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              if (kDebugMode) SizedBox(height: 16),

              // Prediction result
              if (_lastApiResponse != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _prediction.contains('Normal')
                        ? Colors.green.withOpacity(0.1)
                        : _prediction.contains('Suspect')
                            ? Colors.orange.withOpacity(0.1)
                            : _prediction.contains('Error')
                                ? Colors.red.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _prediction.contains('Normal')
                          ? Colors.green
                          : _prediction.contains('Suspect')
                              ? Colors.orange
                              : _prediction.contains('Error')
                                  ? Colors.red
                                  : Colors.red,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      ..._lastApiResponse!.entries.map((entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              "${entry.key}: ${entry.value}",
                              style: TextStyle(
                                fontSize: 15,
                                color: AppPallete.textColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )),
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
                    'Previous CTG Analyses',
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
                          message: "Loading previous analyses...",
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

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
