import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'dart:math' as math;

class AIHealthScoreScreen extends StatefulWidget {
  const AIHealthScoreScreen({Key? key}) : super(key: key);

  @override
  State<AIHealthScoreScreen> createState() => _AIHealthScoreScreenState();
}

class _AIHealthScoreScreenState extends State<AIHealthScoreScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────────
  late AnimationController _fadeController;
  late AnimationController _scoreController;
  late AnimationController _cardController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scoreAnimation;
  late Animation<double> _pulseAnimation;
  late List<Animation<double>> _cardAnims;

  // ── Firebase ──────────────────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? user = FirebaseAuth.instance.currentUser;

  // ── State ──────────────────────────────────────────────────────────────────
  bool isLoading = true;

  // Scores (0–100)
  int overallScore = 0;
  int moodScore = 0;
  int sleepScore = 0;
  int waterScore = 0;
  int activityScore = 0;
  int burnoutRisk = 0;

  // Status labels
  String overallStatus = 'Loading...';
  String moodStatus = 'No data';
  String sleepStatus = 'No data';
  String waterStatus = 'No data';
  String activityStatus = 'No data';
  String burnoutStatus = 'Calculating...';

  // Raw averages (to show actual values)
  double avgMoodRating = 0;
  double avgSleepHours = 0;
  double avgWaterGlasses = 0;
  double avgActivityMins = 0;

  // Weekly history for bar chart (7 days, index 0 = today)
  List<double> weeklyOverall = List.filled(7, 0);

  // Days logged counts
  int daysLogged = 0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadHealthData();
  }

  // ── Animations ────────────────────────────────────────────────────────────
  void _initAnimations() {
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scoreController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _cardController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));
    _scoreAnimation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic));
    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // 6 staggered card anims
    _cardAnims = List.generate(6, (i) {
      final start = i * 0.12;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _cardController,
          curve: Interval(start, end, curve: Curves.easeOutCubic)));
    });

    _fadeController.forward();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadHealthData() async {
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final now = DateTime.now();
      final userRef = _firestore.collection('users').doc(user!.uid);
      final last7Days = List.generate(7, (i) {
        final d = now.subtract(Duration(days: i));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      List<int> moodScores = [];
      List<double> sleepScores = [];
      List<int> waterScores = [];
      List<int> activityScores = [];
      List<double> dailyOverall = [];

      // ⚡ Fetch ALL 28 docs in parallel (4 collections × 7 days)
      final allFutures = <String, Future<DocumentSnapshot>>{};
      for (final dateStr in last7Days) {
        allFutures['mood_$dateStr'] = userRef.collection('mood_logs').doc(dateStr).get();
        allFutures['sleep_$dateStr'] = userRef.collection('sleep_logs').doc(dateStr).get();
        allFutures['water_$dateStr'] = userRef.collection('water_logs').doc(dateStr).get();
        allFutures['activity_$dateStr'] = userRef.collection('activity_logs').doc(dateStr).get();
      }
      final keys = allFutures.keys.toList();
      final results = await Future.wait(allFutures.values);
      final docs = Map.fromIterables(keys, results);

      for (int i = 0; i < last7Days.length; i++) {
        final dateStr = last7Days[i];
        int? dayMood;
        double? daySleep;
        int? dayWater;
        int? dayActivity;

        // Mood
        final moodDoc = docs['mood_$dateStr']!;
        if (moodDoc.exists) {
          final rating = (moodDoc.data() as Map<String, dynamic>?)?['rating'];
          if (rating != null) {
            dayMood = (rating is int) ? rating : int.tryParse(rating.toString()) ?? 0;
            moodScores.add(dayMood);
          }
        }

        // Sleep
        final sleepDoc = docs['sleep_$dateStr']!;
        if (sleepDoc.exists) {
          final d = sleepDoc.data() as Map<String, dynamic>?;
          final hours = d?['hours'] ?? d?['sleepDuration'];
          if (hours != null) {
            daySleep = (hours is double) ? hours : double.tryParse(hours.toString()) ?? 0.0;
            sleepScores.add(daySleep);
          }
        }

        // Water
        final waterDoc = docs['water_$dateStr']!;
        if (waterDoc.exists) {
          final d = waterDoc.data() as Map<String, dynamic>?;
          final glasses = d?['glasses'] ?? d?['totalGlasses'];
          if (glasses != null) {
            dayWater = (glasses is int) ? glasses : int.tryParse(glasses.toString()) ?? 0;
            waterScores.add(dayWater);
          }
        }

        // Activity
        final activityDoc = docs['activity_$dateStr']!;
        if (activityDoc.exists) {
          final duration = (activityDoc.data() as Map<String, dynamic>?)?['duration'];
          if (duration != null) {
            dayActivity = (duration is int) ? duration : int.tryParse(duration.toString()) ?? 0;
            activityScores.add(dayActivity);
          }
        }

        final dayScore = _calcDayScore(dayMood, daySleep, dayWater, dayActivity);
        dailyOverall.add(dayScore);
      }

      // Reverse so index 0 = oldest (Mon→Sun for chart)
      weeklyOverall = dailyOverall.reversed.toList();

      // Store raw averages
      if (moodScores.isNotEmpty) {
        avgMoodRating =
            moodScores.reduce((a, b) => a + b) / moodScores.length;
      }
      if (sleepScores.isNotEmpty) {
        avgSleepHours =
            sleepScores.reduce((a, b) => a + b) / sleepScores.length;
      }
      if (waterScores.isNotEmpty) {
        avgWaterGlasses =
            waterScores.reduce((a, b) => a + b) / waterScores.length;
      }
      if (activityScores.isNotEmpty) {
        avgActivityMins =
            activityScores.reduce((a, b) => a + b) / activityScores.length;
      }

      daysLogged = [
        moodScores.isNotEmpty,
        sleepScores.isNotEmpty,
        waterScores.isNotEmpty,
        activityScores.isNotEmpty
      ].where((b) => b).length;

      _calculateScores(
          moodScores, sleepScores, waterScores, activityScores);

      setState(() => isLoading = false);
      _scoreController.forward();
      _cardController.forward();
    } catch (e) {
      debugPrint('Error loading health data: $e');
      setState(() {
        isLoading = false;
        overallStatus = 'Error loading data';
      });
    }
  }

  double _calcDayScore(
      int? mood, double? sleep, int? water, int? activity) {
    double total = 0;
    int count = 0;
    if (mood != null) {
      total += (mood / 5) * 100;
      count++;
    }
    if (sleep != null) {
      double s =
          (sleep >= 7 && sleep <= 9) ? 100 : (sleep >= 6 ? 75 : (sleep >= 5 ? 50 : 25));
      total += s;
      count++;
    }
    if (water != null) {
      total += ((water / 8) * 100).clamp(0, 100);
      count++;
    }
    if (activity != null) {
      total += ((activity / 30) * 100).clamp(0, 100);
      count++;
    }
    return count > 0 ? total / count : 0;
  }

  void _calculateScores(List<int> moodScores, List<double> sleepScores,
      List<int> waterScores, List<int> activityScores) {
    // Mood
    if (moodScores.isNotEmpty) {
      final avg = moodScores.reduce((a, b) => a + b) / moodScores.length;
      moodScore = ((avg / 5) * 100).round();
      moodStatus = moodScore >= 80
          ? 'Excellent mood'
          : moodScore >= 60
              ? 'Good overall'
              : moodScore >= 40
                  ? 'Could be better'
                  : 'Needs attention';
    }

    // Sleep
    if (sleepScores.isNotEmpty) {
      final avg = sleepScores.reduce((a, b) => a + b) / sleepScores.length;
      if (avg >= 7 && avg <= 9) {
        sleepScore = 100;
        sleepStatus = 'Perfect sleep';
      } else if (avg >= 6) {
        sleepScore = 75;
        sleepStatus = 'Almost there';
      } else if (avg >= 5) {
        sleepScore = 50;
        sleepStatus = 'Need more sleep';
      } else if (avg > 9) {
        sleepScore = 70;
        sleepStatus = 'Sleeping too much';
      } else {
        sleepScore = 25;
        sleepStatus = 'Critical — too little';
      }
    }

    // Water
    if (waterScores.isNotEmpty) {
      final avg = waterScores.reduce((a, b) => a + b) / waterScores.length;
      waterScore = ((avg / 8) * 100).round().clamp(0, 100);
      waterStatus = waterScore >= 100
          ? 'Perfectly hydrated'
          : waterScore >= 75
              ? 'Well hydrated'
              : waterScore >= 50
                  ? 'Drink more water'
                  : 'Dehydrated';
    }

    // Activity
    if (activityScores.isNotEmpty) {
      final avg =
          activityScores.reduce((a, b) => a + b) / activityScores.length;
      activityScore = ((avg / 30) * 100).round().clamp(0, 100);
      activityStatus = activityScore >= 100
          ? 'Very active'
          : activityScore >= 75
              ? 'Good activity'
              : activityScore >= 50
                  ? 'Move more'
                  : 'Too sedentary';
    }

    // Overall (weighted)
    final hasData = [
      moodScores.isNotEmpty,
      sleepScores.isNotEmpty,
      waterScores.isNotEmpty,
      activityScores.isNotEmpty
    ].where((b) => b).length;

    if (hasData > 0) {
      overallScore = (moodScore * 0.3 +
              sleepScore * 0.3 +
              waterScore * 0.2 +
              activityScore * 0.2)
          .round();
      overallStatus = overallScore >= 85
          ? 'Excellent Health!'
          : overallScore >= 70
              ? 'Good Health'
              : overallScore >= 50
                  ? 'Needs Improvement'
                  : 'Needs Attention';
    } else {
      overallScore = 0;
      overallStatus = 'Start logging data!';
    }

    burnoutRisk = (100 - overallScore).clamp(0, 100);
    burnoutStatus = burnoutRisk <= 20
        ? 'Low risk — keep it up!'
        : burnoutRisk <= 40
            ? 'Moderate — watch it'
            : burnoutRisk <= 60
                ? 'High — take care'
                : 'Very high — act now';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF4ECCA3);
    if (score >= 60) return const Color(0xFFFFC857);
    if (score >= 40) return const Color(0xFFFF9068);
    return const Color(0xFFFF6B6B);
  }

  String _scoreGrade(int score) {
    if (score >= 90) return 'A+';
    if (score >= 80) return 'A';
    if (score >= 70) return 'B';
    if (score >= 60) return 'C';
    if (score >= 50) return 'D';
    return 'F';
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scoreController.dispose();
    _cardController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          // Ambient gradient blobs
          _ambientBlobs(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: isLoading
                        ? _buildLoading()
                        : CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate([
                                    _buildOverallScoreCard(),
                                    const SizedBox(height: 16),
                                    _buildWeeklyTrendCard(),
                                    const SizedBox(height: 16),
                                    _buildMetricsGrid(),
                                    const SizedBox(height: 16),
                                    _buildBurnoutCard(),
                                    const SizedBox(height: 16),
                                    _buildAIInsightCard(),
                                    const SizedBox(height: 16),
                                    _buildDataSourceCard(),
                                  ]),
                                ),
                              ),
                            ],
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

  Widget _ambientBlobs() {
    return Stack(children: [
      Positioned(
        top: -80,
        right: -60,
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFF7B2CBF).withOpacity(0.10), Colors.transparent],
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 80,
        left: -70,
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFF2EC4B6).withOpacity(0.07), Colors.transparent],
            ),
          ),
        ),
      ),
      Positioned(
        top: 300,
        right: -40,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFF4ECCA3).withOpacity(0.05), Colors.transparent],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: const [Color(0xFF2EC4B6), Color(0xFF7B2CBF)],
                    transform:
                        GradientRotation(_pulseController.value * 2 * math.pi),
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF2EC4B6).withOpacity(0.3),
                        blurRadius: 25,
                        spreadRadius: 2),
                    BoxShadow(
                        color: const Color(0xFF7B2CBF).withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: -5),
                  ],
                ),
                child: const Icon(Icons.analytics_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)],
            ).createShader(r),
            child: const Text('Analysing your health data...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text('Fetching last 7 days',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)],
                  ).createShader(r),
                  child: const Text('AI Health Score',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2)),
                ),
                const SizedBox(height: 2),
                Text('Last 7 days • Real data',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.45),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // ML badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF2EC4B6).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text('ML',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Overall Score Card ────────────────────────────────────────────────────
  Widget _buildOverallScoreCard() {
    final color = _scoreColor(overallScore);
    return _animCard(
      0,
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                  color: color.withOpacity(0.25), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              children: [
                // Score ring
                AnimatedBuilder(
                  animation: _scoreAnimation,
                  builder: (_, __) {
                    final disp =
                        (overallScore * _scoreAnimation.value).round();
                    final color = _scoreColor(overallScore);
                    return Row(
                      children: [
                        // Ring with glow
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 155,
                              height: 155,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outer glow ring
                                  Container(
                                    width: 155,
                                    height: 155,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.15 * _scoreAnimation.value),
                                          blurRadius: 25,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Background ring
                                  SizedBox(
                                    width: 150,
                                    height: 150,
                                    child: CircularProgressIndicator(
                                      value: 1.0,
                                      strokeWidth: 14,
                                      backgroundColor: Colors.transparent,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white
                                                  .withOpacity(0.07)),
                                    ),
                                  ),
                                  // Score arc
                                  SizedBox(
                                    width: 150,
                                    height: 150,
                                    child: CircularProgressIndicator(
                                      value: _scoreAnimation.value *
                                          (overallScore / 100),
                                      strokeWidth: 14,
                                      backgroundColor: Colors.transparent,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              color),
                                      strokeCap: StrokeCap.round,
                                    ),
                                  ),
                                  // Centre content
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$disp',
                                        style: TextStyle(
                                            fontSize: 54,
                                            fontWeight: FontWeight.w900,
                                            color: color,
                                            height: 1),
                                      ),
                                      Text(
                                        _scoreGrade(overallScore),
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: color
                                                .withOpacity(0.8)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Side stats
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(overallStatus,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text('Overall Score',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 18),
                            _sideStat(Icons.mood_rounded, 'Mood',
                                '${moodScore}pts', _scoreColor(moodScore)),
                            const SizedBox(height: 8),
                            _sideStat(Icons.bedtime_rounded, 'Sleep',
                                '${sleepScore}pts', _scoreColor(sleepScore)),
                            const SizedBox(height: 8),
                            _sideStat(Icons.water_drop_rounded, 'Water',
                                '${waterScore}pts', _scoreColor(waterScore)),
                            const SizedBox(height: 8),
                            _sideStat(Icons.directions_run_rounded, 'Activity',
                                '${activityScore}pts',
                                _scoreColor(activityScore)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                // Bottom bar: days logged
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _bottomStat(Icons.calendar_today_rounded, '$daysLogged/4', 'Metrics'),
                      _vDivider(),
                      _bottomStat(Icons.analytics_rounded, '7', 'Days tracked'),
                      _vDivider(),
                      _bottomStat(
                          Icons.flag_rounded,
                          overallScore >= 70
                              ? 'On track'
                              : 'Improve',
                          'Status'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideStat(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color.withOpacity(0.7), size: 14),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _bottomStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF2EC4B6).withOpacity(0.7), size: 16),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _vDivider() {
    return Container(
        width: 1, height: 36, color: Colors.white.withOpacity(0.12));
  }

  // ── Weekly Trend Card ─────────────────────────────────────────────────────
  Widget _buildWeeklyTrendCard() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    // Map last 7 days to day labels (oldest first)
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return days[d.weekday - 1];
    });
    final maxVal = weeklyOverall.isEmpty
        ? 100.0
        : (weeklyOverall.reduce(math.max) == 0
            ? 100.0
            : weeklyOverall.reduce(math.max));

    return _animCard(
      1,
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                  color: Colors.white.withOpacity(0.18), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bar_chart_rounded,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Text('7-Day Health Trend',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECCA3).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF4ECCA3).withOpacity(0.3)),
                      ),
                      child: const Text('REAL DATA',
                          style: TextStyle(
                              color: Color(0xFF4ECCA3),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Bar chart
                AnimatedBuilder(
                  animation: _scoreAnimation,
                  builder: (_, __) => SizedBox(
                    height: 90,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (i) {
                        final val = weeklyOverall.length > i
                            ? weeklyOverall[i]
                            : 0.0;
                        final frac = maxVal > 0
                            ? (val / maxVal).clamp(0.0, 1.0) *
                                _scoreAnimation.value
                            : 0.0;
                        final color = _scoreColor(val.toInt());
                        final isToday = i == 6;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 600),
                              width: 28,
                              height: (frac * 72).clamp(4.0, 72.0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: isToday
                                      ? [
                                          const Color(0xFF00D9FF),
                                          const Color(0xFF7B2CBF)
                                        ]
                                      : [
                                          color.withOpacity(0.9),
                                          color.withOpacity(0.4)
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: isToday
                                    ? [
                                        BoxShadow(
                                            color: const Color(0xFF00D9FF)
                                                .withOpacity(0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2))
                                      ]
                                    : [],
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    final isToday = i == 6;
                    return Text(
                      dayLabels[i],
                      style: TextStyle(
                          color: isToday
                              ? const Color(0xFF00D9FF)
                              : Colors.white.withOpacity(0.45),
                          fontSize: 9,
                          fontWeight: isToday
                              ? FontWeight.w900
                              : FontWeight.w600),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Metrics Grid ──────────────────────────────────────────────────────────
  Widget _buildMetricsGrid() {
    final metrics = [
      _MetricData(
        icon: Icons.mood_rounded,
        label: 'Mood',
        score: moodScore,
        status: moodStatus,
        rawValue: avgMoodRating > 0
            ? '${avgMoodRating.toStringAsFixed(1)}/5'
            : 'No data',
        rawLabel: 'avg rating',
        color: const Color(0xFFFFC857),
      ),
      _MetricData(
        icon: Icons.bedtime_rounded,
        label: 'Sleep',
        score: sleepScore,
        status: sleepStatus,
        rawValue: avgSleepHours > 0
            ? '${avgSleepHours.toStringAsFixed(1)}h'
            : 'No data',
        rawLabel: 'avg / night',
        color: const Color(0xFF9D84B7),
      ),
      _MetricData(
        icon: Icons.water_drop_rounded,
        label: 'Hydration',
        score: waterScore,
        status: waterStatus,
        rawValue: avgWaterGlasses > 0
            ? '${avgWaterGlasses.toStringAsFixed(1)}/8'
            : 'No data',
        rawLabel: 'glasses / day',
        color: const Color(0xFF00D9FF),
      ),
      _MetricData(
        icon: Icons.directions_run_rounded,
        label: 'Activity',
        score: activityScore,
        status: activityStatus,
        rawValue: avgActivityMins > 0
            ? '${avgActivityMins.toStringAsFixed(0)} min'
            : 'No data',
        rawLabel: 'avg / day',
        color: const Color(0xFF4ECCA3),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text('Health Breakdown',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ),
        ...metrics.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _animCard(e.key + 2, _buildMetricCard(e.value)),
          );
        }),
      ],
    );
  }

  Widget _buildMetricCard(_MetricData m) {
    final color = m.color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.12),
                color.withOpacity(0.05),
              ],
            ),
            border: Border.all(
                color: color.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 6))
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Icon container
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [color, color.withOpacity(0.7)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Icon(m.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(m.status,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  // Score badge
                  AnimatedBuilder(
                    animation: _scoreAnimation,
                    builder: (_, __) {
                      final disp = (m.score * _scoreAnimation.value).round();
                      return Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [color, color.withOpacity(0.6)]),
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Center(
                          child: Text('$disp',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1)),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Gradient progress bar
              AnimatedBuilder(
                animation: _scoreAnimation,
                builder: (_, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 7,
                    child: Stack(children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: (m.score / 100) * _scoreAnimation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withOpacity(0.6)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Raw value row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.icon,
                            color: color.withOpacity(0.7),
                            size: 14),
                        const SizedBox(width: 5),
                        Text(m.rawValue,
                            style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 4),
                        Text(m.rawLabel,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(_scoreGrade(m.score),
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 5),
                  Text('grade',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Burnout Card ──────────────────────────────────────────────────────────
  Widget _buildBurnoutCard() {
    final riskColor = burnoutRisk >= 60
        ? const Color(0xFFFF6B6B)
        : burnoutRisk >= 40
            ? const Color(0xFFFF9068)
            : burnoutRisk >= 20
                ? const Color(0xFFFFC857)
                : const Color(0xFF4ECCA3);

    return _animCard(
      3,
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  riskColor.withOpacity(0.12),
                  riskColor.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                  color: riskColor.withOpacity(0.35), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [
                              riskColor,
                              riskColor.withOpacity(0.7)
                            ]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: riskColor.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Burnout Risk Index',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          Text(burnoutStatus,
                              style: TextStyle(
                                  color: riskColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _scoreAnimation,
                      builder: (_, __) {
                        final disp =
                            (burnoutRisk * _scoreAnimation.value).round();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [
                                  riskColor,
                                  riskColor.withOpacity(0.7)
                                ]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: riskColor.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4))
                            ],
                          ),
                          child: Text('$disp%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900)),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _scoreAnimation,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 8,
                      child: Stack(children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: (burnoutRisk / 100) * _scoreAnimation.value,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [riskColor, riskColor.withOpacity(0.5)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [BoxShadow(color: riskColor.withOpacity(0.4), blurRadius: 6)],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Risk level indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _riskDot('Low', const Color(0xFF4ECCA3), burnoutRisk <= 20),
                    _riskDot(
                        'Moderate', const Color(0xFFFFC857), burnoutRisk > 20 && burnoutRisk <= 40),
                    _riskDot(
                        'High', const Color(0xFFFF9068), burnoutRisk > 40 && burnoutRisk <= 60),
                    _riskDot(
                        'Critical', const Color(0xFFFF6B6B), burnoutRisk > 60),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _riskDot(String label, Color color, bool active) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : color.withOpacity(0.25),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: active ? color : Colors.white.withOpacity(0.3),
                fontSize: 9,
                fontWeight:
                    active ? FontWeight.w800 : FontWeight.w500)),
      ],
    );
  }

  // ── AI Insight Card ───────────────────────────────────────────────────────
  Widget _buildAIInsightCard() {
    return _animCard(
      4,
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2EC4B6).withOpacity(0.12),
                  const Color(0xFF9D84B7).withOpacity(0.08),
                ],
              ),
              border: Border.all(
                  color: const Color(0xFF2EC4B6).withOpacity(0.35),
                  width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF2EC4B6).withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: const Icon(Icons.psychology_rounded,
                          color: Colors.white, size: 17),
                    ),
                    const SizedBox(width: 10),
                    const Text('AI Insight',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECCA3).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: const Color(0xFF4ECCA3).withOpacity(0.3)),
                      ),
                      child: const Text('PERSONALISED',
                          style: TextStyle(
                              color: Color(0xFF4ECCA3),
                              fontSize: 7,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    _generateInsight(),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        height: 1.65,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _generateInsight() {
    final parts = <String>[];

    // Overall
    if (overallScore == 0) {
      return 'No health data logged yet. Start tracking your mood, sleep, water and activity to unlock your personalised AI health score!';
    }
    if (overallScore >= 85) {
      parts.add('Outstanding! Your overall health score of $overallScore/100 is excellent. Keep up this lifestyle!');
    } else if (overallScore >= 70) {
      parts.add('Your health score of $overallScore/100 is good. A few small improvements can push you to excellent!');
    } else {
      parts.add('Your health score is $overallScore/100. Focus on the weaker areas below to improve.');
    }

    // Weakest metric
    final scores = {
      'Sleep': sleepScore,
      'Mood': moodScore,
      'Hydration': waterScore,
      'Activity': activityScore,
    };
    final weakest = scores.entries
        .where((e) => e.value > 0)
        .fold<MapEntry<String, int>?>(null, (prev, e) {
      if (prev == null || e.value < prev.value) return e;
      return prev;
    });

    if (weakest != null && weakest.value < 70) {
      parts.add('Your weakest area is ${weakest.key} (${weakest.value}pts). Prioritise this for the biggest score boost.');
    }

    // Specific tips
    if (avgSleepHours > 0 && avgSleepHours < 7) {
      parts.add('You averaged ${avgSleepHours.toStringAsFixed(1)}h sleep — aim for 7–9h for optimal recovery.');
    }
    if (avgWaterGlasses > 0 && avgWaterGlasses < 6) {
      parts.add('Hydration is at ${avgWaterGlasses.toStringAsFixed(1)} glasses/day. Try to hit 8 glasses for full marks.');
    }
    if (burnoutRisk > 50) {
      parts.add('Burnout risk is elevated at $burnoutRisk%. Consider rest, meditation or a short break.');
    }

    return parts.join('\n\n');
  }

  // ── Data Source Card ──────────────────────────────────────────────────────
  Widget _buildDataSourceCard() {
    return _animCard(
      5,
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2EC4B6).withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.info_outline_rounded,
                  color: const Color(0xFF2EC4B6).withOpacity(0.6), size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scores are calculated from your real logged data. Log mood, sleep, water & activity daily for accurate results.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.40),
                    fontSize: 10,
                    height: 1.5,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Staggered card wrapper ────────────────────────────────────────────────
  Widget _animCard(int index, Widget child) {
    final animIndex = index.clamp(0, _cardAnims.length - 1);
    return AnimatedBuilder(
      animation: _cardAnims[animIndex],
      builder: (_, __) => Opacity(
        opacity: _cardAnims[animIndex].value,
        child: Transform.translate(
          offset: Offset(0, (1 - _cardAnims[animIndex].value) * 22),
          child: child,
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────
class _MetricData {
  final IconData icon;
  final String label;
  final int score;
  final String status;
  final String rawValue;
  final String rawLabel;
  final Color color;

  const _MetricData({
    required this.icon,
    required this.label,
    required this.score,
    required this.status,
    required this.rawValue,
    required this.rawLabel,
    required this.color,
  });
}

