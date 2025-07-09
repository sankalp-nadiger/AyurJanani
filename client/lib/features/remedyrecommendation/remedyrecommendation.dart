import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:prenova/core/theme/app_pallete.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RemedyRecommendation extends StatefulWidget {
  @override
  _RemedyRecommendationState createState() => _RemedyRecommendationState();
}

class _RemedyRecommendationState extends State<RemedyRecommendation> {
  final TextEditingController _symptomController = TextEditingController();
  final List<String> _commonSymptoms = [
    'Headache',
    'Nausea',
    'Back pain',
    'Fatigue',
    'Heartburn',
    'Swelling',
    'Constipation',
    'Cramps',
    'Mood swings',
    'Dizziness',
  ];
  final List<String> _selectedSymptoms = [];
  Map<String, dynamic>? _classifiedSymptoms;
  Map<String, dynamic>? _riskMapping;
  Map<String, dynamic>? _remedyData;
  bool _isLoading = false;
  String? _error;
  int _currentStep =
      1; // 1: symptoms, 2: classification, 3: risk mapping, 4: remedies

  final List<Map<String, List<String>>> _groupedSymptoms = [
    {
      'General': ['Fatigue', 'Dizziness', 'Mood swings', 'Headache']
    },
    {
      'Digestive': ['Nausea', 'Constipation', 'Heartburn']
    },
    {
      'Pain': ['Back pain', 'Cramps']
    },
    {
      'Physical': ['Swelling']
    },
  ];

  void _toggleSymptom(String symptom) {
    setState(() {
      // Toggle selection
      if (_selectedSymptoms.contains(symptom)) {
        _selectedSymptoms.remove(symptom);
      } else {
        _selectedSymptoms.add(symptom);
      }
      // Clear text field when chips are selected
      _symptomController.clear();
    });
  }

  Future<void> _processSymptoms() async {
    final symptoms = [..._selectedSymptoms];
    final customSymptom = _symptomController.text.trim();
    if (customSymptom.isNotEmpty) symptoms.add(customSymptom);

    // Clean and deduplicate symptoms
    final cleanSymptoms = symptoms
        .where((symptom) => symptom.trim().isNotEmpty)
        .map((symptom) => symptom.trim())
        .toSet()
        .toList();

    if (cleanSymptoms.isEmpty) {
      setState(() {
        _error = 'Please select or enter at least one symptom.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _classifiedSymptoms = null;
      _riskMapping = null;
      _remedyData = null;
    });

    try {
      print('=== REMEDY RECOMMENDATION PROCESS STARTED ===');
      debugPrint('=== REMEDY RECOMMENDATION PROCESS STARTED ===');
      print('Selected Symptoms: $_selectedSymptoms');
      debugPrint('Selected Symptoms: $_selectedSymptoms');
      print('Clean Symptoms: $cleanSymptoms');
      debugPrint('Clean Symptoms: $cleanSymptoms');

      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final token = session?.accessToken;

      print('Auth Token Available: ${token != null}');
      debugPrint('Auth Token Available: ${token != null}');

      // Step 1: Classify symptoms
      print('=== STEP 1: CLASSIFYING SYMPTOMS ===');
      debugPrint('=== STEP 1: CLASSIFYING SYMPTOMS ===');

      final classifyRequest = {'symptoms': cleanSymptoms};
      print('Classify Request: ${jsonEncode(classifyRequest)}');
      debugPrint('Classify Request: ${jsonEncode(classifyRequest)}');

      final classifyResponse = await http.post(
        Uri.parse('https://prenova.onrender.com/ayurveda/classify_symptoms'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(classifyRequest),
      );

      print('Classify Status Code: ${classifyResponse.statusCode}');
      print('Classify Headers: ${classifyResponse.headers}');
      print('Classify Body: ${classifyResponse.body}');
      debugPrint('Classify Status Code: ${classifyResponse.statusCode}');
      debugPrint('Classify Headers: ${classifyResponse.headers}');
      debugPrint('Classify Body: ${classifyResponse.body}');

      if (classifyResponse.statusCode != 200) {
        throw Exception(
            'Failed to classify symptoms: ${classifyResponse.statusCode}');
      }

      final classifiedData = jsonDecode(classifyResponse.body);
      setState(() {
        _classifiedSymptoms = classifiedData;
        _currentStep = 2;
      });

      // Step 2: Map symptom risk
      print('=== STEP 2: MAPPING SYMPTOM RISK ===');
      debugPrint('=== STEP 2: MAPPING SYMPTOM RISK ===');

      // Extract categories from classification response
      final categories = classifiedData['categories'] ?? [];
      print('Extracted Categories: $categories');
      debugPrint('Extracted Categories: $categories');

      final riskRequest = {
        'symptoms': cleanSymptoms,
        'symptom_categories': categories,
      };
      print('Risk Request: ${jsonEncode(riskRequest)}');
      debugPrint('Risk Request: ${jsonEncode(riskRequest)}');

      final riskResponse = await http.post(
        Uri.parse('https://prenova.onrender.com/ayurveda/map_symptom_risk'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(riskRequest),
      );

      print('Risk Status Code: ${riskResponse.statusCode}');
      print('Risk Headers: ${riskResponse.headers}');
      print('Risk Body: ${riskResponse.body}');
      debugPrint('Risk Status Code: ${riskResponse.statusCode}');
      debugPrint('Risk Headers: ${riskResponse.headers}');
      debugPrint('Risk Body: ${riskResponse.body}');

      if (riskResponse.statusCode != 200) {
        throw Exception(
            'Failed to map symptom risk: ${riskResponse.statusCode}');
      }

      final riskData = jsonDecode(riskResponse.body);
      setState(() {
        _riskMapping = riskData;
        _currentStep = 3;
      });

      // Step 3: Get remedies
      print('=== STEP 3: GETTING REMEDIES ===');
      debugPrint('=== STEP 3: GETTING REMEDIES ===');

      final remedyRequest = {
        'symptoms': cleanSymptoms,
      };
      print('Remedy Request: ${jsonEncode(remedyRequest)}');
      debugPrint('Remedy Request: ${jsonEncode(remedyRequest)}');

      final remedyResponse = await http.post(
        Uri.parse(
            'https://prenova.onrender.com/ayurveda/remedy_recommendation'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(remedyRequest),
      );

      print('Remedy Status Code: ${remedyResponse.statusCode}');
      print('Remedy Headers: ${remedyResponse.headers}');
      print('Remedy Body: ${remedyResponse.body}');
      debugPrint('Remedy Status Code: ${remedyResponse.statusCode}');
      debugPrint('Remedy Headers: ${remedyResponse.headers}');
      debugPrint('Remedy Body: ${remedyResponse.body}');

      if (remedyResponse.statusCode == 200) {
        final remedyData = jsonDecode(remedyResponse.body);
        setState(() {
          _remedyData = remedyData;
          _currentStep = 4;
          _isLoading = false;
        });

        print('=== REMEDY RECOMMENDATION PROCESS COMPLETED SUCCESSFULLY ===');
        debugPrint(
            '=== REMEDY RECOMMENDATION PROCESS COMPLETED SUCCESSFULLY ===');
        print('Final Remedy Data: ${jsonEncode(remedyData)}');
        debugPrint('Final Remedy Data: ${jsonEncode(remedyData)}');

        // Debug the remedy structure
        if (remedyData['remedies'] != null) {
          print('Remedies array: ${remedyData['remedies']}');
          debugPrint('Remedies array: ${remedyData['remedies']}');
          if (remedyData['remedies'] is List &&
              remedyData['remedies'].isNotEmpty) {
            print('First remedy: ${remedyData['remedies'][0]}');
            debugPrint('First remedy: ${remedyData['remedies'][0]}');
          }
        }
      } else {
        throw Exception('Failed to get remedies: ${remedyResponse.statusCode}');
      }
    } catch (e) {
      print('=== REMEDY RECOMMENDATION PROCESS FAILED ===');
      debugPrint('=== REMEDY RECOMMENDATION PROCESS FAILED ===');
      print('Error: ${e.toString()}');
      debugPrint('Error: ${e.toString()}');

      setState(() {
        _error = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _symptomController.dispose();
    super.dispose();
  }

  Widget _buildClassificationStep() {
    if (_classifiedSymptoms == null) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 20),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppPallete.gradient1.withOpacity(0.08),
            AppPallete.gradient2.withOpacity(0.06)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPallete.gradient1.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category, color: AppPallete.gradient1, size: 22),
              SizedBox(width: 8),
              Text(
                'Symptom Classification',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppPallete.gradient1,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Display all classification data dynamically
          ..._classifiedSymptoms!.entries.map((entry) {
            final key = entry.key;
            final value = entry.value;

            // Skip null or empty values
            if (value == null || value.toString().isEmpty)
              return SizedBox.shrink();

            // Map keys to display names and icons
            String displayName;
            IconData icon;

            switch (key) {
              case 'categories':
                displayName = 'Symptom Categories';
                icon = Icons.category;
                break;
              case 'confidence':
                // Skip confidence level - don't display it
                return SizedBox.shrink();
              case 'dosha_imbalance':
                displayName = 'Dosha Imbalance';
                icon = Icons.balance;
                break;
              case 'body_system':
                displayName = 'Body System';
                icon = Icons.medical_services;
                break;
              case 'severity':
                displayName = 'Severity';
                icon = Icons.warning;
                break;
              default:
                displayName = key
                    .replaceAll('_', ' ')
                    .split(' ')
                    .map((word) => word.isNotEmpty
                        ? word[0].toUpperCase() + word.substring(1)
                        : '')
                    .join(' ');
                icon = Icons.info;
            }

            return _buildClassificationItem(displayName, value, icon);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildClassificationItem(String title, dynamic value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppPallete.gradient2, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppPallete.gradient2,
                    fontSize: 14,
                  ),
                ),
                if (value is List) ...[
                  // Handle arrays (like symptom categories) with chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: (value as List).map((item) {
                      return Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppPallete.gradient1.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppPallete.gradient1.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          item
                              .toString()
                              .replaceAll('_', ' ')
                              .split(' ')
                              .map((word) => word.isNotEmpty
                                  ? word[0].toUpperCase() + word.substring(1)
                                  : '')
                              .join(' '),
                          style: TextStyle(
                            color: AppPallete.gradient1,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  // Handle regular text values
                  Text(
                    value.toString(),
                    style: TextStyle(
                      color: AppPallete.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskMappingStep() {
    if (_riskMapping == null) return SizedBox.shrink();

    // Check if there's any meaningful data to display
    final hasData = _riskMapping!.entries.any((entry) {
      final value = entry.value;
      return value != null &&
          value.toString().isNotEmpty &&
          value.toString() != 'null' &&
          value.toString() != '{}' &&
          value.toString() != '[]';
    });

    if (!hasData) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 20),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppPallete.gradient2.withOpacity(0.08),
            AppPallete.gradient1.withOpacity(0.06)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPallete.gradient2.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment, color: AppPallete.gradient2, size: 22),
              SizedBox(width: 8),
              Text(
                'Risk Assessment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppPallete.gradient2,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Display all risk mapping data dynamically
          ..._riskMapping!.entries.map((entry) {
            final key = entry.key;
            final value = entry.value;

            // Skip null or empty values
            if (value == null || value.toString().isEmpty)
              return SizedBox.shrink();

            // Map keys to display names and colors
            String displayName;
            Color color;

            switch (key) {
              case 'risk_level':
                displayName = 'Risk Level';
                color = _getRiskColor(value.toString());
                break;
              case 'recommendations':
                displayName = 'Immediate Actions';
                color = AppPallete.gradient2;
                break;
              case 'consultation_needed':
                displayName = 'Consultation Required';
                color = value == true ? Colors.red : Colors.green;
                break;
              default:
                displayName = key
                    .replaceAll('_', ' ')
                    .split(' ')
                    .map((word) => word.isNotEmpty
                        ? word[0].toUpperCase() + word.substring(1)
                        : '')
                    .join(' ');
                color = AppPallete.gradient2;
            }

            return _buildRiskItem(displayName, value, color);
          }).toList(),
        ],
      ),
    );
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return AppPallete.gradient2;
    }
  }

  String _getRemedyText(Map<String, dynamic> remedy) {
    // Try different possible field names for remedy text
    return remedy['remedy'] ??
        remedy['text'] ??
        remedy['description'] ??
        remedy['content'] ??
        remedy['details'] ??
        remedy.toString();
  }

  Widget _formatRemedyText(String text) {
    if (text.trim().isEmpty) {
      return Text(
        'No remedy details available.',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 15,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Split text into paragraphs and format them
    final paragraphs =
        text.split('\n').where((p) => p.trim().isNotEmpty).toList();

    if (paragraphs.isEmpty) {
      return _buildRichText(text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((paragraph) {
        final trimmedParagraph = paragraph.trim();

        // Check if this is a header (starts with common header patterns)
        final isHeader = trimmedParagraph.toUpperCase() == trimmedParagraph ||
            trimmedParagraph.startsWith('•') ||
            trimmedParagraph.startsWith('-') ||
            trimmedParagraph.startsWith('*') ||
            (trimmedParagraph.contains(':') && trimmedParagraph.length < 50) ||
            trimmedParagraph.toLowerCase().contains('ingredients') ||
            trimmedParagraph.toLowerCase().contains('dosage') ||
            trimmedParagraph.toLowerCase().contains('preparation') ||
            trimmedParagraph.toLowerCase().contains('usage') ||
            trimmedParagraph.toLowerCase().contains('benefits');

        if (isHeader) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Row(
              children: [
                Icon(Icons.label, color: AppPallete.gradient1, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: _buildRichText(
                    trimmedParagraph
                        .replaceAll(RegExp(r'^[•\-*]\s*'), '')
                        .trim(),
                    isHeader: true,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 26),
            child: _buildRichText(trimmedParagraph),
          );
        }
      }).toList(),
    );
  }

  Widget _buildRichText(String text, {bool isHeader = false}) {
    // Split text by ** markers to identify bold sections
    final parts = text.split('**');
    final textSpans = <TextSpan>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isNotEmpty) {
        // Even indices are normal text, odd indices are bold text
        final isBold = i % 2 == 1;

        textSpans.add(TextSpan(
          text: part,
          style: TextStyle(
            color: isHeader ? AppPallete.gradient1 : AppPallete.textColor,
            fontSize: isHeader ? 16 : 15,
            fontWeight: isBold || isHeader ? FontWeight.bold : FontWeight.w500,
            height: isHeader ? 1.4 : 1.6,
          ),
        ));
      }
    }

    return RichText(
      text: TextSpan(children: textSpans),
    );
  }

  Widget _buildRiskItem(String title, dynamic value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                Text(
                  value.toString(),
                  style: TextStyle(
                    color: AppPallete.textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remedy Recommendation'),
        backgroundColor: AppPallete.gradient1,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress indicator
            if (_isLoading || _currentStep > 1) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPallete.gradient1.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Processing Step $_currentStep of 4',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppPallete.gradient1,
                          ),
                        ),
                        if (_isLoading)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppPallete.gradient1,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _currentStep / 4,
                      backgroundColor: Colors.grey[300],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppPallete.gradient1),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
            ],

            // Step 1: Symptom Selection
            if (_currentStep == 1 || _isLoading) ...[
              Text(
                'Select your symptoms:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppPallete.gradient1,
                ),
              ),
              SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _groupedSymptoms.map((group) {
                  final groupName = group.keys.first;
                  final symptoms = group[groupName]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 4),
                          child: Text(
                            groupName,
                            style: TextStyle(
                              color: AppPallete.gradient2,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: symptoms.map((symptom) {
                            final selected =
                                _selectedSymptoms.contains(symptom);
                            return ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(symptom,
                                      style: TextStyle(
                                          color: AppPallete.textColor,
                                          fontWeight: FontWeight.w600)),
                                  if (selected) ...[
                                    SizedBox(width: 6),
                                    Icon(Icons.check,
                                        color: Colors.white, size: 18),
                                  ]
                                ],
                              ),
                              selected: selected,
                              onSelected: (_) => _toggleSymptom(symptom),
                              selectedColor: AppPallete.gradient1,
                              backgroundColor: Colors.grey[200],
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 24),
              Text(
                'Or enter a custom symptom:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppPallete.gradient2,
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: _symptomController,
                decoration: InputDecoration(
                  hintText: 'Type your symptom...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: TextStyle(fontSize: 15, color: Colors.black),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.search, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPallete.gradient1,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  label: Text('Analyze Symptoms',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  onPressed: _isLoading ? null : _processSymptoms,
                ),
              ),
            ],

            // Step 2: Classification Results
            if (_currentStep >= 2) _buildClassificationStep(),

            // Step 3: Risk Mapping Results
            if (_currentStep >= 3) _buildRiskMappingStep(),

            // Step 4: Remedies
            if (_currentStep >= 4 && _remedyData != null) ...[
              SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppPallete.gradient1.withOpacity(0.09),
                      AppPallete.gradient2.withOpacity(0.07)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.08),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.healing,
                            color: AppPallete.gradient1, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Ayurvedic Remedies',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppPallete.gradient1,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    if (_remedyData?['prakriti'] != null &&
                        (_remedyData?['prakriti'] as String).trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(Icons.person,
                                color: AppPallete.gradient2, size: 22),
                            SizedBox(width: 8),
                            Text('Prakriti: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppPallete.gradient2,
                                    fontSize: 16)),
                            Expanded(
                              child: Text(
                                _remedyData?['prakriti'],
                                style: TextStyle(
                                    color: AppPallete.textColor, fontSize: 16),
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_remedyData?['remedies'] != null &&
                        (_remedyData?['remedies'] as List).isNotEmpty) ...[
                      // Display all remedies in the array
                      ...(_remedyData!['remedies'] as List).map((remedy) {
                        final remedyText = _getRemedyText(remedy);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _formatRemedyText(remedyText),
                        );
                      }).toList(),
                    ] else if (_remedyData?['remedy'] != null) ...[
                      // If remedy is directly in the response
                      _formatRemedyText(_remedyData!['remedy'] ?? ''),
                    ] else if (_remedyData?['recommendation'] != null) ...[
                      // If recommendation field exists
                      _formatRemedyText(_remedyData!['recommendation'] ?? ''),
                    ] else ...[
                      // Show raw response for debugging
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.bug_report, color: Colors.blue[700]),
                                SizedBox(width: 8),
                                Text(
                                  'Debug: Full Response',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              jsonEncode(_remedyData),
                              style: TextStyle(
                                color: Colors.blue[900],
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
