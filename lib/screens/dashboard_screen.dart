import 'package:major_project/screens/reminders/reminders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/gemini_service.dart';
import '../services/app_logger.dart';
import 'health_logging/mood_tracker_screen.dart';
import 'health_logging/sleep_tracker_screen.dart';
import 'health_logging/water_tracker_screen.dart';
import 'health_logging/Activity_tracker_screen.dart';
import 'health_logging/profile_screen.dart';
import 'health_logging/ai_chat_screen.dart';
import 'health_logging/insights_screen.dart';
import 'health_score_screen.dart';
import 'symptom_checker_screen.dart';
import 'pdf_report_screen.dart';
import 'health_scanner/health_scanner_screen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ANIMATED BACKGROUND PAINTER — floating orbs / particles
// ═══════════════════════════════════════════════════════════════════════════
class _OrbParticle {
  Offset position;
  double radius;
  double speed;
  double angle;
  Color color;
  _OrbParticle({required this.position, required this.radius, required this.speed, required this.angle, required this.color});
}

class _FloatingOrbsPainter extends CustomPainter {
  final double tick;
  final List<_OrbParticle> orbs;
  _FloatingOrbsPainter({required this.tick, required this.orbs});

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in orbs) {
      final dx = math.sin(tick * o.speed + o.angle) * 30;
      final dy = math.cos(tick * o.speed * 0.7 + o.angle) * 20;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [o.color.withOpacity(0.35), o.color.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: o.position + Offset(dx, dy), radius: o.radius));
      canvas.drawCircle(o.position + Offset(dx, dy), o.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingOrbsPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  PULSE RING PAINTER — for animated pulse behind elements
// ═══════════════════════════════════════════════════════════════════════════
class _PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _PulseRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final p = ((progress + i * 0.33) % 1.0);
      final radius = size.width * 0.25 + p * size.width * 0.3;
      final opacity = (1.0 - p) * 0.35;
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  SMOOTH CYCLING‑PERSON PAINTER  (realistic silhouette on a bike)
// ═══════════════════════════════════════════════════════════════════════════
class _CyclistPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CyclistPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 70; // normalize to 70px reference

    // Wheel properties
    final wheelR = 9.0 * scale;
    final rearWheelCenter = Offset(cx - wheelR * 1.25, cy + wheelR * 0.7);
    final frontWheelCenter = Offset(cx + wheelR * 1.25, cy + wheelR * 0.7);

    // ── 3D Ground shadow (ellipse beneath) ──
    final groundY = cy + wheelR * 0.7 + wheelR + 2 * scale;
    final shadowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
      ).createShader(Rect.fromCenter(center: Offset(cx, groundY), width: size.width * 0.85, height: 7 * scale));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, groundY), width: size.width * 0.80, height: 5 * scale),
      shadowPaint,
    );

    // ── Subtle wheel glow for depth ──
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.12), Colors.transparent],
      ).createShader(Rect.fromCircle(center: rearWheelCenter, radius: wheelR * 1.6));
    canvas.drawCircle(rearWheelCenter, wheelR * 1.5, glowPaint);
    canvas.drawCircle(frontWheelCenter, wheelR * 1.5, glowPaint);

    // Paint for frame & structure
    final framePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Thinner paint for wheels
    final wheelPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * scale
      ..strokeCap = StrokeCap.round;

    // Subtle inner rim for 3D wheel depth
    final innerRimPaint = Paint()
      ..color = color.withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale;

    final spokePaint = Paint()
      ..color = color.withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * scale;

    // ── Wheels ──
    canvas.drawCircle(rearWheelCenter, wheelR, wheelPaint);
    canvas.drawCircle(frontWheelCenter, wheelR, wheelPaint);
    // Inner rims for 3D depth
    canvas.drawCircle(rearWheelCenter, wheelR * 0.75, innerRimPaint);
    canvas.drawCircle(frontWheelCenter, wheelR * 0.75, innerRimPaint);

    // ── Wheel hubs ──
    final hubPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(rearWheelCenter, 1.8 * scale, hubPaint);
    canvas.drawCircle(frontWheelCenter, 1.8 * scale, hubPaint);

    // ── Rotating spokes (6 per wheel) ──
    final spokeAngle = progress * math.pi * 2;
    for (int i = 0; i < 6; i++) {
      final angle = spokeAngle + i * math.pi / 3;
      final dx = math.cos(angle) * wheelR * 0.85;
      final dy = math.sin(angle) * wheelR * 0.85;
      canvas.drawLine(rearWheelCenter, rearWheelCenter + Offset(dx, dy), spokePaint);
      canvas.drawLine(frontWheelCenter, frontWheelCenter + Offset(dx, dy), spokePaint);
    }

    // ── Frame geometry ──
    final bottomBracket = Offset(cx - wheelR * 0.05, cy + wheelR * 0.45); // crank center
    final seatTube = Offset(cx - wheelR * 0.45, cy - wheelR * 0.55); // seat top
    final headTube = Offset(cx + wheelR * 0.65, cy - wheelR * 0.45); // handlebar stem
    final seatStay = seatTube + Offset(-wheelR * 0.05, wheelR * 0.08); // seat attachment

    // Chainstay (bottom bracket to rear wheel)
    canvas.drawLine(bottomBracket, rearWheelCenter, framePaint);
    // Seat tube (bottom bracket to seat)
    canvas.drawLine(bottomBracket, seatStay, framePaint);
    // Top tube (seat to head tube)
    canvas.drawLine(seatStay, headTube, framePaint);
    // Down tube (bottom bracket to head tube)
    canvas.drawLine(bottomBracket, headTube, framePaint);
    // Seat stay (seat to rear wheel)
    canvas.drawLine(seatStay, rearWheelCenter, framePaint);
    // Fork (head tube to front wheel)
    canvas.drawLine(headTube, frontWheelCenter, framePaint);

    // ── Handlebar ──
    final handlebarEnd = headTube + Offset(wheelR * 0.2, -wheelR * 0.2);
    canvas.drawLine(headTube, handlebarEnd, framePaint);

    // ── Seat ──
    final seatLeft = seatTube + Offset(-wheelR * 0.2, 0);
    final seatRight = seatTube + Offset(wheelR * 0.15, 0);
    canvas.drawLine(seatLeft, seatRight, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round);

    // ── Rider body (smooth) ──
    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round;

    // Torso — from seat to shoulder (leaning forward)
    final hip = seatTube + Offset(0, wheelR * 0.05);
    final shoulder = Offset(
      hip.dx + wheelR * 0.65,
      hip.dy - wheelR * 0.75,
    );
    // Slight torso bob with pedaling
    final bobY = math.sin(progress * math.pi * 2) * 0.8 * scale;
    final shoulderBob = shoulder + Offset(0, bobY);

    canvas.drawLine(hip, shoulderBob, bodyPaint);

    // ── Head ──
    final headRadius = wheelR * 0.25;
    final headCenter = shoulderBob + Offset(wheelR * 0.12, -headRadius * 1.3);
    canvas.drawCircle(headCenter, headRadius, bodyPaint);

    // ── Arms — shoulder to handlebar ──
    final elbow = Offset(
      (shoulderBob.dx + handlebarEnd.dx) / 2 + wheelR * 0.05,
      (shoulderBob.dy + handlebarEnd.dy) / 2 - wheelR * 0.1,
    );
    canvas.drawLine(shoulderBob, elbow, bodyPaint);
    canvas.drawLine(elbow, handlebarEnd, bodyPaint);

    // ── Legs — with smooth pedaling motion ──
    final pedalR = wheelR * 0.38;
    final pedalAngle = progress * math.pi * 2;
    final foot1 = bottomBracket + Offset(
      math.cos(pedalAngle) * pedalR,
      math.sin(pedalAngle) * pedalR,
    );
    final foot2 = bottomBracket + Offset(
      math.cos(pedalAngle + math.pi) * pedalR,
      math.sin(pedalAngle + math.pi) * pedalR,
    );

    // Knee positions — using inverse kinematics style
    final thighLen = wheelR * 0.8;
    final shinLen = wheelR * 0.75;

    _drawLeg(canvas, hip, foot1, thighLen, shinLen, bodyPaint, true);
    _drawLeg(canvas, hip, foot2, thighLen, shinLen, bodyPaint, false);

    // ── Crank arms ──
    final crankPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(bottomBracket, foot1, crankPaint);
    canvas.drawLine(bottomBracket, foot2, crankPaint);
  }

  void _drawLeg(Canvas canvas, Offset hip, Offset foot, double thighLen, double shinLen, Paint paint, bool front) {
    // Calculate knee position using triangle geometry
    final dx = foot.dx - hip.dx;
    final dy = foot.dy - hip.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist > thighLen + shinLen) {
      // Leg fully extended
      final mid = Offset((hip.dx + foot.dx) / 2, (hip.dy + foot.dy) / 2);
      canvas.drawLine(hip, mid, paint);
      canvas.drawLine(mid, foot, paint);
      return;
    }

    // Law of cosines for knee angle
    final cosAngle = ((thighLen * thighLen + dist * dist - shinLen * shinLen) / (2 * thighLen * dist)).clamp(-1.0, 1.0);
    final angle = math.acos(cosAngle);
    final baseAngle = math.atan2(dy, dx);

    // Knee bends outward (front leg one way, back leg same direction for cycling)
    final kneeAngle = baseAngle - angle;
    final knee = Offset(
      hip.dx + math.cos(kneeAngle) * thighLen,
      hip.dy + math.sin(kneeAngle) * thighLen,
    );

    canvas.drawLine(hip, knee, paint);
    canvas.drawLine(knee, foot, paint);
  }

  @override
  bool shouldRepaint(covariant _CyclistPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════════
//                         DASHBOARD SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {

  late AnimationController _entryCtrl;
  late AnimationController _cardCtrl;
  late AnimationController _orbCtrl;
  late AnimationController _cyclistCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _pulseCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late List<Animation<double>> _stagger;

  final AuthService _authService = AuthService();
  User? user;
  Map<String, dynamic>? userProfile;
  int _currentIndex = 0;
  Stream<DocumentSnapshot>? _userProfileStream;

  Map<String, dynamic> todaysHealth = {
    'mood': null, 'sleep': null, 'water': 0, 'activity': null,
    'streak': 0, 'completedToday': <String>[],
  };
  List<Map<String, dynamic>> recentActivities = [];
  late List<_OrbParticle> _orbs;

  // ── Dynamic AI-powered daily health tip ──
  final GeminiService _geminiService = GeminiService();
  String _dailyTip = '';
  bool _isTipLoading = true;
  IconData _tipIcon = Icons.lightbulb_rounded;
  Color _tipColor = const Color(0xFF2EC4B6);

  // Tip icon/color rotation for variety
  static const List<Map<String, dynamic>> _tipStyles = [
    {'icon': Icons.psychology_rounded, 'color': Color(0xFF9D84B7)},
    {'icon': Icons.water_drop_rounded, 'color': Color(0xFF00D9FF)},
    {'icon': Icons.directions_run_rounded, 'color': Color(0xFF4ECCA3)},
    {'icon': Icons.bedtime_rounded, 'color': Color(0xFF9D84B7)},
    {'icon': Icons.restaurant_rounded, 'color': Color(0xFF6BCF7F)},
    {'icon': Icons.wb_sunny_rounded, 'color': Color(0xFFFFC857)},
    {'icon': Icons.self_improvement_rounded, 'color': Color(0xFF7B2CBF)},
    {'icon': Icons.favorite_rounded, 'color': Color(0xFFE05555)},
    {'icon': Icons.fitness_center_rounded, 'color': Color(0xFF4ECCA3)},
    {'icon': Icons.spa_rounded, 'color': Color(0xFF2EC4B6)},
  ];

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _initOrbs();
    _initAnimations();
    _initializeFastApp();
    _scheduleReminders();
    _loadDailyTip();

    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-2668741490707269/7695269833', // Real Ad Unit ID
      request: AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  void _initOrbs() {
    final rng = math.Random(42);
    _orbs = List.generate(6, (i) => _OrbParticle(
      position: Offset(rng.nextDouble() * 400, rng.nextDouble() * 900),
      radius: 60 + rng.nextDouble() * 80,
      speed: 0.3 + rng.nextDouble() * 0.5,
      angle: rng.nextDouble() * math.pi * 2,
      color: [const Color(0xFF1A9E92), const Color(0xFF6A21A8), const Color(0xFF00B4D8),
              const Color(0xFF3DA58A), const Color(0xFFE05555), const Color(0xFF8A6DBF)][i],
    ));
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _cyclistCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))..repeat();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();

    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _stagger = List.generate(8, (i) {
      final s = (i * 0.09).clamp(0.0, 0.7);
      final e = (s + 0.35).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _cardCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });
  }

  Future<void> _initializeFastApp() async {
    user = _authService.currentUser;
    if (mounted) { _entryCtrl.forward(); _cardCtrl.forward(); }
    if (user != null) {
      _userProfileStream = FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots();
    }
    _loadDataInBackground();
  }

  Future<void> _loadDataInBackground() async {
    if (user == null) return;
    try {
      // Fire ALL requests in true parallel — no waiting
      final results = await Future.wait([
        _authService.getUserProfile(),
        _loadHealthDataSilently(),
        _calculateStreak(),
        _loadRecentActivities(),
      ], eagerError: false);

      userProfile = results[0] as Map<String, dynamic>?;
      if (mounted) setState(() {});
    } catch (e) { AppLogger.error('Error loading background data: $e'); }
  }

  Future<void> _loadHealthDataSilently() async {
    if (user == null) return;
    try {
      final today = DateTime.now();
      final ds = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final futures = await Future.wait([
        userRef.collection('mood_logs').doc(ds).get(),
        userRef.collection('sleep_logs').doc(ds).get(),
        userRef.collection('water_logs').doc(ds).get(),
        userRef.collection('activity_logs').doc(ds).get(),
      ]);
      List<String> completedToday = [];
      if (futures[0].exists) { todaysHealth['mood'] = futures[0].data()?['mood']; completedToday.add('mood'); }
      if (futures[1].exists) { todaysHealth['sleep'] = futures[1].data()?['hours']; completedToday.add('sleep'); }
      if (futures[2].exists) {
        final w = futures[2].data(); final g = w?['glasses'];
        todaysHealth['water'] = g is num ? g.toInt() : int.tryParse(g?.toString() ?? '') ?? 0;
        if (todaysHealth['water'] > 0) completedToday.add('water');
      }
      if (futures[3].exists) {
        final d = futures[3].data()!;
        todaysHealth['activity'] = {'type': d['activity'] ?? 'Unknown', 'duration': d['duration'] ?? 0, 'steps': d['steps'] ?? 0};
        completedToday.add('activity');
      }
      todaysHealth['completedToday'] = completedToday;
    } catch (e) { AppLogger.error('Error loading health data: $e'); }
  }

  Future<void> _calculateStreak() async {
    if (user == null) return;
    try {
      int streak = 0;
      final now = DateTime.now();
      final userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      // Check 5 days for speed — fast streak display
      for (int i = 0; i < 5; i++) {
        final d = now.subtract(Duration(days: i));
        final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final f = await Future.wait([
          userRef.collection('mood_logs').doc(ds).get(const GetOptions(source: Source.cache)).catchError((_) => userRef.collection('mood_logs').doc(ds).get()),
          userRef.collection('sleep_logs').doc(ds).get(const GetOptions(source: Source.cache)).catchError((_) => userRef.collection('sleep_logs').doc(ds).get()),
          userRef.collection('water_logs').doc(ds).get(const GetOptions(source: Source.cache)).catchError((_) => userRef.collection('water_logs').doc(ds).get()),
          userRef.collection('activity_logs').doc(ds).get(const GetOptions(source: Source.cache)).catchError((_) => userRef.collection('activity_logs').doc(ds).get()),
        ]);
        if (f.where((doc) => doc.exists).length >= 2) { streak++; } else { break; }
      }
      todaysHealth['streak'] = streak;
    } catch (_) { todaysHealth['streak'] = 0; }
  }

  Future<void> _loadRecentActivities() async {
    if (user == null) return;
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final now = DateTime.now();
      List<Map<String, dynamic>> acts = [];
      // Fetch 2 days in parallel for speed
      final allFutures = <Future<List<MapEntry<String, DocumentSnapshot>>>>[];
      for (int i = 0; i < 2; i++) {
        final date = now.subtract(Duration(days: i));
        final ds = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final cols = ['mood_logs', 'sleep_logs', 'water_logs', 'activity_logs'];
        final names = ['mood', 'sleep', 'water', 'activity'];
        allFutures.add(Future.wait(
          List.generate(4, (j) => userRef.collection(cols[j]).doc(ds).get()
            .then((doc) => MapEntry<String, DocumentSnapshot?>(names[j], doc))
            .catchError((_) => MapEntry<String, DocumentSnapshot?>(names[j], null)))
        ).then((results) {
          final entries = <MapEntry<String, DocumentSnapshot>>[];
          for (final r in results) { if (r.value != null && r.value!.exists) entries.add(MapEntry(r.key, r.value!)); }
          return entries;
        }));
      }
      final allResults = await Future.wait(allFutures);
      for (int i = 0; i < allResults.length; i++) {
        final date = now.subtract(Duration(days: i));
        for (final entry in allResults[i]) {
          acts.add({'type': entry.key, 'data': entry.value.data() as Map<String, dynamic>, 'timestamp': (entry.value.data() as Map<String, dynamic>)['timestamp'] ?? Timestamp.fromDate(date)});
        }
      }
      acts.sort((a, b) => (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));
      recentActivities = acts.take(5).toList();
    } catch (_) {}
  }

  Future<void> _scheduleReminders() async {
    try { await NotificationService().autoScheduleReminders(); } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  AI-POWERED DAILY HEALTH TIP — fresh every day, cached locally
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _loadDailyTip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final cachedDate = prefs.getString('tip_date') ?? '';
      final cachedTip = prefs.getString('tip_text') ?? '';

      // Pick a random style for today
      final styleIndex = today.day % _tipStyles.length;
      _tipIcon = _tipStyles[styleIndex]['icon'] as IconData;
      _tipColor = _tipStyles[styleIndex]['color'] as Color;

      if (cachedDate == todayStr && cachedTip.isNotEmpty) {
        // Already have today's tip — use cached
        if (mounted) setState(() { _dailyTip = cachedTip; _isTipLoading = false; });
      } else {
        // Fetch fresh tip from Gemini
        if (mounted) setState(() => _isTipLoading = true);
        await _fetchFreshTip(prefs, todayStr);
      }
    } catch (e) {
      AppLogger.error('Error loading daily tip: $e');
      if (mounted) setState(() {
        _dailyTip = 'Stay hydrated, move your body, and prioritize sleep for a healthier you! 💪';
        _isTipLoading = false;
      });
    }
  }

  Future<void> _fetchFreshTip(SharedPreferences prefs, String todayStr) async {
    try {
      final response = await _geminiService.generateHealthResponse(
        userMessage: 'Give me ONE unique, motivating, and scientifically backed daily health tip. '
            'Make it fresh, inspiring, and different every time. Include a specific fact or number. '
            'Keep it under 20 words. No greeting, no prefix, just the tip. Use one emoji at the end.',
        healthData: todaysHealth,
      );

      final tip = response.trim();
      if (tip.isNotEmpty && tip.length < 200) {
        await prefs.setString('tip_date', todayStr);
        await prefs.setString('tip_text', tip);
        if (mounted) setState(() { _dailyTip = tip; _isTipLoading = false; });
      } else {
        throw Exception('Invalid tip response');
      }
    } catch (e) {
      AppLogger.error('Error fetching fresh tip: $e');
      // Use a fallback tip if API fails
      final fallbacks = [
        'Walking 10,000 steps daily reduces cardiovascular risk by 35% 🚶',
        'Laughing for 15 minutes burns up to 40 calories daily 😄',
        'Cold showers boost immunity and increase alertness by 300% 🧊',
        'Reading before bed reduces stress levels by 68% 📚',
        'Eating slowly helps you consume 20% fewer calories per meal 🍽️',
        'Gratitude journaling improves sleep quality by 25% 📝',
        'Standing for 3 hours daily burns 750+ extra calories per week 🧍',
        'Dark chocolate (70%+) lowers blood pressure within 2 weeks 🍫',
        'Humming activates your vagus nerve and reduces anxiety instantly 🎵',
        'Morning sunlight exposure resets circadian rhythm in 15 minutes ☀️',
        'Deep belly laughs oxygenate organs and relieve muscle tension 😂',
        'Chewing food 32 times improves digestion and nutrient absorption 🦷',
        'A 20-minute nap boosts alertness and performance by 34% 💤',
        'Green tea daily reduces risk of stroke by 20% 🍵',
        'Smiling releases endorphins even when you force it — try now! 😊',
      ];
      final tip = fallbacks[DateTime.now().day % fallbacks.length];
      if (mounted) setState(() { _dailyTip = tip; _isTipLoading = false; });
    }
  }

  String _getDisplayName() {
    if (userProfile != null && userProfile!['name'] != null && userProfile!['name'].toString().isNotEmpty) return userProfile!['name'].toString();
    if (user?.displayName != null && user!.displayName!.isNotEmpty) return user!.displayName!;
    return 'User';
  }

  String _getGreeting() { final h = DateTime.now().hour; if (h < 12) return 'Good Morning'; if (h < 17) return 'Good Afternoon'; return 'Good Evening'; }
  String _getMoodEmoji(int? m) { if (m == null) return '😐'; switch (m) { case 1: return '😟'; case 2: return '😐'; case 3: return '🙂'; case 4: return '😊'; case 5: return '😄'; default: return '😐'; } }
  IconData _getActivityIcon(String t) { switch (t) { case 'mood': return Icons.mood_rounded; case 'sleep': return Icons.bedtime_rounded; case 'water': return Icons.water_drop_rounded; case 'activity': return Icons.directions_run_rounded; default: return Icons.note_rounded; } }

  String _getActivityTitle(String type, Map<String, dynamic> data) {
    try {
      switch (type) {
        case 'mood': return 'Updated mood to ${_getMoodEmoji(data['mood'])}';
        case 'sleep': return 'Logged ${data['hours'] ?? 0}h of sleep';
        case 'water': return 'Drank ${data['glasses'] ?? 0} glasses of water';
        case 'activity': final dur = data['duration'] ?? 0; return 'Completed ${(data['activity'] ?? 'activity').toString().toLowerCase()} (${dur is num ? dur.toInt() : dur}min)';
        default: return 'Logged health data';
      }
    } catch (_) { return 'Logged health data'; }
  }

  String _formatTimeAgo(Timestamp ts) {
    try { final diff = DateTime.now().difference(ts.toDate()); if (diff.inMinutes < 60) return '${diff.inMinutes}min ago'; if (diff.inHours < 24) return '${diff.inHours}h ago'; return '${diff.inDays}d ago'; } catch (_) { return 'Recently'; }
  }

  double _getCompletionPercentage() { final c = todaysHealth['completedToday'] as List<String>? ?? <String>[]; return c.length / 4.0; }


  String _generateAISuggestion() {
    final completed = todaysHealth['completedToday'] as List<String>? ?? <String>[];
    final w = (todaysHealth['water'] as num?)?.toInt() ?? 0;
    if (completed.length == 4) return "Outstanding! You've hit all goals today. Consistency builds powerful wellness habits.";
    if (w < 4) return "Hydration checkpoint: ${8 - w} more glasses needed to boost energy by 30%.";
    if (!completed.contains('sleep')) return "Track your sleep to discover patterns that optimize recovery and performance.";
    if (!completed.contains('mood')) return "Quick mood check-in builds emotional awareness and identifies wellness patterns.";
    if (!completed.contains('activity')) return "Just 15 minutes of movement releases endorphins and improves focus!";
    return "Excellent progress! Small consistent actions create transformational results.";
  }

  IconData _greetingIcon() { final h = DateTime.now().hour; if (h < 12) return Icons.wb_sunny_rounded; if (h < 17) return Icons.wb_cloudy_rounded; return Icons.nightlight_round; }
  String _formattedDate() {
    final now = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  void _navigateTo(Widget screen) {
    HapticFeedback.mediumImpact();
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (context, animation, _) => screen,
      transitionDuration: const Duration(milliseconds: 550),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        // Page-turn: 3D perspective rotation from right side
        return AnimatedBuilder(
          animation: curved,
          builder: (_, __) {
            final angle = (1.0 - curved.value) * math.pi / 6; // 30 degrees max
            final opacity = curved.value.clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.centerRight,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // perspective
                  ..rotateY(angle),
                child: child,
              ),
            );
          },
        );
      },
    ));
  }

  @override
  void dispose() {
    _entryCtrl.dispose(); _cardCtrl.dispose(); _orbCtrl.dispose();
    _cyclistCtrl.dispose(); _shimmerCtrl.dispose(); _pulseCtrl.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_currentIndex),
                child: _buildTab(_currentIndex),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _isBannerAdReady && _bannerAd != null
                ? SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0: return _buildHomeTab();
      case 1: return const AIChatScreen(embedded: true);
      case 2: return const InsightsScreen();
      case 3: return const ProfileScreen();
      default: return _buildHomeTab();
    }
  }


  // ═══════════════════════════════════════════════════════════════════════
  //  HOME TAB
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: () async { await _loadDataInBackground(); if (mounted) setState(() {}); },
      color: const Color(0xFF00D9FF),
      backgroundColor: const Color(0xFF1A1F3A),
      child: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _orbCtrl,
            builder: (_, __) => CustomPaint(
              painter: _FloatingOrbsPainter(tick: _orbCtrl.value * math.pi * 2, orbs: _orbs),
            ),
          ),
        ),
        FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: _buildHeroHeader()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                  sliver: SliverList(delegate: SliverChildListDelegate([
                    _buildDailyTipBanner(),           const SizedBox(height: 14),
                    _buildStreakProgressRow(),         const SizedBox(height: 14),
                    _buildTodaySummaryCard(),          const SizedBox(height: 18),
                    _buildQuickActionsGrid(),          const SizedBox(height: 20),
                    _buildSectionHeader(Icons.health_and_safety_rounded, 'Advanced Health', iconColor: const Color(0xFFFF6B6B)),
                    const SizedBox(height: 10),
                    _buildHealthScoreCard(),           const SizedBox(height: 12),
                    _buildAIHealthScannerCard(),       const SizedBox(height: 20),
                    _buildSectionHeader(Icons.build_rounded, 'Tools & Reports', iconColor: const Color(0xFF9D84B7)),
                    const SizedBox(height: 10),
                    _buildFeatureButtonsRow(),         const SizedBox(height: 18),
                    _buildAISuggestionCard(),          const SizedBox(height: 16),
                    _buildRecentActivityCard(),
                  ])),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHeroHeader() {
    final pct = _getCompletionPercentage();
    final statusText = pct == 1.0 ? 'All goals hit!' : pct >= 0.5 ? 'Making progress' : 'Let\'s get started';
    final statusColor = pct == 1.0 ? const Color(0xFF4ECCA3) : pct >= 0.5 ? const Color(0xFFFFC857) : Colors.white.withOpacity(0.5);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Greeting line
              Row(children: [
                Icon(_greetingIcon(), color: const Color(0xFFFFC857), size: 18),
                const SizedBox(width: 6),
                Text(_getGreeting(), style: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.60), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 7),
              // Name with shimmer
              if (_userProfileStream != null && user != null)
                StreamBuilder<DocumentSnapshot>(
                  stream: _userProfileStream,
                  builder: (context, snap) {
                    String name = _getDisplayName();
                    if (snap.hasData && snap.data!.exists) {
                      final d = snap.data!.data() as Map<String, dynamic>?;
                      if (d != null && d['name'] != null && d['name'].toString().isNotEmpty) name = d['name'].toString();
                    }
                    return AnimatedBuilder(
                      animation: _shimmerCtrl,
                      builder: (_, __) {
                        return ShaderMask(
                          shaderCallback: (bounds) {
                            final t = _shimmerCtrl.value;
                            return LinearGradient(
                              begin: Alignment(-1.0 + 3.0 * t, 0),
                              end: Alignment(-0.5 + 3.0 * t, 0),
                              colors: const [Colors.white, Color(0xFF2EC4B6), Colors.white],
                              stops: const [0.0, 0.5, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.srcIn,
                          child: Text(name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
                        );
                      },
                    );
                  },
                )
              else
                Text(_getDisplayName(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 9),
              // Date badge + status chip
              Wrap(spacing: 8, runSpacing: 6, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2EC4B6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.28)),
                  ),
                  child: Text(_formattedDate(), style: const TextStyle(fontSize: 10, color: Color(0xFF2EC4B6), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor,
                      boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 4)])),
                    const SizedBox(width: 6),
                    Text(statusText, style: TextStyle(fontSize: 9.5, color: statusColor, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ])),
            const SizedBox(width: 6),
            // Cyclist animation — decorative (larger, smoother)
            SizedBox(
              width: 100, height: 90,
              child: AnimatedBuilder(
                animation: _cyclistCtrl,
                builder: (_, __) {
                  final breathe = 1.0 + math.sin(_cyclistCtrl.value * math.pi * 2) * 0.02;
                  return Transform.scale(
                    scale: breathe,
                    child: CustomPaint(
                      painter: _CyclistPainter(
                        progress: _cyclistCtrl.value,
                        color: const Color(0xFF1A9E92),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            // Profile icon
            GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); setState(() => _currentIndex = 3); },
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 5)),
                    BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: user?.photoURL != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(15),
                        child: Image.network(user!.photoURL!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 22)))
                    : const Icon(Icons.person_rounded, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  DAILY HEALTH TIP BANNER — AI-powered, fresh every day
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDailyTipBanner() {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final glow = (math.sin(_shimmerCtrl.value * math.pi * 2) + 1) / 2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft, end: Alignment.centerRight,
              colors: [
                const Color(0xFF2EC4B6).withOpacity(0.10 + glow * 0.06),
                const Color(0xFF7B2CBF).withOpacity(0.07 + glow * 0.04),
                const Color(0xFF2EC4B6).withOpacity(0.08 + glow * 0.05),
              ],
            ),
            border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.20 + glow * 0.12)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_tipColor.withOpacity(0.25), _tipColor.withOpacity(0.10)]),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _tipColor.withOpacity(0.25)),
              ),
              child: _isTipLoading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_tipColor)))
                  : Icon(_tipIcon, color: _tipColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Daily Health Tip', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF2EC4B6).withOpacity(0.8), letterSpacing: 0.6)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2CBF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('AI', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: const Color(0xFF7B2CBF).withOpacity(0.9))),
                ),
              ]),
              const SizedBox(height: 3),
              _isTipLoading
                  ? Text('Generating today\'s tip...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4), height: 1.3, fontStyle: FontStyle.italic))
                  : Text(_dailyTip, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.75), height: 1.3)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isTipLoading ? null : () async {
                HapticFeedback.lightImpact();
                setState(() => _isTipLoading = true);
                final prefs = await SharedPreferences.getInstance();
                final today = DateTime.now();
                final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                // Clear cache so it fetches new
                await prefs.remove('tip_date');
                // Pick new random style
                final newIdx = (DateTime.now().millisecond) % _tipStyles.length;
                _tipIcon = _tipStyles[newIdx]['icon'] as IconData;
                _tipColor = _tipStyles[newIdx]['color'] as Color;
                await _fetchFreshTip(prefs, todayStr);
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isTipLoading ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
                  color: Colors.white.withOpacity(0.4), size: 14),
              ),
            ),
          ]),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SECTION HEADER
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSectionHeader(IconData icon, String title, {Color? iconColor}) {
    final color = iconColor ?? const Color(0xFF2EC4B6);
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Icon(icon, color: Colors.white, size: 13),
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.70), letterSpacing: 0.3)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.35), const Color(0xFF7B2CBF).withOpacity(0.15), Colors.transparent]),
          borderRadius: BorderRadius.circular(1),
        ))),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  STREAK + PROGRESS ROW
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildStreakProgressRow() {
    final streak = (todaysHealth['streak'] as num?)?.toInt() ?? 0;
    final pct = _getCompletionPercentage();
    final done = (todaysHealth['completedToday'] as List<String>? ?? <String>[]).length;

    return _staggerWrap(0, Row(children: [
      Expanded(child: _glassCard(child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: streak > 0 ? [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)] : [const Color(0xFF1E2A47), const Color(0xFF2C3E5C)]),
            boxShadow: [BoxShadow(color: (streak > 0 ? const Color(0xFFFF6B6B) : Colors.transparent).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Center(child: Icon(streak > 0 ? Icons.local_fire_department_rounded : Icons.rocket_launch_rounded, color: Colors.white, size: 24)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$streak', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(width: 3),
            Padding(padding: const EdgeInsets.only(bottom: 2),
              child: Text('day${streak != 1 ? 's' : ''}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
          Text(streak > 0 ? 'Keep going!' : 'Start today!', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
      ]))),
      const SizedBox(width: 12),
      Expanded(child: _glassCard(child: Row(children: [
        SizedBox(width: 48, height: 48, child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: pct,
            backgroundColor: Colors.white.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(pct == 1.0 ? const Color(0xFF4ECCA3) : const Color(0xFF2EC4B6)),
            strokeWidth: 5, strokeCap: StrokeCap.round,
          ),
          Text('$done', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${(pct * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1)),
          Text(pct == 1.0 ? 'Perfect day!' : '$done/4 done', style: TextStyle(
            color: pct == 1.0 ? const Color(0xFF4ECCA3) : Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
      ]))),
    ]));
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TODAY'S SUMMARY
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildTodaySummaryCard() {
    final completed = todaysHealth['completedToday'] as List<String>? ?? <String>[];
    final mood = todaysHealth['mood'];
    final sleep = todaysHealth['sleep'];
    final water = (todaysHealth['water'] as num?)?.toInt() ?? 0;
    final act = todaysHealth['activity'];

    return _staggerWrap(1, _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 13),
          ),
          const SizedBox(width: 8),
          const Text("Today's Snapshot", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final pulse = (math.sin(_pulseCtrl.value * math.pi * 2) + 1) / 2;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFF4ECCA3).withOpacity(0.10), const Color(0xFF4ECCA3).withOpacity(0.28), pulse),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.3 + pulse * 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: Color.lerp(const Color(0xFF4ECCA3).withOpacity(0.6), const Color(0xFF4ECCA3), pulse))),
                  const SizedBox(width: 5),
                  const Text('LIVE', style: TextStyle(color: Color(0xFF4ECCA3), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                ]),
              );
            },
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _summaryChip(Icons.mood_rounded, 'Mood', completed.contains('mood') ? 'Level ${mood ?? '--'}' : '--', completed.contains('mood'), const Color(0xFFFFC857)),
          _summaryDivider(),
          _summaryChip(Icons.bedtime_rounded, 'Sleep', completed.contains('sleep') ? '${sleep}h' : '--', completed.contains('sleep'), const Color(0xFF9D84B7)),
          _summaryDivider(),
          _summaryChip(Icons.water_drop_rounded, 'Water', water > 0 ? '$water cups' : '--', completed.contains('water'), const Color(0xFF2EC4B6)),
          _summaryDivider(),
          _summaryChip(Icons.directions_run_rounded, 'Activity', act != null ? '${(act as Map)['duration']}m' : '--', completed.contains('activity'), const Color(0xFF4ECCA3)),
        ]),
      ]),
    ));
  }

  Widget _summaryChip(IconData icon, String label, String value, bool done, Color color) => Expanded(
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: (done ? color : Colors.white).withOpacity(done ? 0.15 : 0.06),
          shape: BoxShape.circle),
        child: Icon(icon, color: done ? color : Colors.white.withOpacity(0.35), size: 18),
      ),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(color: done ? Colors.white : Colors.white.withOpacity(0.35), fontSize: 13, fontWeight: FontWeight.w900, height: 1)),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      const SizedBox(height: 6),
      // Mini progress indicator
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: done ? 28 : 20, height: 3,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
          color: done ? null : Colors.white.withOpacity(0.08),
          gradient: done ? const LinearGradient(colors: [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]) : null)),
    ]),
  );
  Widget _summaryDivider() => Container(width: 1, height: 48, decoration: BoxDecoration(
    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Colors.white.withOpacity(0.02), Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.02)]),
  ));

  // ═══════════════════════════════════════════════════════════════════════
  //  QUICK ACTIONS GRID
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildQuickActionsGrid() {
    final actions = [
      {'icon': Icons.mood_rounded, 'label': 'Mood', 'color': const Color(0xFFFFC857), 'grad': [const Color(0xFFFFC857), const Color(0xFFFF9F1C)],
       'completed': (todaysHealth['completedToday'] as List<String>? ?? <String>[]).contains('mood'), 'screen': const MoodTrackerScreen()},
      {'icon': Icons.bedtime_rounded, 'label': 'Sleep', 'color': const Color(0xFF9D84B7), 'grad': [const Color(0xFF9D84B7), const Color(0xFF7B2CBF)],
       'completed': (todaysHealth['completedToday'] as List<String>? ?? <String>[]).contains('sleep'), 'screen': const SleepTrackerScreen()},
      {'icon': Icons.water_drop_rounded, 'label': 'Water', 'color': const Color(0xFF2EC4B6), 'grad': [const Color(0xFF2EC4B6), const Color(0xFF00D9FF)],
       'completed': (todaysHealth['completedToday'] as List<String>? ?? <String>[]).contains('water'), 'screen': const WaterTrackerScreen()},
      {'icon': Icons.directions_run_rounded, 'label': 'Activity', 'color': const Color(0xFF4ECCA3), 'grad': [const Color(0xFF4ECCA3), const Color(0xFF2EC4B6)],
       'completed': (todaysHealth['completedToday'] as List<String>? ?? <String>[]).contains('activity'), 'screen': const ActivityTrackerScreen()},
    ];

    return _staggerWrap(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]).createShader(r),
          child: const Text('Quick Actions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3)),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Text('Tap to log', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: List.generate(actions.length, (i) {
        final a = actions[i];
        final done = a['completed'] as bool;
        final col = a['color'] as Color;
        final grad = a['grad'] as List<Color>;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              final result = await Navigator.push(context, PageRouteBuilder(
                pageBuilder: (_, anim, __) => a['screen'] as Widget,
                transitionDuration: const Duration(milliseconds: 400),
                transitionsBuilder: (_, anim, __, child) => SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ));
              if (result == true) { await _loadDataInBackground(); if (mounted) setState(() {}); }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: done
                    ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [col.withOpacity(0.28), col.withOpacity(0.12)])
                    : LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: done ? col.withOpacity(0.5) : Colors.white.withOpacity(0.12), width: 1.2),
                boxShadow: [BoxShadow(color: col.withOpacity(done ? 0.25 : 0.0), blurRadius: done ? 14 : 0, offset: const Offset(0, 5))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(alignment: Alignment.center, children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: done ? LinearGradient(colors: grad) : null,
                      color: done ? null : Colors.white.withOpacity(0.08),
                      boxShadow: done ? [BoxShadow(color: col.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))] : []),
                    child: Center(child: Icon(a['icon'] as IconData, color: Colors.white, size: 22))),
                  if (done) Positioned(top: 0, right: 0,
                    child: Container(width: 15, height: 15,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4ECCA3),
                        border: Border.all(color: const Color(0xFF0A0E21), width: 1.5),
                        boxShadow: [BoxShadow(color: const Color(0xFF4ECCA3).withOpacity(0.5), blurRadius: 6)]),
                      child: const Icon(Icons.check, color: Colors.white, size: 9))),
                ]),
                const SizedBox(height: 8),
                Text(a['label'] as String, style: TextStyle(color: done ? col : Colors.white.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ));
      })),
    ]));
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HEALTH SCORE CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHealthScoreCard() {
    return _staggerWrap(3, GestureDetector(
      onTap: () => _navigateTo(const AIHealthScoreScreen()),
      child: Stack(children: [
        // Subtle pulse ring behind the card
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => CustomPaint(
              painter: _PulseRingPainter(progress: _pulseCtrl.value, color: const Color(0xFF2EC4B6)),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF2EC4B6), Color(0xFF239B8F), Color(0xFF7B2CBF), Color(0xFFFF6B6B)],
              stops: [0.0, 0.35, 0.7, 1.0]),
            boxShadow: [
              BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 28, offset: const Offset(0, 10)),
              BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI Health Score', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                const SizedBox(height: 4),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 9), SizedBox(width: 3),
                    Text('ML POWERED', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ])),
              ])),
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14)),
            ]),
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _scoreMini(Icons.mood_rounded, todaysHealth['mood'] != null ? '${todaysHealth['mood']}' : '--', 'Mood', todaysHealth['mood'] != null && (todaysHealth['mood'] as num) >= 3),
                Container(width: 1.5, height: 34, color: Colors.white.withOpacity(0.25)),
                _scoreMini(Icons.bedtime_rounded, todaysHealth['sleep'] != null ? '${(todaysHealth['sleep'] as num).toStringAsFixed(0)}h' : '--', 'Sleep', todaysHealth['sleep'] != null && (todaysHealth['sleep'] as num) >= 6),
                Container(width: 1.5, height: 34, color: Colors.white.withOpacity(0.25)),
                _scoreMini(Icons.water_drop_rounded, '${(todaysHealth['water'] as num?)?.toInt() ?? 0}', 'Water', (todaysHealth['water'] as num?)?.toInt() != null && (todaysHealth['water'] as num).toInt() >= 4),
              ])),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.touch_app_rounded, color: Colors.white.withOpacity(0.85), size: 12),
              const SizedBox(width: 4),
              Text('Tap for detailed analysis', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
    ));
  }

  Widget _scoreMini(IconData icon, String val, String label, bool good) => Column(children: [
    Icon(icon, color: Colors.white, size: 16), const SizedBox(height: 4),
    Text(val, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 8, fontWeight: FontWeight.w600)),
    const SizedBox(height: 3),
    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: (good ? const Color(0xFF4ECCA3) : const Color(0xFFFF9068)).withOpacity(0.3), borderRadius: BorderRadius.circular(4)),
      child: Text(good ? 'Good' : 'Watch', style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800))),
  ]);

  // ═══════════════════════════════════════════════════════════════════════
  //  AI HEALTH SCANNER CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildAIHealthScannerCard() {
    return _staggerWrap(4, GestureDetector(
      onTap: () => _navigateTo(const HealthScannerScreen()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [const Color(0xFFFF6B6B).withOpacity(0.18), const Color(0xFF7B2CBF).withOpacity(0.16), const Color(0xFF00D9FF).withOpacity(0.10)]),
              border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.40), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 8)),
                BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
              ]),
            child: Column(children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFF7B2CBF)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: const Icon(Icons.radar_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('AI Health Scanner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
                  const SizedBox(height: 3),
                  Text('Measure vitals with camera', style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w600)),
                ])),
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12)),
              ]),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _scanStat(Icons.monitor_heart_rounded, 'HR', 'BPM', const Color(0xFFFF6B6B)), _tinyDiv(),
                  _scanStat(Icons.air_rounded, 'Resp', '/min', const Color(0xFF00D9FF)), _tinyDiv(),
                  _scanStat(Icons.psychology_rounded, 'Stress', 'Lvl', const Color(0xFFFFC857)), _tinyDiv(),
                  _scanStat(Icons.bloodtype_rounded, 'BP', 'mmHg', const Color(0xFF9D84B7)),
                ])),
              const SizedBox(height: 10),
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFD94B7B), Color(0xFF7B2CBF)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.30), blurRadius: 12, offset: const Offset(0, 5))]),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.radio_button_checked_rounded, color: Colors.white, size: 14), SizedBox(width: 8),
                  Text('Start Scan  →', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                ])),
            ]),
          ),
        ),
      ),
    ));
  }

  Widget _scanStat(IconData icon, String label, String unit, Color color) {
    return Column(children: [
      Icon(icon, color: color.withOpacity(0.7), size: 18),
      const SizedBox(height: 3),
      Text('--', style: TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 14, fontWeight: FontWeight.w900, height: 1)),
      const SizedBox(height: 1),
      Text(unit, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 8, fontWeight: FontWeight.w700)),
    ]);
  }
  Widget _tinyDiv() {
    return Container(width: 1, height: 32, decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.white.withOpacity(0.02), Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.02)]),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  FEATURE BUTTONS ROW
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildFeatureButtonsRow() {
    return _staggerWrap(5, Row(children: [
      Expanded(child: _featureButton(icon: Icons.medical_services_rounded, label: 'Symptoms', sub: 'Check now',
        grad: [const Color(0xFFFF6B6B), const Color(0xFFFF9068)], onTap: () => _navigateTo(const SymptomCheckerScreen()))),
      const SizedBox(width: 10),
      Expanded(child: _featureButton(icon: Icons.picture_as_pdf_rounded, label: 'PDF Report', sub: 'Export',
        grad: [const Color(0xFF7B2CBF), const Color(0xFF9D84B7)], onTap: () => _navigateTo(const PdfReportScreen()))),
      const SizedBox(width: 10),
      Expanded(child: _featureButton(icon: Icons.notifications_active_rounded, label: 'Reminders', sub: 'Stay on track',
        grad: [const Color(0xFFFF9068), const Color(0xFFFF6B6B)], onTap: () => _navigateTo(const RemindersScreen()))),
    ]));
  }

  Widget _featureButton({required IconData icon, required String label, required String sub, required List<Color> grad, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [grad[0].withOpacity(0.24), grad[1].withOpacity(0.12)],
              ),
              border: Border.all(color: grad[0].withOpacity(0.35), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: grad[0].withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: grad),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: grad[0].withOpacity(0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  AI SUGGESTION CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildAISuggestionCard() {
    return _staggerWrap(6, _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))]),
          child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AI Health Coach', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          const SizedBox(height: 2),
          Text('Personalized insight', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
        AnimatedBuilder(
          animation: _shimmerCtrl,
          builder: (_, __) {
            final v = _shimmerCtrl.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Color.lerp(const Color(0xFF4ECCA3).withOpacity(0.15), const Color(0xFF4ECCA3).withOpacity(0.35), (math.sin(v * math.pi * 2) + 1) / 2),
                borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4ECCA3))),
                const SizedBox(width: 4),
                const Text('LIVE', style: TextStyle(color: Color(0xFF4ECCA3), fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ]),
            );
          },
        ),
      ]),
      const SizedBox(height: 12),
      // Gradient accent line on left side like a blockquote
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7), Color(0xFF7B2CBF)]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Text(_generateAISuggestion(), style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 12.5, height: 1.55, fontWeight: FontWeight.w500, letterSpacing: 0.1)))),
        ]),
      ),
    ])));
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RECENT ACTIVITY CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildRecentActivityCard() {
    return _staggerWrap(7, _glassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: const Icon(Icons.timeline_rounded, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        const Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
        const Spacer(),
        if (recentActivities.isNotEmpty)
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]), borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.2), blurRadius: 6)]),
            child: Text('${recentActivities.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
      ]),
      const SizedBox(height: 14),
      if (recentActivities.isEmpty)
        Container(padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(children: [
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.2), const Color(0xFF9D84B7).withOpacity(0.2)])),
              child: Icon(Icons.timeline_rounded, color: Colors.white.withOpacity(0.5), size: 26)),
            const SizedBox(height: 12),
            Text('No recent activities', style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Start logging to see your progress here', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10.5)),
          ]))
      else
        ...recentActivities.asMap().entries.map((entry) {
          final i = entry.key;
          final a = entry.value;
          final isLast = i == recentActivities.length - 1;
          final typeColor = _getActivityColor(a['type']);
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Timeline connector
              SizedBox(width: 26, child: Column(children: [
                Container(width: 11, height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [typeColor, typeColor.withOpacity(0.6)]),
                    boxShadow: [BoxShadow(color: typeColor.withOpacity(0.45), blurRadius: 8)],
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [typeColor.withOpacity(0.5), typeColor.withOpacity(0.08)]),
                  ),
                )),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: typeColor.withOpacity(0.14)),
                ),
                child: Row(children: [
                  Container(width: 38, height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [typeColor.withOpacity(0.28), typeColor.withOpacity(0.14)]),
                      borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Icon(_getActivityIcon(a['type']), color: typeColor, size: 18))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_getActivityTitle(a['type'], a['data']),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.92)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(_formatTimeAgo(a['timestamp']), style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600)),
                  ])),
                ]),
              )),
            ]),
          );
        }),
    ])));
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'mood': return const Color(0xFFFFC857);
      case 'sleep': return const Color(0xFF9D84B7);
      case 'water': return const Color(0xFF2EC4B6);
      case 'activity': return const Color(0xFF4ECCA3);
      default: return const Color(0xFF2EC4B6);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SHARED UI HELPERS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding ?? const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.05)]),
            border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 8)),
              BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.03), blurRadius: 30, offset: const Offset(0, 4)),
            ]),
          child: child,
        ),
      ),
    );
  }

  Widget _staggerWrap(int index, Widget child) {
    final idx = index.clamp(0, _stagger.length - 1);
    return AnimatedBuilder(
      animation: _stagger[idx],
      builder: (_, __) => Opacity(
        opacity: _stagger[idx].value,
        child: Transform.translate(offset: Offset(0, (1 - _stagger[idx].value) * 20), child: child),
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════
  //  BOTTOM NAV
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildBottomNav() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF141829).withOpacity(0.94),
              const Color(0xFF0D1128),
            ],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF2EC4B6).withOpacity(0.15),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.50),
              blurRadius: 35,
              offset: const Offset(0, -12),
            ),
            BoxShadow(
              color: const Color(0xFF2EC4B6).withOpacity(0.06),
              blurRadius: 50,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _navItem(Icons.home_rounded, Icons.home_outlined, 'Home', 0),
                    _navItem(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'AI Chat', 1),
                    _navItem(Icons.insights_rounded, Icons.insights_outlined, 'Insights', 2),
                    _navItem(Icons.person_rounded, Icons.person_outline_rounded, 'Profile', 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData activeIcon, IconData inactiveIcon, String label, int index) {
    final active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon with scale + glow
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(active ? 8 : 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF2EC4B6).withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2EC4B6).withOpacity(active ? 0.20 : 0.0),
                    blurRadius: active ? 16 : 0,
                    spreadRadius: active ? 1 : 0,
                  ),
                ],
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: active ? 1.0 : 0.85),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Icon(
                  active ? activeIcon : inactiveIcon,
                  color: active
                      ? const Color(0xFF2EC4B6)
                      : Colors.white.withOpacity(0.38),
                  size: active ? 24 : 22,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: active
                    ? const Color(0xFF2EC4B6)
                    : Colors.white.withOpacity(0.38),
                fontSize: active ? 10.5 : 9.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: active ? 0.4 : 0.2,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 4),
            // Active indicator dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: active ? 18 : 0,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFF2EC4B6), Color(0xFF00D9FF)],
                      )
                    : const LinearGradient(
                        colors: [Colors.transparent, Colors.transparent],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2EC4B6).withOpacity(active ? 0.5 : 0.0),
                    blurRadius: active ? 8 : 0,
                    spreadRadius: active ? 1 : 0,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
