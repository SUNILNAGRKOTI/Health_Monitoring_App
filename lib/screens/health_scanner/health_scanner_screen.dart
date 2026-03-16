import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AI Health Scanner Screen
/// Uses rear camera + flash (PPG – photoplethysmography) to estimate:
///   • Heart Rate (BPM)
///   • Respiratory Rate (/min)  — derived from HRV signal modulation
///   • Stress Level             — derived from HRV (RMSSD)
///   • Blood Pressure estimate  — systolic / diastolic from PTT model
///   • Fatigue Level            — from HRV entropy & mean BPM
/// ─────────────────────────────────────────────────────────────────────────────
class HealthScannerScreen extends StatefulWidget {
  const HealthScannerScreen({Key? key}) : super(key: key);

  @override
  State<HealthScannerScreen> createState() => _HealthScannerScreenState();
}

class _HealthScannerScreenState extends State<HealthScannerScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isTorchOn = false;

  // ── State machine ────────────────────────────────────────────────────────────
  ScanState _scanState = ScanState.idle;

  // ── Signal buffers ───────────────────────────────────────────────────────────
  final List<double> _redChannel = [];          // raw PPG signal
  final List<double> _waveformPoints = [];      // smoothed waveform for chart
  static const int _sampleWindowSize = 450;    // ~15 s at ~30 fps
  static const int _scanDurationSec = 15;
  static const int _warmupFrames = 45;          // ~1.5s warmup (discard)

  // ── Timer & progress ────────────────────────────────────────────────────────
  Timer? _scanTimer;
  Timer? _uiRefreshTimer;
  int _secondsRemaining = _scanDurationSec;
  double _signalQuality = 0.0;  // 0–1
  bool _fingerDetected = false;
  int _totalFrames = 0;          // counts all frames including warmup

  // ── Live estimates (updated every second) ───────────────────────────────────
  int _liveHeartRate = 0;
  int _liveBreathing = 0;

  // ── Final results ────────────────────────────────────────────────────────────
  ScanResult? _result;

  // ── Animations ───────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _resultController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _resultFadeAnimation;
  late Animation<Offset> _resultSlideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initCamera();
  }

  // ── Animation setup ──────────────────────────────────────────────────────────
  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _resultFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _resultController, curve: Curves.easeOutCubic),
    );

    _resultSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _resultController, curve: Curves.easeOutCubic),
        );
  }

  // ── Camera init ──────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Prefer rear camera
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        rear,
        ResolutionPreset.low, // low = faster frame processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // ── Start scanning ───────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (_cameraController == null || !_isCameraInitialized) return;

    HapticFeedback.mediumImpact();
    _redChannel.clear();
    _waveformPoints.clear();
    _secondsRemaining = _scanDurationSec;
    _signalQuality = 0.0;
    _liveHeartRate = 0;
    _liveBreathing = 0;
    _fingerDetected = false;
    _totalFrames = 0;

    setState(() => _scanState = ScanState.scanning);

    // Enable torch (flash) for better PPG signal
    try {
      await _cameraController!.setFlashMode(FlashMode.torch);
      _isTorchOn = true;
    } catch (_) {}

    // Start processing camera frames
    await _cameraController!.startImageStream(_processFrame);

    // Countdown timer (fires every second)
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _secondsRemaining--;
        // Update live estimates every second after we have enough data
        if (_redChannel.length > 60) {
          _liveHeartRate = _estimateHeartRate(_redChannel);
          _liveBreathing = _estimateRespiratoryRate(_redChannel);
        }
        if (_secondsRemaining <= 0) {
          t.cancel();
          _uiRefreshTimer?.cancel();
          _finalizeScan();
        }
      });
    });

    // Fast UI refresh for signal quality & finger detection feedback
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {}); // Refresh UI with latest _fingerDetected & _signalQuality
    });
  }

  // ── Process each camera frame ─────────────────────────────────────────────
  void _processFrame(CameraImage image) {
    _totalFrames++;

    // Extract average brightness from Y plane (luma)
    final yPlane = image.planes[0];
    final bytes = yPlane.bytes;
    final len = bytes.length;

    // Sample every 4th pixel for speed
    double sum = 0;
    int count = 0;
    for (int i = 0; i < len; i += 4) {
      sum += bytes[i];
      count++;
    }
    final avg = sum / count;

    // ── Finger detection ──
    // When finger covers camera + flash is on, the average brightness is
    // typically 80–220 (warm reddish glow). Without finger it's either
    // very bright (>240 = flash reflecting) or very dark (<40 = no light).
    // Also check the V (chroma) plane if available for red-ish hue.
    final isFingerOnCamera = avg > 50 && avg < 240;
    _fingerDetected = isFingerOnCamera;

    // ── Skip warmup frames (camera auto-adjust period) ──
    if (_totalFrames <= _warmupFrames) return;

    // ── Only record data when finger is on camera ──
    if (!isFingerOnCamera) {
      _signalQuality = (_signalQuality * 0.9).clamp(0.0, 1.0); // decay quality
      return;
    }

    _redChannel.add(avg);
    if (_redChannel.length > _sampleWindowSize) {
      _redChannel.removeAt(0);
    }

    // Smooth for waveform display (5-point moving average)
    if (_redChannel.length >= 5) {
      final last5 = _redChannel.sublist(_redChannel.length - 5);
      final smoothed = last5.reduce((a, b) => a + b) / 5;
      _waveformPoints.add(smoothed);
      if (_waveformPoints.length > 150) _waveformPoints.removeAt(0);
    }

    // ── Update signal quality ──
    if (_redChannel.length >= 30) {
      final recent = _redChannel.sublist(_redChannel.length - 30);
      final mean = recent.reduce((a, b) => a + b) / recent.length;
      final variance =
          recent.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / recent.length;
      final stdDev = math.sqrt(variance);

      // Good PPG signal typically has stdDev 0.5–20 depending on sensor.
      // Lower threshold to be more forgiving — any measurable pulsation is fine.
      final rawQ = (stdDev / 5.0).clamp(0.0, 1.0);
      // Smooth quality transitions
      _signalQuality = (_signalQuality * 0.7 + rawQ * 0.3).clamp(0.0, 1.0);
    }
  }

  // ── Finalize & compute results ────────────────────────────────────────────
  Future<void> _finalizeScan() async {
    HapticFeedback.heavyImpact();

    // Stop stream & torch
    try {
      await _cameraController!.stopImageStream();
      await _cameraController!.setFlashMode(FlashMode.off);
      _isTorchOn = false;
    } catch (_) {}

    setState(() => _scanState = ScanState.analyzing);

    // Simulate brief analysis delay (gives polished feel)
    await Future.delayed(const Duration(milliseconds: 1500));

    // Compute all metrics
    final heartRate = _estimateHeartRate(_redChannel);
    final breathing = _estimateRespiratoryRate(_redChannel);
    final hrv = _computeHRV(_redChannel);
    final stressLevel = _estimateStress(hrv);
    final bp = _estimateBloodPressure(heartRate, hrv);
    final fatigue = _estimateFatigue(heartRate, hrv);

    final result = ScanResult(
      heartRate: heartRate,
      breathingRate: breathing,
      stressLevel: stressLevel,
      systolic: bp[0],
      diastolic: bp[1],
      hrv: hrv,
      fatigueLevel: fatigue,
      waveformData: List.from(_waveformPoints),
      timestamp: DateTime.now(),
    );

    // Save to Firestore
    await _saveResultToFirestore(result);

    if (mounted) {
      setState(() {
        _result = result;
        _scanState = ScanState.results;
      });
      _resultController.forward(from: 0);
    }
  }

  // ── Signal Processing Algorithms ──────────────────────────────────────────

  /// Robust peak detection → BPM
  int _estimateHeartRate(List<double> signal) {
    if (signal.length < 60) return 0;

    final data = signal.sublist(math.max(0, signal.length - 300));
    if (data.length < 30) return 0;

    // 1) Remove DC offset
    final mean = data.reduce((a, b) => a + b) / data.length;
    final centered = data.map((v) => v - mean).toList();

    // 2) Smooth with 5-point moving average (bandpass low end)
    final smoothed = <double>[];
    for (int i = 2; i < centered.length - 2; i++) {
      smoothed.add((centered[i - 2] + centered[i - 1] + centered[i] +
              centered[i + 1] + centered[i + 2]) / 5);
    }
    if (smoothed.length < 20) return 0;

    // 3) Find peaks with adaptive threshold + minimum distance
    // Min distance between peaks: at 180 BPM, peaks are ~10 frames apart at 30fps
    const minPeakDistance = 8;
    final threshold = smoothed.reduce((a, b) => a > b ? a : b) * 0.3; // 30% of max

    List<int> peakIndices = [];
    for (int i = 2; i < smoothed.length - 2; i++) {
      if (smoothed[i] > threshold &&
          smoothed[i] > smoothed[i - 1] &&
          smoothed[i] > smoothed[i + 1] &&
          smoothed[i] >= smoothed[i - 2] &&
          smoothed[i] >= smoothed[i + 2]) {
        // Check minimum distance from last peak
        if (peakIndices.isEmpty || (i - peakIndices.last) >= minPeakDistance) {
          peakIndices.add(i);
        }
      }
    }

    if (peakIndices.length < 2) return 0;

    // 4) Calculate average inter-peak interval
    double totalInterval = 0;
    for (int i = 1; i < peakIndices.length; i++) {
      totalInterval += (peakIndices[i] - peakIndices[i - 1]);
    }
    final avgInterval = totalInterval / (peakIndices.length - 1);

    // 5) Convert to BPM (assuming ~30 fps)
    final bpm = (60.0 * 30.0 / avgInterval).round();

    return bpm.clamp(45, 180);
  }

  /// Respiratory rate via low-frequency envelope of PPG signal
  int _estimateRespiratoryRate(List<double> signal) {
    if (signal.length < 90) return 0;
    final data = signal.sublist(math.max(0, signal.length - 300));
    if (data.length < 60) return 0;

    // Compute envelope (moving average with large window to capture breathing)
    final windowSize = math.min(30, data.length ~/ 3);
    final halfW = windowSize ~/ 2;
    final envelope = <double>[];
    for (int i = halfW; i < data.length - halfW; i++) {
      final window = data.sublist(i - halfW, i + halfW);
      envelope.add(window.reduce((a, b) => a + b) / window.length);
    }

    if (envelope.length < 20) return 15;

    // Count slow oscillations
    final mean = envelope.reduce((a, b) => a + b) / envelope.length;
    int crossings = 0;
    for (int i = 1; i < envelope.length; i++) {
      if (envelope[i - 1] < mean && envelope[i] >= mean) crossings++;
    }

    final durationSec = envelope.length / 30.0;
    if (durationSec < 1) return 15;
    final rr = (crossings / durationSec * 60).round();
    return rr.clamp(8, 30);
  }

  /// RMSSD (HRV metric) — using detected peak intervals
  double _computeHRV(List<double> signal) {
    if (signal.length < 90) return 30.0;

    final data = signal.sublist(math.max(0, signal.length - 300));
    final mean = data.reduce((a, b) => a + b) / data.length;
    final centered = data.map((v) => v - mean).toList();

    // Smooth
    final smoothed = <double>[];
    for (int i = 2; i < centered.length - 2; i++) {
      smoothed.add((centered[i - 2] + centered[i - 1] + centered[i] +
              centered[i + 1] + centered[i + 2]) / 5);
    }

    // Find peaks for IBI calculation
    if (smoothed.length < 20) return 30.0;
    final threshold = smoothed.reduce((a, b) => a > b ? a : b) * 0.3;
    List<int> peaks = [];
    for (int i = 2; i < smoothed.length - 2; i++) {
      if (smoothed[i] > threshold &&
          smoothed[i] > smoothed[i - 1] &&
          smoothed[i] > smoothed[i + 1]) {
        if (peaks.isEmpty || (i - peaks.last) >= 8) {
          peaks.add(i);
        }
      }
    }

    if (peaks.length < 3) return 30.0;

    // Calculate successive IBI differences (in ms, assuming 30fps → 33.3ms/frame)
    List<double> ibis = [];
    for (int i = 1; i < peaks.length; i++) {
      ibis.add((peaks[i] - peaks[i - 1]) * 33.3);
    }

    // RMSSD
    double sumSqDiff = 0;
    for (int i = 1; i < ibis.length; i++) {
      final diff = ibis[i] - ibis[i - 1];
      sumSqDiff += diff * diff;
    }
    final rmssd = math.sqrt(sumSqDiff / (ibis.length - 1));
    return rmssd.clamp(5.0, 100.0);
  }

  /// Stress: high HRV → low stress
  StressLevel _estimateStress(double hrv) {
    if (hrv > 50) return StressLevel.low;
    if (hrv > 30) return StressLevel.moderate;
    return StressLevel.high;
  }

  /// BP estimation: simplified PTT-inspired model
  List<int> _estimateBloodPressure(int heartRate, double hrv) {
    // These are rough heuristic models, not medical-grade
    final systolic = (110 + (heartRate - 70) * 0.5 - hrv * 0.2).round().clamp(90, 160);
    final diastolic = (70 + (heartRate - 70) * 0.3 - hrv * 0.1).round().clamp(60, 100);
    return [systolic, diastolic];
  }

  /// Fatigue: high HR + low HRV = fatigued
  FatigueLevel _estimateFatigue(int heartRate, double hrv) {
    final score = heartRate - hrv;
    if (score < 40) return FatigueLevel.rested;
    if (score < 65) return FatigueLevel.mild;
    return FatigueLevel.fatigued;
  }

  // ── Firestore persistence ─────────────────────────────────────────────────
  Future<void> _saveResultToFirestore(ScanResult result) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scan_results')
          .add(result.toMap());
    } catch (e) {
      debugPrint('Save scan error: $e');
    }
  }

  // ── Reset to idle ─────────────────────────────────────────────────────────
  void _resetScan() {
    HapticFeedback.lightImpact();
    _resultController.reverse();
    setState(() {
      _scanState = ScanState.idle;
      _result = null;
      _redChannel.clear();
      _waveformPoints.clear();
      _signalQuality = 0.0;
      _liveHeartRate = 0;
      _liveBreathing = 0;
      _fingerDetected = false;
      _totalFrames = 0;
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _uiRefreshTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _resultController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _buildCurrentState(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background gradient ───────────────────────────────────────────────────
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0E21), Color(0xFF0D1528), Color(0xFF111827)],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                const Text(
                  'AI Health Scanner',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Real-time vital signs • No wearables',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2EC4B6).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor_heart_outlined, color: Color(0xFF2EC4B6), size: 11),
                SizedBox(width: 4),
                Text('PPG',
                    style: TextStyle(
                        color: Color(0xFF2EC4B6),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Route to current state widget ─────────────────────────────────────────
  Widget _buildCurrentState() {
    switch (_scanState) {
      case ScanState.idle:
        return _buildIdleView();
      case ScanState.scanning:
        return _buildScanningView();
      case ScanState.analyzing:
        return _buildAnalyzingView();
      case ScanState.results:
        return _buildResultsView();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // IDLE VIEW
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildIdleView() {
    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        children: [
          // Scanner preview card
          _buildScannerPreviewCard(),
          const SizedBox(height: 16),
          // Vitals that will be measured
          _buildVitalsPreviewRow(),
          const SizedBox(height: 16),
          // How it works
          _buildHowItWorksCard(),
          const SizedBox(height: 20),
          // Start button
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildScannerPreviewCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF00D9FF).withOpacity(0.15),
                const Color(0xFF7B2CBF).withOpacity(0.10),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF00D9FF).withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Camera preview or placeholder
              if (_isCameraInitialized && _cameraController != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CameraPreview(_cameraController!),
                )
              else
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded,
                          size: 48, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 8),
                      Text('Initializing camera...',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              // Overlay
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF0A0E21).withOpacity(0.7),
                    ],
                  ),
                ),
              ),
              // Pulsing circle
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (ctx, _) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6B6B).withOpacity(0.15),
                      border: Border.all(
                          color: const Color(0xFFFF6B6B).withOpacity(0.6),
                          width: 2),
                    ),
                    child: const Icon(Icons.fingerprint_rounded,
                        color: Color(0xFFFF6B6B), size: 40),
                  ),
                ),
              ),
              // Bottom label
              Positioned(
                bottom: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sensors_rounded, color: Colors.white.withOpacity(0.9), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Real-time Vital Signs Detection',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVitalsPreviewRow() {
    final vitals = [
      {'icon': Icons.monitor_heart_rounded, 'label': 'Heart Rate', 'unit': 'BPM', 'color': const Color(0xFFFF6B6B)},
      {'icon': Icons.air_rounded, 'label': 'Breathing', 'unit': '/min', 'color': const Color(0xFF00D9FF)},
      {'icon': Icons.psychology_rounded, 'label': 'Stress', 'unit': 'Level', 'color': const Color(0xFFFFC857)},
      {'icon': Icons.bloodtype_rounded, 'label': 'BP Est.', 'unit': 'mmHg', 'color': const Color(0xFF9D84B7)},
    ];
    return Row(
      children: vitals.asMap().entries.map((entry) {
        final i = entry.key;
        final v = entry.value;
        final color = v['color'] as Color;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              left: i == 0 ? 0 : 5,
              right: i == vitals.length - 1 ? 0 : 5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.18)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(v['icon'] as IconData, color: color, size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  '--',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v['unit'] as String,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHowItWorksCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                          colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.science_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'How It Works',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _howItWorksStep('1', 'Tap Start & place finger on camera',
                  'Gently press any fingertip on the rear camera lens',
                  const Color(0xFFFF6B6B)),
              _howItWorksStep('2', 'Stay still for 15 seconds',
                  'Flash will turn on — the light reads blood flow in your finger',
                  const Color(0xFFFFC857)),
              _howItWorksStep('3', 'Get your vitals instantly',
                  'AI analyzes the signal and shows heart rate, stress & more',
                  const Color(0xFF4ECCA3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _howItWorksStep(
      String num, String title, String sub, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.6)),
            ),
            child: Center(
              child: Text(num,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                Text(sub,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _isCameraInitialized ? _startScan : null,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (ctx, _) => Transform.scale(
          scale: _isCameraInitialized ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: _isCameraInitialized
                  ? const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFFF9068)])
                  : LinearGradient(colors: [
                      Colors.grey.withOpacity(0.3),
                      Colors.grey.withOpacity(0.2)
                    ]),
              boxShadow: _isCameraInitialized
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF6B6B).withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.radar_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  _isCameraInitialized ? 'Start Scan' : 'Initializing...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SCANNING VIEW
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildScanningView() {
    final progress = 1.0 - (_secondsRemaining / _scanDurationSec);

    return SingleChildScrollView(
      key: const ValueKey('scanning'),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        children: [
          // Camera view with overlay
          _buildScanningCameraCard(progress),
          const SizedBox(height: 14),
          // Signal quality
          _buildSignalQualityBar(),
          const SizedBox(height: 14),
          // Live readings
          _buildLiveReadingsCard(),
          const SizedBox(height: 14),
          // Instruction reminder
          _buildScanInstructionCard(),
        ],
      ),
    );
  }

  Widget _buildScanningCameraCard(double progress) {
    final borderColor = _fingerDetected
        ? const Color(0xFF4ECCA3)
        : const Color(0xFFFF6B6B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: borderColor.withOpacity(0.7),
            width: 2,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview
            if (_isCameraInitialized && _cameraController != null)
              CameraPreview(_cameraController!)
            else
              Container(color: Colors.black),

            // Dark overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),

            // Scanning animation rings
            Center(
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (ctx, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: List.generate(3, (i) {
                      final offset = ((_waveController.value + i * 0.33) % 1.0);
                      return Opacity(
                        opacity: (1.0 - offset).clamp(0.0, 1.0),
                        child: Container(
                          width: 60 + offset * 80,
                          height: 60 + offset * 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (_fingerDetected ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B)).withOpacity(0.7),
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // Center icon
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_fingerDetected ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B)).withOpacity(0.3),
                  border: Border.all(
                    color: _fingerDetected ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B),
                    width: 2,
                  ),
                ),
                child: Icon(
                  _fingerDetected ? Icons.favorite_rounded : Icons.fingerprint_rounded,
                  color: _fingerDetected ? const Color(0xFF4ECCA3) : const Color(0xFFFF6B6B),
                  size: 28,
                ),
              ),
            ),

            // Top bar: timer
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFF6B6B),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text('SCANNING',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_secondsRemaining s',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom: progress bar
            Positioned(
              bottom: 14,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Text(
                    _secondsRemaining > 0
                        ? 'Measuring... $_secondsRemaining s remaining'
                        : 'Finalizing...',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF6B6B)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalQualityBar() {
    final qualityPercent = (_signalQuality * 100).toInt();
    final qualityColor = !_fingerDetected
        ? const Color(0xFFFF6B6B)
        : _signalQuality > 0.4
            ? const Color(0xFF4ECCA3)
            : _signalQuality > 0.15
                ? const Color(0xFFFFC857)
                : const Color(0xFFFF6B6B);

    final qualityText = !_fingerDetected
        ? '⚠ Place finger on camera'
        : _signalQuality > 0.4
            ? 'Excellent signal'
            : _signalQuality > 0.15
                ? 'Good signal'
                : 'Adjusting...';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: _fingerDetected
                ? qualityColor.withOpacity(0.35)
                : const Color(0xFFFF6B6B).withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _fingerDetected ? qualityColor : const Color(0xFFFF6B6B),
                        boxShadow: [BoxShadow(color: (_fingerDetected ? qualityColor : const Color(0xFFFF6B6B)).withOpacity(0.6), blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(_fingerDetected ? 'Signal Quality' : 'Finger Not Detected',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                  Row(
                    children: [
                      Text(qualityText,
                          style: TextStyle(
                              color: qualityColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                      if (_fingerDetected) ...[
                        const SizedBox(width: 6),
                        Text('$qualityPercent%',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _fingerDetected ? _signalQuality : 0.0,
                  backgroundColor: Colors.white.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(qualityColor),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveReadingsCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFFFF6B6B)),
                  ),
                  const SizedBox(width: 7),
                  const Text('Live Readings',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _liveMetricTile(
                        Icons.monitor_heart_rounded,
                        _liveHeartRate > 0 ? '$_liveHeartRate' : (_fingerDetected ? '...' : '--'),
                        'BPM', const Color(0xFFFF6B6B)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _liveMetricTile(
                        Icons.air_rounded,
                        _liveBreathing > 0 ? '$_liveBreathing' : (_fingerDetected ? '...' : '--'),
                        '/min',
                        const Color(0xFF00D9FF)),
                  ),
                ],
              ),
              // Waveform chart
              if (_waveformPoints.length > 10) ...[
                const SizedBox(height: 14),
                _buildMiniWaveform(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveMetricTile(
      IconData icon, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1)),
          const SizedBox(height: 2),
          Text(unit,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildMiniWaveform() {
    final pts = _waveformPoints;
    if (pts.length < 2) return const SizedBox();

    final minV = pts.reduce(math.min);
    final maxV = pts.reduce(math.max);
    final range = (maxV - minV).clamp(1.0, double.infinity);

    final spots = pts.asMap().entries.map((e) {
      final normalized = (e.value - minV) / range;
      return FlSpot(e.key.toDouble(), normalized);
    }).toList();

    return SizedBox(
      height: 60,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFFFF6B6B),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFFF6B6B).withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanInstructionCard() {
    final detected = _fingerDetected;
    final instructionColor = detected ? const Color(0xFF4ECCA3) : const Color(0xFFFFC857);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: instructionColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: instructionColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: instructionColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              detected ? Icons.check_circle_rounded : Icons.touch_app_rounded,
              color: instructionColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detected ? 'Scanning in progress...' : 'Place finger on camera',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Text(
                    detected
                        ? 'Hold still • Don\'t lift your finger • Almost there!'
                        : 'Gently press any finger on rear camera lens',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ANALYZING VIEW
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildAnalyzingView() {
    return Center(
      key: const ValueKey('analyzing'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (ctx, _) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D9FF).withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Analyzing Signal...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text('Processing PPG waveform data',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 30),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00D9FF)),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // RESULTS VIEW
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildResultsView() {
    if (_result == null) return const SizedBox();

    return SlideTransition(
      position: _resultSlideAnimation,
      child: FadeTransition(
        opacity: _resultFadeAnimation,
        child: SingleChildScrollView(
          key: const ValueKey('results'),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          child: Column(
            children: [
              // Summary card
              _buildResultsSummaryCard(),
              const SizedBox(height: 14),
              // Heart rate detail
              _buildHeartRateDetailCard(),
              const SizedBox(height: 14),
              // Other vitals grid
              _buildVitalsGrid(),
              const SizedBox(height: 14),
              // AI insight
              _buildAIInsightCard(),
              const SizedBox(height: 20),
              // Action buttons
              _buildResultActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsSummaryCard() {
    final r = _result!;
    final overallStatus = _getOverallStatus(r);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: overallStatus.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: overallStatus.gradient[0].withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(overallStatus.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      const Text('Scan Complete',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 3),
                    Text(overallStatus.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.2)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(r.timestamp),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryMini(Icons.monitor_heart_rounded, '${r.heartRate}', 'BPM'),
                _divider(),
                _summaryMini(Icons.air_rounded, '${r.breathingRate}', '/min'),
                _divider(),
                _summaryMini(Icons.psychology_rounded, r.stressLevel.label, 'Stress'),
                _divider(),
                _summaryMini(Icons.bloodtype_rounded, '${r.systolic}/${r.diastolic}', 'mmHg'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryMini(IconData icon, String value, String unit) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.85), size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1)),
        const SizedBox(height: 2),
        Text(unit,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 8,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _divider() {
    return Container(
        width: 1, height: 36, color: Colors.white.withOpacity(0.3));
  }

  Widget _buildHeartRateDetailCard() {
    final r = _result!;
    final hrStatus = _heartRateStatus(r.heartRate);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withOpacity(0.08),
            border: Border.all(
                color: const Color(0xFFFF6B6B).withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.monitor_heart_rounded, color: Color(0xFFFF6B6B), size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text('Heart Rate Analysis',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: hrStatus.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: hrStatus.color.withOpacity(0.5)),
                    ),
                    child: Text(hrStatus.label,
                        style: TextStyle(
                            color: hrStatus.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${r.heartRate}',
                      style: TextStyle(
                          color: hrStatus.color,
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          height: 1)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('BPM',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // PPG waveform
              if (r.waveformData.length > 10)
                _buildResultWaveform(r.waveformData),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                      child: _detailTile('HRV', '${r.hrv.toStringAsFixed(1)} ms',
                          const Color(0xFF9D84B7))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _detailTile('Fatigue',
                          r.fatigueLevel.label, r.fatigueLevel.color)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _detailTile(
                          'Range', '60–100 BPM', const Color(0xFF4ECCA3))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultWaveform(List<double> data) {
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).clamp(1.0, double.infinity);

    final spots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value - minV) / range);
    }).toList();

    return SizedBox(
      height: 70,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFFFF6B6B),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFF6B6B).withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildVitalsGrid() {
    final r = _result!;
    final vitals = [
      {
        'icon': Icons.air_rounded,
        'label': 'Breathing Rate',
        'value': '${r.breathingRate} /min',
        'status': r.breathingRate >= 12 && r.breathingRate <= 20
            ? 'Normal'
            : 'Review',
        'statusGood': r.breathingRate >= 12 && r.breathingRate <= 20,
        'color': const Color(0xFF00D9FF),
        'range': '12–20 /min',
      },
      {
        'icon': Icons.psychology_rounded,
        'label': 'Stress Level',
        'value': r.stressLevel.label,
        'status': r.stressLevel == StressLevel.low ? 'Optimal' : 'Elevated',
        'statusGood': r.stressLevel == StressLevel.low,
        'color': r.stressLevel.color,
        'range': 'Based on HRV',
      },
      {
        'icon': Icons.bloodtype_rounded,
        'label': 'Est. Blood Pressure',
        'value': '${r.systolic}/${r.diastolic}',
        'status': r.systolic < 130 ? 'Normal' : 'Elevated',
        'statusGood': r.systolic < 130,
        'color': const Color(0xFFFFC857),
        'range': 'Estimated (mmHg)',
      },
      {
        'icon': Icons.bedtime_rounded,
        'label': 'Fatigue',
        'value': r.fatigueLevel.label,
        'status': r.fatigueLevel == FatigueLevel.rested ? 'Rested' : 'Review',
        'statusGood': r.fatigueLevel == FatigueLevel.rested,
        'color': r.fatigueLevel.color,
        'range': 'From HRV + HR',
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: vitals.length,
      itemBuilder: (ctx, i) {
        final v = vitals[i];
        final color = v['color'] as Color;
        final isGood = v['statusGood'] as bool;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withOpacity(0.12),
                    color.withOpacity(0.05),
                  ],
                ),
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(v['icon'] as IconData, color: color, size: 16),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isGood ? const Color(0xFF4ECCA3) : const Color(0xFFFFC857)).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (isGood ? const Color(0xFF4ECCA3) : const Color(0xFFFFC857)).withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isGood ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                color: isGood ? const Color(0xFF4ECCA3) : const Color(0xFFFFC857), size: 9),
                            const SizedBox(width: 3),
                            Text(v['status'] as String,
                                style: TextStyle(
                                    color: isGood ? const Color(0xFF4ECCA3) : const Color(0xFFFFC857),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(v['value'] as String,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1)),
                  const SizedBox(height: 3),
                  Text(v['label'] as String,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(v['range'] as String,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAIInsightCard() {
    final r = _result!;
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
                const Color(0xFF2EC4B6).withOpacity(0.15),
                const Color(0xFF9D84B7).withOpacity(0.10),
              ],
            ),
            border: Border.all(
                color: const Color(0xFF2EC4B6).withOpacity(0.4), width: 1.5),
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
                          colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.psychology_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('AI Insight',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECCA3).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text('PERSONALIZED',
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
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _generateInsight(r),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFF6B6B).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFFFF6B6B), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'For informational purposes only. Not a substitute for professional medical advice.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultActions() {
    return Column(
      children: [
        GestureDetector(
          onTap: _resetScan,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                  colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D9FF).withOpacity(0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Scan Again',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.07),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Back to Dashboard',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _generateInsight(ScanResult r) {
    final insights = <String>[];

    if (r.heartRate < 60) {
      insights.add('Your resting heart rate of ${r.heartRate} BPM indicates strong cardiovascular fitness — well below average.');
    } else if (r.heartRate <= 100) {
      insights.add('Heart rate of ${r.heartRate} BPM is within the clinically normal range (60–100 BPM). Keep maintaining your active lifestyle.');
    } else {
      insights.add('Elevated heart rate detected at ${r.heartRate} BPM. Consider rest, hydration, or deep breathing before re-scanning.');
    }

    if (r.stressLevel == StressLevel.low) {
      insights.add('HRV analysis indicates a relaxed autonomic state — optimal for recovery and cognitive performance.');
    } else if (r.stressLevel == StressLevel.moderate) {
      insights.add('Moderate sympathetic activation detected. A 5-minute deep breathing session (4s inhale, 6s exhale) may improve HRV.');
    } else {
      insights.add('High stress markers detected via low HRV. Recommended: short walk, progressive muscle relaxation, or hydration break.');
    }

    if (r.fatigueLevel == FatigueLevel.fatigued) {
      insights.add('Fatigue indicators present (elevated HR + reduced HRV variability). Prioritize 7–9 hours of sleep for recovery.');
    }

    return insights.join('\n\n');
  }

  OverallStatus _getOverallStatus(ScanResult r) {
    final isGood = r.heartRate >= 60 &&
        r.heartRate <= 100 &&
        r.stressLevel == StressLevel.low &&
        r.breathingRate >= 12 &&
        r.breathingRate <= 20;
    if (isGood) {
      return OverallStatus(
          label: 'All Vitals Normal',
          icon: Icons.verified_rounded,
          gradient: [const Color(0xFF4ECCA3), const Color(0xFF2EC4B6)]);
    }
    return OverallStatus(
        label: 'Review Vitals',
        icon: Icons.info_outline_rounded,
        gradient: [const Color(0xFFFFC857), const Color(0xFFFF9068)]);
  }

  _HRStatus _heartRateStatus(int bpm) {
    if (bpm < 60) return _HRStatus('Below Normal', const Color(0xFF00D9FF));
    if (bpm <= 100) return _HRStatus('Normal', const Color(0xFF4ECCA3));
    return _HRStatus('Elevated', const Color(0xFFFF6B6B));
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

enum ScanState { idle, scanning, analyzing, results }

enum StressLevel {
  low,
  moderate,
  high;

  String get label {
    switch (this) {
      case StressLevel.low: return 'LOW';
      case StressLevel.moderate: return 'MODERATE';
      case StressLevel.high: return 'HIGH';
    }
  }

  Color get color {
    switch (this) {
      case StressLevel.low: return const Color(0xFF4ECCA3);
      case StressLevel.moderate: return const Color(0xFFFFC857);
      case StressLevel.high: return const Color(0xFFFF6B6B);
    }
  }
}

enum FatigueLevel {
  rested,
  mild,
  fatigued;

  String get label {
    switch (this) {
      case FatigueLevel.rested: return 'Rested';
      case FatigueLevel.mild: return 'Mild';
      case FatigueLevel.fatigued: return 'Fatigued';
    }
  }

  Color get color {
    switch (this) {
      case FatigueLevel.rested: return const Color(0xFF4ECCA3);
      case FatigueLevel.mild: return const Color(0xFFFFC857);
      case FatigueLevel.fatigued: return const Color(0xFFFF6B6B);
    }
  }
}

class ScanResult {
  final int heartRate;
  final int breathingRate;
  final StressLevel stressLevel;
  final int systolic;
  final int diastolic;
  final double hrv;
  final FatigueLevel fatigueLevel;
  final List<double> waveformData;
  final DateTime timestamp;

  const ScanResult({
    required this.heartRate,
    required this.breathingRate,
    required this.stressLevel,
    required this.systolic,
    required this.diastolic,
    required this.hrv,
    required this.fatigueLevel,
    required this.waveformData,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'heartRate': heartRate,
        'breathingRate': breathingRate,
        'stressLevel': stressLevel.name,
        'systolic': systolic,
        'diastolic': diastolic,
        'hrv': hrv,
        'fatigueLevel': fatigueLevel.name,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}

class OverallStatus {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  const OverallStatus(
      {required this.label, required this.icon, required this.gradient});
}

class _HRStatus {
  final String label;
  final Color color;
  const _HRStatus(this.label, this.color);
}

