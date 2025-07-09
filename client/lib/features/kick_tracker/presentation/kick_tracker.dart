import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

class KickSession {
  final String id;
  final int kickCount;
  final int duration;
  final DateTime createdAt;
  final List<FlSpot> data;

  KickSession({
    required this.id,
    required this.kickCount,
    required this.duration,
    required this.createdAt,
    required this.data,
  });
}

class KickTrackerScreen extends StatefulWidget {
  const KickTrackerScreen({super.key});

  @override
  State<KickTrackerScreen> createState() => _KickTrackerScreenState();
}

class _KickTrackerScreenState extends State<KickTrackerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  List<KickSession> _sessions = [];
  final List<FlSpot> _currentData = [];
  Timer? _timer;
  var _elapsedSeconds = 0;
  var _kickCount = 0;
  var _isTracking = false;
  var _sessionId = '';
  var _isButtonDisabled = false;

  late AnimationController _kickController;
  late AnimationController _fadeController;
  late Animation<double> _kickAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _kickController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    _kickAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _kickController, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _loadSessions();
    _fadeController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _kickController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final response = await _supabase
          .from('kick_sessions')
          .select()
          .order('created_at', ascending: false);

      final sessions = (response as List)
          .map((session) => KickSession(
                id: session['session_id'],
                kickCount: session['kick_count'],
                duration: session['elapsed_seconds'],
                createdAt: DateTime.parse(session['created_at']),
                data: _parseChartData(session['kick_data'] is String
                    ? List<Map<String, dynamic>>.from(
                        jsonDecode(session['kick_data']))
                    : session['kick_data']),
              ))
          .toList();

      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      _showError('Failed to load sessions: ${e.toString()}');
    }
  }

  List<FlSpot> _parseChartData(List<dynamic> data) {
    return data
        .map<FlSpot>(
            (point) => FlSpot(point['x'].toDouble(), point['y'].toDouble()))
        .toList();
  }

  Future<void> _saveSession() async {
    try {
      await _supabase.from('kick_sessions').upsert({
        'session_id': _sessionId,
        'kick_count': _kickCount,
        'elapsed_seconds': _elapsedSeconds,
        'kick_data':
            jsonEncode(_currentData.map((p) => {'x': p.x, 'y': p.y}).toList()),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadSessions();
    } catch (e) {
      _showError('Failed to save session: ${e.toString()}');
    }
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
      _resetCounters();
      _sessionId = DateTime.now().toIso8601String();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
        _currentData
            .add(FlSpot(_elapsedSeconds.toDouble(), _kickCount.toDouble()));
      });
    });
  }

  void _stopTracking() async {
    _timer?.cancel();
    setState(() => _isTracking = false);
    await _saveSession();
  }

  void _recordKick() {
    if (_isTracking && !_isButtonDisabled) {
      setState(() {
        _kickCount++;
        _isButtonDisabled = true;
      });

      _kickController.forward().then((_) => _kickController.reverse());

      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _isButtonDisabled = false);
        }
      });
    }
  }

  void _resetCounters() {
    _elapsedSeconds = 0;
    _kickCount = 0;
    _currentData.clear();
    _isButtonDisabled = false;
  }

  void _showError(String message) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Baby Kick Tracker',
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
              colors: [AppPallete.primaryColor, AppPallete.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: AppPallete.primaryColor.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              SizedBox(height: 20),
              _buildMainKickCard(),
              SizedBox(height: 24),
              _buildStatsRow(),
              SizedBox(height: 24),
              _buildChart(),
              SizedBox(height: 24),
              _buildSessionHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainKickCard() {
    return Container(
      padding: EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _isTracking ? AppPallete.primaryColor : Colors.white,
            _isTracking ? AppPallete.accentColor : Colors.grey[50]!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _isTracking
                ? AppPallete.primaryColor.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Current Session',
            style: TextStyle(
              fontSize: 16,
              color: _isTracking
                  ? Colors.white.withOpacity(0.9)
                  : AppPallete.textColor.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  Text(
                    '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _isTracking ? Colors.white : AppPallete.textColor,
                    ),
                  ),
                  Text(
                    'Time',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isTracking
                          ? Colors.white.withOpacity(0.8)
                          : AppPallete.textColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              Container(
                width: 2,
                height: 40,
                color: _isTracking
                    ? Colors.white.withOpacity(0.3)
                    : AppPallete.textColor.withOpacity(0.2),
              ),
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _kickAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _kickAnimation.value,
                        child: Text(
                          '$_kickCount',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _isTracking
                                ? Colors.white
                                : AppPallete.accentColor,
                          ),
                        ),
                      );
                    },
                  ),
                  Text(
                    'Kicks',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isTracking
                          ? Colors.white.withOpacity(0.8)
                          : AppPallete.textColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _isTracking ? LucideIcons.square : LucideIcons.play,
                      color: Colors.white,
                    ),
                    label: Text(
                      _isTracking ? 'STOP' : 'START',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isTracking ? Colors.red[600] : Colors.green[600],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isTracking ? _stopTracking : _startTracking,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Container(
                width: 70,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _isButtonDisabled || !_isTracking ? null : _recordKick,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isButtonDisabled
                        ? AppPallete.primaryColor.withOpacity(0.5)
                        : AppPallete.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: AnimatedBuilder(
                    animation: _kickAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _kickAnimation.value,
                        child: Icon(
                          LucideIcons.heart,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            _isTracking
                ? 'Tap the heart when you feel a kick!'
                : 'Start tracking to record baby movements',
            style: TextStyle(
              color: _isTracking
                  ? Colors.white.withOpacity(0.9)
                  : AppPallete.textColor.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
            child: _StatCard(LucideIcons.timer, 'Duration',
                '$_elapsedSeconds s', AppPallete.primaryColor)),
        SizedBox(width: 16),
        Expanded(
            child: _StatCard(LucideIcons.heart, 'Kicks', '$_kickCount',
                AppPallete.accentColor)),
        SizedBox(width: 16),
        Expanded(
            child: _StatCard(LucideIcons.activity, 'Sessions',
                '${_sessions.length}', AppPallete.highlightColor)),
      ],
    );
  }

  Widget _buildChart() {
    return Container(
      height: 250,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trendingUp,
                  color: AppPallete.accentColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Kick Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppPallete.textColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: _elapsedSeconds.toDouble(),
                minY: 0,
                maxY: (_kickCount.toDouble() + 5).clamp(0.0, double.infinity),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 60,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}s',
                        style: TextStyle(
                            color: AppPallete.textColor.withOpacity(0.7),
                            fontSize: 12),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                            color: AppPallete.textColor.withOpacity(0.7),
                            fontSize: 12),
                      ),
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey[200]!,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _currentData.isEmpty ? [FlSpot(0, 0)] : _currentData,
                    isCurved: true,
                    color: AppPallete.accentColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppPallete.accentColor!,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppPallete.primaryColor.withOpacity(0.3),
                          AppPallete.primaryColor.withOpacity(0.1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHistory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(LucideIcons.history,
                    color: AppPallete.accentColor, size: 20),
                SizedBox(width: 8),
                Text(
                  'Session History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppPallete.textColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 300,
            child: _sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.heart,
                            size: 48, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          'No kick sessions recorded yet',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: 20),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return Container(
                        margin: EdgeInsets.only(bottom: 8, left: 20, right: 20),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppPallete.backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppPallete.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                LucideIcons.heart,
                                color: AppPallete.accentColor,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Session ${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppPallete.textColor,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '${session.kickCount} kicks in ${session.duration}s',
                                    style: TextStyle(
                                      color:
                                          AppPallete.textColor.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${session.createdAt.day}/${session.createdAt.month}/${session.createdAt.year}',
                              style: TextStyle(
                                color: AppPallete.textColor.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _StatCard(this.icon, this.title, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppPallete.textColor.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              color: AppPallete.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
