import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../../services/app_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FLOATING ORBS PAINTER (matches dashboard)
// ═══════════════════════════════════════════════════════════════════════════
class _Orb {
  final Offset pos;
  final double radius, speed, angle;
  final Color color;
  const _Orb(this.pos, this.radius, this.speed, this.angle, this.color);
}

class _OrbPainter extends CustomPainter {
  final double tick;
  final List<_Orb> orbs;
  _OrbPainter(this.tick, this.orbs);

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in orbs) {
      final dx = math.sin(tick * o.speed + o.angle) * 28;
      final dy = math.cos(tick * o.speed * 0.7 + o.angle) * 18;
      final c = o.pos + Offset(dx, dy);
      canvas.drawCircle(
        c,
        o.radius,
        Paint()
          ..shader = RadialGradient(
            colors: [o.color.withOpacity(0.3), o.color.withOpacity(0.0)],
          ).createShader(Rect.fromCircle(center: c, radius: o.radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  ANIMATED HEALTH SCORE ARC PAINTER
// ═══════════════════════════════════════════════════════════════════════════
class _ScoreArcPainter extends CustomPainter {
  final double progress; // 0..1
  final double strokeW;
  _ScoreArcPainter({required this.progress, this.strokeW = 12}); // ignore: unused_field

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeW / 2;

    // background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    // gradient arc
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweepAngle,
        false,
        Paint()
          ..shader = const SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF), Color(0xFFFF6B6B)],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreArcPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════════
//                       INSIGHTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({Key? key}) : super(key: key);
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with TickerProviderStateMixin {
  // ── Animations ─────────────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late AnimationController _staggerCtrl;
  late AnimationController _orbCtrl;
  late AnimationController _scoreCtrl;
  late AnimationController _chartCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late List<Animation<double>> _stagger;
  late Animation<double> _scoreAnim;

  // ── Period ─────────────────────────────────────────────────────────
  int _selectedPeriod = 0;
  final List<String> _periodLabels = ['Week', 'Month', 'Quarter'];

  bool _isLoading = true;

  // ── Health data ────────────────────────────────────────────────────
  double healthScore = 0.0;
  double previousHealthScore = 0.0;
  int currentStreak = 0;
  int totalDaysTracked = 0;

  List<double> weeklyHealthScores = [];
  List<String> timeLabels = [];

  double todayMood = 0.0;
  double todaySleep = 0.0;
  double todayWater = 0.0;
  int todaySteps = 0;

  Map<String, double> averages = {
    'mood': 0.0,
    'sleep': 0.0,
    'water': 0.0,
    'activity': 0.0,
  };

  User? user;
  late List<_Orb> _orbs;

  // ═════════════════════════════════════════════════════════════════════
  //  INIT
  // ═════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _initOrbs();
    _initAnimations();
    _loadHealthData();
  }

  void _initOrbs() {
    final r = math.Random(77);
    _orbs = List.generate(5, (i) => _Orb(
      Offset(r.nextDouble() * 420, r.nextDouble() * 1000),
      55 + r.nextDouble() * 70,
      0.25 + r.nextDouble() * 0.4,
      r.nextDouble() * math.pi * 2,
      [const Color(0xFF2EC4B6), const Color(0xFF7B2CBF), const Color(0xFF00D9FF),
       const Color(0xFF4ECCA3), const Color(0xFF9D84B7)][i],
    ));
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _chartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _stagger = List.generate(8, (i) {
      final s = (i * 0.10).clamp(0.0, 0.72);
      final e = (s + 0.32).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _staggerCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });

    _scoreAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic));
  }

  // ═════════════════════════════════════════════════════════════════════
  //  DATA LOADING  (optimized — parallel fetches)
  // ═════════════════════════════════════════════════════════════════════
  Future<void> _loadHealthData() async {
    user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = false);
    _entryCtrl.forward();
    _staggerCtrl.forward();
    _chartCtrl.forward();
    _fetchAnalyticsData();
  }

  bool _isFetchingPeriod = false;

  Future<void> _onPeriodChanged(int newPeriod) async {
    if (newPeriod == _selectedPeriod) return;
    setState(() {
      _selectedPeriod = newPeriod;
      _isFetchingPeriod = true;
    });
    _chartCtrl.reset();
    _chartCtrl.forward();
    _scoreCtrl.reset();
    await _fetchAnalyticsData();
    if (mounted) setState(() => _isFetchingPeriod = false);
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final now = DateTime.now();

      // ── Determine all dates we need ──
      List<DateTime> dates = [];
      if (_selectedPeriod == 0) {
        // Week — 7 days
        for (int i = 6; i >= 0; i--) dates.add(now.subtract(Duration(days: i)));
      } else if (_selectedPeriod == 1) {
        // Month — 28 days (4 weeks)
        for (int i = 27; i >= 0; i--) dates.add(now.subtract(Duration(days: i)));
      } else {
        // Quarter — all days from 3 months ago to today
        final start = DateTime(now.year, now.month - 2, 1);
        for (DateTime d = start; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
          dates.add(d);
        }
      }

      // ── Fetch ALL days in parallel (single batch) ──
      final dateStrings = dates.map(_formatDateString).toList();
      final allDayData = await Future.wait(
        dateStrings.map((ds) => _fetchDayData(userRef, ds)),
      );

      // ── Build a date -> data map ──
      final Map<String, Map<String, double>> dayDataMap = {};
      for (int i = 0; i < dates.length; i++) {
        dayDataMap[dateStrings[i]] = allDayData[i];
      }

      // ── Process into scores/averages based on period ──
      List<double> moodData = [];
      List<double> sleepData = [];
      List<double> waterData = [];
      List<double> activityData = [];
      List<double> scores = [];
      List<String> labels = [];
      int daysWithData = 0;
      int streakCount = 0;

      if (_selectedPeriod == 0) {
        // Week — one entry per day
        for (int i = 0; i < dates.length; i++) {
          final data = allDayData[i];
          labels.add(_getDayLabel(dates[i]));
          double dayScore = 0;
          if (data['mood']! > 0) dayScore += ((data['mood']! / 5.0) * 25).clamp(0.0, 25.0);
          if (data['sleep']! > 0) dayScore += ((data['sleep']! / 8.0) * 25).clamp(0.0, 25.0);
          if (data['water']! > 0) dayScore += ((data['water']! / 8.0) * 25).clamp(0.0, 25.0);
          if (data['activity']! > 0) dayScore += ((data['activity']! / 30.0) * 25).clamp(0.0, 25.0);
          scores.add(dayScore.clamp(0.0, 100.0));
          moodData.add(data['mood']!);
          sleepData.add(data['sleep']!);
          waterData.add(data['water']!);
          activityData.add(data['activity']!);
          if (data.values.any((v) => v > 0)) daysWithData++;
          if (i == dates.length - 1) {
            todayMood = data['mood']!;
            todaySleep = data['sleep']!;
            todayWater = data['water']!;
            todaySteps = data['activity']!.toInt();
          }
        }
        for (int i = scores.length - 1; i >= 0; i--) {
          if (scores[i] >= 50) streakCount++;
          else break;
        }
      } else if (_selectedPeriod == 1) {
        // Month — aggregate into 4 weeks
        for (int weekOffset = 3; weekOffset >= 0; weekOffset--) {
          List<double> wM = [], wS = [], wW = [], wA = [];
          for (int day = 0; day < 7; day++) {
            final idx = (3 - weekOffset) * 7 + day;
            if (idx >= allDayData.length) break;
            final data = allDayData[idx];
            if (data.values.any((v) => v > 0)) {
              wM.add(data['mood']!); wS.add(data['sleep']!);
              wW.add(data['water']!); wA.add(data['activity']!);
            }
          }
          moodData.add(wM.isEmpty ? 0.0 : wM.reduce((a, b) => a + b) / wM.length);
          sleepData.add(wS.isEmpty ? 0.0 : wS.reduce((a, b) => a + b) / wS.length);
          waterData.add(wW.isEmpty ? 0.0 : wW.reduce((a, b) => a + b) / wW.length);
          activityData.add(wA.isEmpty ? 0.0 : wA.reduce((a, b) => a + b) / wA.length);
          double weekScore = 0;
          if (moodData.last > 0) weekScore += ((moodData.last / 5.0) * 25).clamp(0.0, 25.0);
          if (sleepData.last > 0) weekScore += ((sleepData.last / 8.0) * 25).clamp(0.0, 25.0);
          if (waterData.last > 0) weekScore += ((waterData.last / 8.0) * 25).clamp(0.0, 25.0);
          if (activityData.last > 0) weekScore += ((activityData.last / 30.0) * 25).clamp(0.0, 25.0);
          scores.add(weekScore.clamp(0.0, 100.0));
          labels.add('W${4 - weekOffset}');
          if (wM.isNotEmpty || wS.isNotEmpty || wW.isNotEmpty || wA.isNotEmpty) daysWithData++;
        }
      } else {
        // Quarter — aggregate into 3 months
        for (int monthOffset = 2; monthOffset >= 0; monthOffset--) {
          final monthStart = DateTime(now.year, now.month - monthOffset, 1);
          final monthEnd = monthOffset == 0 ? now : DateTime(now.year, now.month - monthOffset + 1, 0);
          List<double> mM = [], mS = [], mW = [], mA = [];
          for (final entry in dayDataMap.entries) {
            // Parse the date string to check if it falls in this month
            final parts = entry.key.split('-');
            final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            if (!d.isBefore(monthStart) && !d.isAfter(monthEnd)) {
              final data = entry.value;
              if (data.values.any((v) => v > 0)) {
                mM.add(data['mood']!); mS.add(data['sleep']!);
                mW.add(data['water']!); mA.add(data['activity']!);
              }
            }
          }
          moodData.add(mM.isEmpty ? 0.0 : mM.reduce((a, b) => a + b) / mM.length);
          sleepData.add(mS.isEmpty ? 0.0 : mS.reduce((a, b) => a + b) / mS.length);
          waterData.add(mW.isEmpty ? 0.0 : mW.reduce((a, b) => a + b) / mW.length);
          activityData.add(mA.isEmpty ? 0.0 : mA.reduce((a, b) => a + b) / mA.length);
          double monthScore = 0;
          if (moodData.last > 0) monthScore += ((moodData.last / 5.0) * 25).clamp(0.0, 25.0);
          if (sleepData.last > 0) monthScore += ((sleepData.last / 8.0) * 25).clamp(0.0, 25.0);
          if (waterData.last > 0) monthScore += ((waterData.last / 8.0) * 25).clamp(0.0, 25.0);
          if (activityData.last > 0) monthScore += ((activityData.last / 30.0) * 25).clamp(0.0, 25.0);
          scores.add(monthScore.clamp(0.0, 100.0));
          labels.add(_getMonthLabel(monthStart));
          if (mM.isNotEmpty || mS.isNotEmpty || mW.isNotEmpty || mA.isNotEmpty) daysWithData++;
        }
      }

      final mL = moodData.where((v) => v > 0).toList();
      final sL = sleepData.where((v) => v > 0).toList();
      final wL = waterData.where((v) => v > 0).toList();
      final aL = activityData.where((v) => v > 0).toList();

      averages = {
        'mood': mL.isEmpty ? 0.0 : mL.reduce((a, b) => a + b) / mL.length,
        'sleep': sL.isEmpty ? 0.0 : sL.reduce((a, b) => a + b) / sL.length,
        'water': wL.isEmpty ? 0.0 : wL.reduce((a, b) => a + b) / wL.length,
        'activity': aL.isEmpty ? 0.0 : aL.reduce((a, b) => a + b) / aL.length,
      };

      currentStreak = streakCount;
      totalDaysTracked = daysWithData;

      if (mounted) {
        setState(() {
          weeklyHealthScores = scores.map((s) => s.clamp(0.0, 100.0)).toList();
          timeLabels = labels;
          healthScore = scores.isNotEmpty ? scores.last.clamp(0.0, 100.0) : 0;
          previousHealthScore = scores.length > 1 ? scores[scores.length - 2].clamp(0.0, 100.0) : 0;
        });
        _scoreCtrl.forward();
      }
    } catch (e) {
      AppLogger.error('Error fetching analytics data: $e');
      if (mounted) setState(() => _isFetchingPeriod = false);
    }
  }

  Future<Map<String, double>> _fetchDayData(DocumentReference userRef, String dateString) async {
    try {
      final docs = await Future.wait([
        userRef.collection('mood_logs').doc(dateString).get(),
        userRef.collection('sleep_logs').doc(dateString).get(),
        userRef.collection('water_logs').doc(dateString).get(),
        userRef.collection('activity_logs').doc(dateString).get(),
      ]);
      return {
        'mood': docs[0].exists && docs[0].data() != null ? (docs[0].data()!['rating'] as num?)?.toDouble() ?? 0.0 : 0.0,
        'sleep': docs[1].exists && docs[1].data() != null ? (docs[1].data()!['hours'] as num?)?.toDouble() ?? 0.0 : 0.0,
        'water': docs[2].exists && docs[2].data() != null ? (docs[2].data()!['glasses'] as num?)?.toDouble() ?? 0.0 : 0.0,
        'activity': docs[3].exists && docs[3].data() != null ? (docs[3].data()!['duration'] as num?)?.toDouble() ?? 0.0 : 0.0,
      };
    } catch (e) {
      return {'mood': 0.0, 'sleep': 0.0, 'water': 0.0, 'activity': 0.0};
    }
  }

  String _formatDateString(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _getDayLabel(DateTime d) => const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday % 7];
  String _getMonthLabel(DateTime d) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month - 1];

  @override
  void dispose() {
    _entryCtrl.dispose();
    _staggerCtrl.dispose();
    _orbCtrl.dispose();
    _scoreCtrl.dispose();
    _chartCtrl.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: _isLoading ? _buildLoading() : _buildBody(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60, height: 60,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
            shape: BoxShape.circle,
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(Colors.white)),
          ),
        ),
        const SizedBox(height: 18),
        Text('Analyzing your health data...', style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildBody() {
    return Stack(children: [
      // Floating orbs
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _orbCtrl,
          builder: (_, __) => CustomPaint(painter: _OrbPainter(_orbCtrl.value * math.pi * 2, _orbs)),
        ),
      ),
      // Content
      FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 90),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildPeriodSelector(),
                  const SizedBox(height: 20),
                  _buildHealthScoreCard(),
                  const SizedBox(height: 16),
                  _buildQuickStats(),
                  const SizedBox(height: 20),
                  _buildChartSection(),
                  const SizedBox(height: 20),
                  _buildMetricsSection(),
                  const SizedBox(height: 20),
                  _buildTrendsCard(),
                  const SizedBox(height: 20),
                  _buildInsightsCard(),
                ]),
              ),
            ),
          ]),
        ),
      ),
      // Period-switch loading overlay
      if (_isFetchingPeriod)
        Positioned.fill(
          child: Container(
            color: const Color(0xFF0A0E21).withOpacity(0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F3A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.15), blurRadius: 20)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF2EC4B6)))),
                  const SizedBox(width: 14),
                  Text('Loading ${_periodLabels[_selectedPeriod]} data...',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════
  //  HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Health Analytics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3)),
              const SizedBox(height: 3),
              Row(children: [
                Container(width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4ECCA3),
                    boxShadow: [BoxShadow(color: const Color(0xFF4ECCA3).withOpacity(0.5), blurRadius: 6)])),
                const SizedBox(width: 6),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]).createShader(r),
                  child: const Text('Your wellness journey', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  PERIOD SELECTOR
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPeriodSelector() {
    return _staggerWrap(0, _glass(
      padding: const EdgeInsets.all(4),
      radius: 14,
      child: Row(
        children: _periodLabels.asMap().entries.map((e) {
          final sel = _selectedPeriod == e.key;
          return Expanded(
            child: GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); _onPeriodChanged(e.key); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: sel ? const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]) : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel ? [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3))] : [],
                ),
                child: Text(e.value, textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sel ? Colors.white : Colors.white.withOpacity(0.5),
                    fontSize: 13, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    ));
  }

  // ═════════════════════════════════════════════════════════════════════
  //  HEALTH SCORE CARD  — animated arc
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHealthScoreCard() {
    final clampedScore = healthScore.clamp(0.0, 100.0);
    final clampedPrev = previousHealthScore.clamp(0.0, 100.0);
    final change = clampedScore - clampedPrev;
    final up = change >= 0;
    final statusColor = clampedScore >= 70 ? const Color(0xFF4ECCA3) : clampedScore >= 40 ? const Color(0xFFFF9F1C) : const Color(0xFFFF6B6B);
    final statusText = clampedScore >= 70 ? 'Excellent' : clampedScore >= 40 ? 'Good' : 'Needs Work';
    final statusIcon = clampedScore >= 70 ? Icons.verified_rounded : clampedScore >= 40 ? Icons.thumb_up_alt_rounded : Icons.trending_up_rounded;

    return _staggerWrap(1, _glass(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          // Left — score text
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]).createShader(r),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 8),
              Text('Health Score', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _scoreAnim,
              builder: (_, __) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${(clampedScore * _scoreAnim.value).toInt()}',
                  style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                const SizedBox(width: 4),
                Padding(padding: const EdgeInsets.only(bottom: 7),
                  child: Text('/100', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, color: statusColor, size: 12),
                  const SizedBox(width: 4),
                  Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (up ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B)).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    color: up ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B), size: 11),
                  const SizedBox(width: 3),
                  Text('${up ? '+' : ''}${change.toInt()}', style: TextStyle(
                    color: up ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B), fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ])),
          const SizedBox(width: 12),
          // Right — animated arc
          SizedBox(
            width: 100, height: 100,
            child: AnimatedBuilder(
              animation: _scoreAnim,
              builder: (_, __) => Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size(100, 100),
                  painter: _ScoreArcPainter(progress: (clampedScore / 100) * _scoreAnim.value),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [statusColor.withOpacity(0.25), statusColor.withOpacity(0.08)])),
                  child: Icon(
                    clampedScore >= 70 ? Icons.favorite_rounded : clampedScore >= 40 ? Icons.favorite_border_rounded : Icons.heart_broken_rounded,
                    color: statusColor, size: 24),
                ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // Score breakdown bar
        _buildScoreBreakdown(),
      ]),
    ));
  }

  Widget _buildScoreBreakdown() {
    final moodScore = todayMood > 0 ? ((todayMood / 5.0) * 25).clamp(0.0, 25.0) : 0.0;
    final sleepScore = todaySleep > 0 ? ((todaySleep / 8.0) * 25).clamp(0.0, 25.0) : 0.0;
    final waterScore = todayWater > 0 ? ((todayWater / 8.0) * 25).clamp(0.0, 25.0) : 0.0;
    final actScore = todaySteps > 0 ? ((todaySteps / 30.0) * 25).clamp(0.0, 25.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.pie_chart_rounded, color: Colors.white.withOpacity(0.4), size: 13),
          const SizedBox(width: 6),
          Text('Score Breakdown', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _breakdownChip('Mood', moodScore, const Color(0xFFFFC857)),
          const SizedBox(width: 6),
          _breakdownChip('Sleep', sleepScore, const Color(0xFF9D84B7)),
          const SizedBox(width: 6),
          _breakdownChip('Water', waterScore, const Color(0xFF2EC4B6)),
          const SizedBox(width: 6),
          _breakdownChip('Activity', actScore, const Color(0xFF4ECCA3)),
        ]),
      ]),
    );
  }

  Widget _breakdownChip(String label, double score, Color color) {
    return Expanded(
      child: Column(children: [
        Text('${score.toInt()}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color, height: 1)),
        const SizedBox(height: 2),
        Text('/25', style: TextStyle(fontSize: 8, color: color.withOpacity(0.5), fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (score / 25).clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  QUICK STATS — 3 compact cards
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildQuickStats() {
    return _staggerWrap(2, Row(children: [
      Expanded(child: _statPill(
        _selectedPeriod == 0 ? 'Streak' : 'Days Tracked',
        _selectedPeriod == 0 ? '$currentStreak' : '$totalDaysTracked',
        _selectedPeriod == 0 ? 'days' : 'total',
        Icons.local_fire_department_rounded, const Color(0xFFFF6B6B))),
      const SizedBox(width: 10),
      Expanded(child: _statPill('Avg Mood', averages['mood']!.toStringAsFixed(1),
        'out of 5',
        Icons.mood_rounded, const Color(0xFFFFC857))),
      const SizedBox(width: 10),
      Expanded(child: _statPill('Avg Sleep', '${averages['sleep']!.toStringAsFixed(1)}h',
        'per night',
        Icons.bedtime_rounded, const Color(0xFF9D84B7))),
    ]));
  }

  Widget _statPill(String label, String value, String subtitle, IconData icon, Color color) {
    return _glass(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withOpacity(0.25), color.withOpacity(0.12)]),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8)],
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, height: 1)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  CHART SECTION
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildChartSection() {
    if (weeklyHealthScores.isEmpty || timeLabels.isEmpty) return const SizedBox.shrink();

    final avgScore = weeklyHealthScores.where((s) => s > 0).isEmpty
        ? 0.0
        : weeklyHealthScores.where((s) => s > 0).reduce((a, b) => a + b) / weeklyHealthScores.where((s) => s > 0).length;

    return _staggerWrap(3, _glass(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.25), blurRadius: 8)],
              ),
              child: const Icon(Icons.show_chart_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Health Trends', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Avg: ${avgScore.toInt()}/100', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600)),
            ]),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.2), blurRadius: 6)],
            ),
            child: Text(_periodLabels[_selectedPeriod],
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: AnimatedBuilder(
            animation: _chartCtrl,
            builder: (_, __) => LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true, drawVerticalLine: false, horizontalInterval: 25,
                  getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 25, reservedSize: 35,
                    getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w600)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1,
                    getTitlesWidget: (v, _) {
                      if (v.toInt() >= 0 && v.toInt() < timeLabels.length) {
                        return Padding(padding: const EdgeInsets.only(top: 8),
                          child: Text(timeLabels[v.toInt()],
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w700)));
                      }
                      return const Text('');
                    })),
                ),
                borderData: FlBorderData(show: false),
                minX: 0, maxX: (weeklyHealthScores.length - 1).toDouble(), minY: 0, maxY: 100,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A1F3A),
                    tooltipBorder: BorderSide(color: const Color(0xFF2EC4B6).withOpacity(0.3)),
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      '${s.y.toInt()}/100',
                      const TextStyle(color: Color(0xFF2EC4B6), fontWeight: FontWeight.w800, fontSize: 12),
                    )).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(weeklyHealthScores.length, (i) =>
                      FlSpot(i.toDouble(), (weeklyHealthScores[i] * _chartCtrl.value).clamp(0.0, 100.0))),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                    barWidth: 3, isStrokeCapRound: true,
                    dotData: FlDotData(show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: const Color(0xFF2EC4B6))),
                    belowBarData: BarAreaData(show: true,
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [const Color(0xFF2EC4B6).withOpacity(0.22), const Color(0xFF7B2CBF).withOpacity(0.03)])),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    ));
  }

  // ═════════════════════════════════════════════════════════════════════
  //  METRICS SECTION
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildMetricsSection() {
    return _staggerWrap(4, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Today\'s Metrics', Icons.dashboard_customize_rounded),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _metricCard('Mood', todayMood.toStringAsFixed(1),
          todayMood >= 4 ? 'Great' : todayMood >= 3 ? 'Good' : todayMood > 0 ? 'Low' : 'N/A',
          Icons.mood_rounded, const Color(0xFFFFC857), (todayMood / 5).clamp(0.0, 1.0))),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Sleep', '${todaySleep.toStringAsFixed(1)}h',
          todaySleep >= 7 ? 'Great' : todaySleep >= 5 ? 'Good' : todaySleep > 0 ? 'Low' : 'N/A',
          Icons.bedtime_rounded, const Color(0xFF9D84B7), (todaySleep / 8).clamp(0.0, 1.0))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _metricCard('Water', '${todayWater.toInt()} gl',
          todayWater >= 6 ? 'Great' : todayWater >= 4 ? 'Good' : todayWater > 0 ? 'Low' : 'N/A',
          Icons.water_drop_rounded, const Color(0xFF2EC4B6), (todayWater / 8).clamp(0.0, 1.0))),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Activity', '${todaySteps}m',
          todaySteps >= 30 ? 'Great' : todaySteps >= 15 ? 'Good' : todaySteps > 0 ? 'Low' : 'N/A',
          Icons.directions_run_rounded, const Color(0xFF4ECCA3), (todaySteps / 30).clamp(0.0, 1.0))),
      ]),
    ]));
  }

  Widget _metricCard(String title, String value, String status, IconData icon, Color color, double progress) {
    final statusColor = status == 'Great' ? const Color(0xFF4ECCA3) : status == 'Good' ? const Color(0xFFFF9F1C) : status == 'N/A' ? Colors.white.withOpacity(0.3) : const Color(0xFFFF6B6B);
    return _glass(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.25), color.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 6)],
            ),
            child: Icon(icon, color: color, size: 17)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withOpacity(0.3))),
            child: Text(status, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1)),
        const SizedBox(height: 3),
        Text(title, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(height: 10),
        Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  TRENDS CARD
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildTrendsCard() {
    String sleepTrend = 'No data yet';
    String waterTrend = 'No data yet';
    String actTrend = 'No data yet';
    Color sleepColor = Colors.white.withOpacity(0.3);
    Color waterColor = Colors.white.withOpacity(0.3);
    Color actColor = Colors.white.withOpacity(0.3);
    IconData sleepStatus = Icons.remove_rounded;
    IconData waterStatus = Icons.remove_rounded;
    IconData actStatus = Icons.remove_rounded;

    if (averages['sleep']! >= 7) { sleepTrend = 'Consistent & healthy 🌙'; sleepColor = const Color(0xFF4ECCA3); sleepStatus = Icons.check_circle_rounded; }
    else if (averages['sleep']! > 0) { sleepTrend = 'Below 7h target 😴'; sleepColor = const Color(0xFFFF9F1C); sleepStatus = Icons.warning_rounded; }
    if (averages['water']! >= 6) { waterTrend = 'Well hydrated 💧'; waterColor = const Color(0xFF4ECCA3); waterStatus = Icons.check_circle_rounded; }
    else if (averages['water']! > 0) { waterTrend = 'Below 6 glass target 💦'; waterColor = const Color(0xFFFF9F1C); waterStatus = Icons.warning_rounded; }
    if (averages['activity']! >= 20) { actTrend = 'Active lifestyle 💪'; actColor = const Color(0xFF4ECCA3); actStatus = Icons.check_circle_rounded; }
    else if (averages['activity']! > 0) { actTrend = 'Below 20min target 🏃'; actColor = const Color(0xFFFF9F1C); actStatus = Icons.warning_rounded; }

    return _staggerWrap(5, _glass(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Trends Analysis', Icons.insights_rounded),
        const SizedBox(height: 14),
        _trendRow('Sleep Pattern', sleepTrend, '${averages['sleep']!.toStringAsFixed(1)}h avg', Icons.bedtime_rounded, const Color(0xFF9D84B7), sleepColor, sleepStatus),
        _trendRow('Hydration', waterTrend, '${averages['water']!.toStringAsFixed(1)} gl avg', Icons.water_drop_rounded, const Color(0xFF2EC4B6), waterColor, waterStatus),
        _trendRow('Activity', actTrend, '${averages['activity']!.toStringAsFixed(0)}m avg', Icons.directions_run_rounded, const Color(0xFF4ECCA3), actColor, actStatus),
      ]),
    ));
  }

  Widget _trendRow(String title, String sub, String avg, IconData icon, Color color, Color statusColor, IconData statusIcon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withOpacity(0.25), color.withOpacity(0.1)]),
            borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
        ])),
        Column(children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(height: 2),
          Text(avg, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  INSIGHTS CARD
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildInsightsCard() {
    // Data-driven personalized recommendations
    List<String> tips = [];
    if (averages['sleep']! > 0 && averages['sleep']! < 7) tips.add('Try to get 7+ hours of sleep. You\'re averaging ${averages['sleep']!.toStringAsFixed(1)}h.');
    if (averages['water']! > 0 && averages['water']! < 6) tips.add('Increase water intake to 8 glasses. Current avg: ${averages['water']!.toStringAsFixed(1)} glasses.');
    if (averages['activity']! > 0 && averages['activity']! < 20) tips.add('Aim for 30 mins of daily activity. You\'re at ${averages['activity']!.toStringAsFixed(0)} min.');
    if (averages['mood']! > 0 && averages['mood']! < 3) tips.add('Your mood has been low. Consider mindfulness or talking to someone.');

    String mainInsight;
    IconData mainIcon;
    Color mainColor;
    if (healthScore >= 80) {
      mainInsight = 'Outstanding! Your health metrics are in excellent shape. Keep up the amazing consistency!';
      mainIcon = Icons.emoji_events_rounded;
      mainColor = const Color(0xFF4ECCA3);
    } else if (healthScore >= 60) {
      mainInsight = 'Great progress! You\'re on track. A few small improvements can push you to excellence.';
      mainIcon = Icons.trending_up_rounded;
      mainColor = const Color(0xFF2EC4B6);
    } else if (healthScore >= 30) {
      mainInsight = 'Building momentum! Focus on consistency in tracking your daily health habits.';
      mainIcon = Icons.speed_rounded;
      mainColor = const Color(0xFFFF9F1C);
    } else {
      mainInsight = 'Let\'s get started! Begin with tracking water and sleep to build healthy habits.';
      mainIcon = Icons.spa_rounded;
      mainColor = const Color(0xFFFF6B6B);
    }

    return _staggerWrap(6, Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFF2EC4B6).withOpacity(0.15), const Color(0xFF7B2CBF).withOpacity(0.1)]),
        border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3), width: 1),
        boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          const Text('AI Insights', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: mainColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: mainColor.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: mainColor,
                boxShadow: [BoxShadow(color: mainColor.withOpacity(0.5), blurRadius: 4)])),
              const SizedBox(width: 4),
              Text('Live', style: TextStyle(color: mainColor, fontSize: 8, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        // Main insight
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mainColor.withOpacity(0.15)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(mainIcon, color: mainColor, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(mainInsight,
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), height: 1.5, fontWeight: FontWeight.w500))),
          ]),
        ),
        // Specific tips
        if (tips.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...tips.asMap().entries.map((entry) {
            final tipColors = [const Color(0xFF9D84B7), const Color(0xFF2EC4B6), const Color(0xFF4ECCA3), const Color(0xFFFFC857)];
            final c = tipColors[entry.key % tipColors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 4),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: c,
                      boxShadow: [BoxShadow(color: c.withOpacity(0.4), blurRadius: 4)]))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(entry.value, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7), height: 1.4, fontWeight: FontWeight.w500))),
                ]),
              ),
            );
          }),
        ],
      ]),
    ));
  }

  // ═════════════════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═════════════════════════════════════════════════════════════════════
  Widget _glass({required Widget child, EdgeInsets? padding, double radius = 20}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.04)]),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 6))]),
          child: child,
        ),
      ),
    );
  }

  Widget _staggerWrap(int i, Widget child) {
    final idx = i.clamp(0, _stagger.length - 1);
    return AnimatedBuilder(
      animation: _stagger[idx],
      builder: (_, __) => Opacity(
        opacity: _stagger[idx].value,
        child: Transform.translate(offset: Offset(0, (1 - _stagger[idx].value) * 22), child: child)),
    );
  }

  Widget _sectionHeader(String text, IconData icon) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.2), blurRadius: 6)],
        ),
        child: Icon(icon, color: Colors.white, size: 14)),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
    ]);
  }
}

