import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui' as ui;
import '../services/notification_service.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _shimmerCtrl;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _titleFade;
  late Animation<double> _subtitleFade;
  late Animation<double> _bottomFade;
  late Animation<Offset> _titleSlide;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _glowAnim;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _initAnimations();
    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _shimmerCtrl.repeat();
    });
    _navigateToNextScreen();
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Logo: fade + scale (0% → 30%)
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.30, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic)),
    );

    // Title: fade + slide (15% → 45%)
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.15, 0.45, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.15, 0.45, curve: Curves.easeOutCubic)),
    );

    // Subtitle: fade + slide (30% → 55%)
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.30, 0.55, curve: Curves.easeOut)),
    );
    _subtitleSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.30, 0.55, curve: Curves.easeOutCubic)),
    );

    // Bottom info: fade (45% → 70%)
    _bottomFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.45, 0.70, curve: Curves.easeOut)),
    );

    // Glow pulse
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    // Shimmer sweep
    _shimmerAnim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  void _navigateToNextScreen() async {
    // ⚡ Initialize Firebase + services WHILE splash is showing
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: "AIzaSyBIiTjxm2S9tjFsgDgYd51nA5noJ7yqZsw",
            authDomain: "swasthyaai-health-app.firebaseapp.com",
            projectId: "swasthyaai-health-app",
            storageBucket: "swasthyaai-health-app.firebasestorage.app",
            messagingSenderId: "196805937310",
            appId: "1:196805937310:web:dd95c554b6c68b8016138f",
            measurementId: "G-JBWVWEDXXH",
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
      debugPrint('✅ Firebase initialized successfully');

      if (!kIsWeb) {
        await NotificationService().initialize();
        debugPrint('✅ Notifications initialized');
        if (FirebaseAuth.instance.currentUser != null) {
          await NotificationService().enableAllRemindersForNewUser();
        }
      }
    } catch (e) {
      debugPrint('❌ Init failed: $e');
    }

    // Ensure splash shows for at least 2s (fast & professional)
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    final user = FirebaseAuth.instance.currentUser;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) =>
            user != null ? const DashboardScreen() : const AuthScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _glowCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1328), Color(0xFF0A0E21), Color(0xFF080B1A)],
          ),
        ),
        child: Stack(children: [
          // ── Subtle ambient glow behind logo ─────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 300 + _glowAnim.value * 30,
                height: 300 + _glowAnim.value * 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2EC4B6).withOpacity(0.07 + _glowAnim.value * 0.04),
                      const Color(0xFF7B2CBF).withOpacity(0.04 + _glowAnim.value * 0.02),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Second subtle orb — top right ───────────────────────────
          Positioned(
            top: -40,
            right: -40,
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7B2CBF).withOpacity(0.06 + _glowAnim.value * 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Third subtle orb — bottom left ──────────────────────────
          Positioned(
            bottom: -30,
            left: -30,
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2EC4B6).withOpacity(0.05 + _glowAnim.value * 0.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo ──────────────────────────────────────────────
                AnimatedBuilder(
                  animation: _entryCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: _buildLogo(),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── App Name ──────────────────────────────────────────
                AnimatedBuilder(
                  animation: _entryCtrl,
                  builder: (_, __) => FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Color(0xFF2EC4B6), Color(0xFF4ECCA3), Color(0xFF2EC4B6)],
                        ).createShader(r),
                        child: const Text(
                          'Healthify',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Tagline ───────────────────────────────────────────
                AnimatedBuilder(
                  animation: _entryCtrl,
                  builder: (_, __) => FadeTransition(
                    opacity: _subtitleFade,
                    child: SlideTransition(
                      position: _subtitleSlide,
                      child: Text(
                        'Your Intelligent Health Companion',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.45),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom section ──────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: AnimatedBuilder(
              animation: _entryCtrl,
              builder: (_, __) => Opacity(
                opacity: _bottomFade.value,
                child: Column(children: [
                  // Loading shimmer bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: AnimatedBuilder(
                      animation: _shimmerCtrl,
                      builder: (_, __) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 3,
                            child: Stack(children: [
                              Container(color: Colors.white.withOpacity(0.06)),
                              FractionallySizedBox(
                                widthFactor: 1.0,
                                child: ShaderMask(
                                  shaderCallback: (bounds) {
                                    final t = _shimmerCtrl.value;
                                    return LinearGradient(
                                      begin: Alignment(-1.0 + 3.0 * t, 0),
                                      end: Alignment(-0.4 + 3.0 * t, 0),
                                      colors: [
                                        Colors.transparent,
                                        const Color(0xFF2EC4B6).withOpacity(0.7),
                                        const Color(0xFF7B2CBF).withOpacity(0.5),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.4, 0.6, 1.0],
                                    ).createShader(bounds);
                                  },
                                  blendMode: BlendMode.srcIn,
                                  child: Container(color: Colors.white),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  // AI badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4ECCA3),
                          boxShadow: [BoxShadow(color: const Color(0xFF4ECCA3).withOpacity(0.5), blurRadius: 4)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Powered by AI',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.4),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  LOGO — clean glassmorphic card with subtle shimmer
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2EC4B6).withOpacity(0.12 + _glowAnim.value * 0.08),
              blurRadius: 35 + _glowAnim.value * 12,
              spreadRadius: -6,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: const Color(0xFF7B2CBF).withOpacity(0.06 + _glowAnim.value * 0.04),
              blurRadius: 50,
              spreadRadius: -10,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.16),
                    Colors.white.withOpacity(0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                  width: 1.2,
                ),
              ),
              child: Stack(children: [
                // Shimmer sweep
                AnimatedBuilder(
                  animation: _shimmerAnim,
                  builder: (_, __) => Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Transform.translate(
                        offset: Offset(_shimmerAnim.value * 150, 0),
                        child: Container(
                          width: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.10),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Icon with gradient circle
                Center(
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2EC4B6).withOpacity(0.30 + _glowAnim.value * 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

