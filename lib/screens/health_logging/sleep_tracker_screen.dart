import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '/services/auth_service.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({Key? key}) : super(key: key);
  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen>
    with TickerProviderStateMixin {

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _cardCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _cardAnims;

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _noteCtrl = TextEditingController();

  bool isLoading = false;
  bool _loadingHistory = true;
  bool _alreadyLogged = false;

  TimeOfDay bedTime = const TimeOfDay(hour: 22, minute: 30);
  TimeOfDay wakeUpTime = const TimeOfDay(hour: 6, minute: 30);
  int sleepQuality = 4;
  double sleepDuration = 8.0;
  List<String> selectedFactors = [];
  List<Map<String, dynamic>> weekHistory = [];

  static const Color _accent = Color(0xFF9D84B7);
  static const Color _accentDark = Color(0xFF7B2CBF);

  final List<Map<String, dynamic>> qualities = [
    {'value': 1, 'emoji': '😫', 'icon': Icons.sentiment_very_dissatisfied_rounded, 'label': 'Terrible', 'sub': 'Very restless night',
     'color': Color(0xFFFF6B6B), 'colors': [Color(0xFFFF6B6B), Color(0xFFEE5A6F)]},
    {'value': 2, 'emoji': '😴', 'icon': Icons.sentiment_dissatisfied_rounded, 'label': 'Poor', 'sub': 'Kept waking up',
     'color': Color(0xFFFF9068), 'colors': [Color(0xFFFF9068), Color(0xFFFF6B6B)]},
    {'value': 3, 'emoji': '😐', 'icon': Icons.sentiment_neutral_rounded, 'label': 'Okay', 'sub': 'Average sleep',
     'color': Color(0xFFFFC857), 'colors': [Color(0xFFFFC857), Color(0xFFFFD93D)]},
    {'value': 4, 'emoji': '😌', 'icon': Icons.sentiment_satisfied_rounded, 'label': 'Good', 'sub': 'Rested well',
     'color': Color(0xFF9D84B7), 'colors': [Color(0xFF9D84B7), Color(0xFF7B2CBF)]},
    {'value': 5, 'emoji': '😊', 'icon': Icons.sentiment_very_satisfied_rounded, 'label': 'Excellent', 'sub': 'Slept like a baby',
     'color': Color(0xFF4ECCA3), 'colors': [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]},
  ];

  final List<Map<String, dynamic>> factors = [
    {'label': 'Caffeine',    'icon': Icons.coffee_rounded},
    {'label': 'Screen Time', 'icon': Icons.phone_android_rounded},
    {'label': 'Stress',      'icon': Icons.psychology_rounded},
    {'label': 'Exercise',    'icon': Icons.fitness_center_rounded},
    {'label': 'Noise',       'icon': Icons.volume_up_rounded},
    {'label': 'Comfort',     'icon': Icons.bed_rounded},
    {'label': 'Alcohol',     'icon': Icons.local_bar_rounded},
    {'label': 'Late Meal',   'icon': Icons.restaurant_rounded},
    {'label': 'Temperature', 'icon': Icons.thermostat_rounded},
    {'label': 'Medication',  'icon': Icons.medication_rounded},
  ];

  Map<String, dynamic> get _currentQ =>
      qualities.firstWhere((q) => q['value'] == sleepQuality);

  @override
  void initState() {
    super.initState();
    _initAnims();
    _loadHistory();
    _calcDuration();
  }

  void _initAnims() {
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _cardAnims = List.generate(5, (i) {
      final s = (i * 0.12).clamp(0.0, 1.0);
      final e = (s + 0.5).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _cardCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });
    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _cardCtrl.forward();
    });
  }

  Future<void> _loadHistory() async {
    try {
      final user = _authService.currentUser;
      if (user == null) { setState(() => _loadingHistory = false); return; }
      final now = DateTime.now();
      final List<Map<String, dynamic>> hist = [];
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        final doc = await _firestore.collection('users').doc(user.uid)
            .collection('sleep_logs').doc(ds).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          hist.add({'date': ds, 'hours': (data['hours'] as num?)?.toDouble() ?? 0.0,
                    'quality': (data['quality'] as num?)?.toInt() ?? 0});
          if (i == 0) _alreadyLogged = true;
        } else {
          hist.add({'date': ds, 'hours': 0.0, 'quality': 0});
        }
      }
      if (mounted) setState(() { weekHistory = hist; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _saveSleepData() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) { _snack('Please log in first', error: true); return; }
      final now = DateTime.now();
      final ds = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      final q = _currentQ;
      await _firestore.collection('users').doc(user.uid)
          .collection('sleep_logs').doc(ds).set({
        'bedTime': '${bedTime.hour.toString().padLeft(2,'0')}:${bedTime.minute.toString().padLeft(2,'0')}',
        'wakeUpTime': '${wakeUpTime.hour.toString().padLeft(2,'0')}:${wakeUpTime.minute.toString().padLeft(2,'0')}',
        'hours': sleepDuration, 'quality': sleepQuality,
        'qualityLabel': q['label'], 'qualityEmoji': q['emoji'],
        'note': _noteCtrl.text.trim(), 'factors': selectedFactors,
        'timestamp': FieldValue.serverTimestamp(), 'date': ds,
        'created_at': now.millisecondsSinceEpoch,
      });
      await _firestore.collection('users').doc(user.uid)
          .collection('daily_summary').doc(ds).set({
        'sleep': {'duration': sleepDuration, 'quality': sleepQuality, 'hours': sleepDuration},
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      HapticFeedback.heavyImpact();
      _snack('Sleep logged successfully!');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: error ? const Color(0xFFFF6B6B) : _accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _calcDuration() {
    final bm = bedTime.hour * 60 + bedTime.minute;
    final wm = wakeUpTime.hour * 60 + wakeUpTime.minute;
    final diff = wm >= bm ? wm - bm : (1440 - bm) + wm;
    setState(() => sleepDuration = diff / 60.0);
  }

  Future<void> _pickTime(bool isBed) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isBed ? bedTime : wakeUpTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: _accent, surface: Color(0xFF1A1F3A))),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => isBed ? bedTime = picked : wakeUpTime = picked);
      _calcDuration();
      HapticFeedback.selectionClick();
    }
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')} $p';
  }

  String _fmtDur(double h) => '${h.floor()}h ${((h - h.floor()) * 60).round()}m';

  String get _sleepTip {
    if (sleepDuration < 6) return 'Too little sleep — aim for 7–9h';
    if (sleepDuration > 9) return 'Slightly long — 7–9h is optimal';
    return 'Great duration! Well done';
  }

  @override
  void dispose() {
    _entryCtrl.dispose(); _pulseCtrl.dispose(); _cardCtrl.dispose();
    _noteCtrl.dispose(); super.dispose();
  }

  Widget _animCard(int i, Widget child) {
    final idx = i.clamp(0, _cardAnims.length - 1);
    return AnimatedBuilder(
      animation: _cardAnims[idx],
      builder: (_, __) => Opacity(
        opacity: _cardAnims[idx].value,
        child: Transform.translate(
            offset: Offset(0, (1 - _cardAnims[idx].value) * 22), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(children: [
        _blobs(),
        SafeArea(child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(position: _slideAnim,
            child: Column(children: [
              _header(),
              Expanded(child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    sliver: SliverList(delegate: SliverChildListDelegate([
                      _mainCard(), const SizedBox(height: 14),
                      _scheduleCard(), const SizedBox(height: 14),
                      _weekHistoryCard(), const SizedBox(height: 14),
                      _factorsCard(), const SizedBox(height: 14),
                      _noteCard(), const SizedBox(height: 20),
                      _saveButton(), const SizedBox(height: 30),
                    ])),
                  )],
                ),
              )),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _blobs() => Stack(children: [
    Positioned(top: -60, right: -40, child: Container(width: 200, height: 200,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: _accent.withOpacity(0.09)))),
    Positioned(bottom: 120, left: -60, child: Container(width: 180, height: 180,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: _accentDark.withOpacity(0.07)))),
  ]);

  Widget _header() {
    final q = _currentQ;
    final color = q['color'] as Color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(children: [
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
          child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.15))),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sleep Tracker', style: TextStyle(fontSize: 21,
              fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2)),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 400),
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            child: Text(q['sub'] as String),
          ),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_accent, _accentDark]),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [BoxShadow(color: _accent.withOpacity(0.35),
                blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.nightlight_round, color: Colors.white, size: 13),
            SizedBox(width: 4),
            Text('Sleep', style: TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.w900)),
          ]),
        ),
      ]),
    );
  }

  Widget _mainCard() {
    final q = _currentQ;
    final color = q['color'] as Color;
    final colors = q['colors'] as List<Color>;
    return _animCard(0, ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [color.withOpacity(0.16), color.withOpacity(0.06)]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: color.withOpacity(0.18),
                blurRadius: 28, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            Row(children: [
              AnimatedBuilder(animation: _pulseAnim,
                builder: (_, __) => Transform.scale(scale: _pulseAnim.value,
                  child: Container(width: 90, height: 90,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: LinearGradient(colors: colors,
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.45),
                          blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: Center(child: Icon(q['icon'] as IconData,
                        color: Colors.white, size: 44)),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Tonight's Sleep",
                    style: TextStyle(color: Colors.white.withOpacity(0.55),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(_fmtDur(sleepDuration),
                      key: ValueKey(sleepDuration.toStringAsFixed(1)),
                      style: TextStyle(color: color, fontSize: 28,
                          fontWeight: FontWeight.w900, height: 1)),
                ),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (sleepDuration / 10).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(_sleepTip, style: TextStyle(color: color.withOpacity(0.85),
                    fontSize: 10, fontWeight: FontWeight.w600)),
                if (_alreadyLogged) ...[
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Already logged today — updating',
                        style: TextStyle(color: color, fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ])),
            ]),
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: qualities.map((qItem) {
                final sel = qItem['value'] == sleepQuality;
                final qc = qItem['color'] as Color;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => sleepQuality = qItem['value'] as int);
                  },
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: sel ? 54 : 42, height: sel ? 54 : 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: sel ? LinearGradient(
                            colors: qItem['colors'] as List<Color>,
                            begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                        color: sel ? null : Colors.white.withOpacity(0.08),
                        border: Border.all(
                            color: sel ? qc : Colors.white.withOpacity(0.18),
                            width: sel ? 2.5 : 1.2),
                        boxShadow: sel ? [BoxShadow(color: qc.withOpacity(0.45),
                            blurRadius: 14, offset: const Offset(0, 5))] : [],
                      ),
                      child: Center(child: Icon(qItem['icon'] as IconData,
                          color: sel ? Colors.white : Colors.white.withOpacity(0.45),
                          size: sel ? 26 : 19)),
                    ),
                    const SizedBox(height: 5),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                          color: sel ? qc : Colors.white.withOpacity(0.4),
                          fontSize: sel ? 10 : 9,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500),
                      child: Text(qItem['label'] as String),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ]),
        ),
      ),
    ));
  }

  Widget _scheduleCard() => _animCard(1, ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white.withOpacity(0.09),
              Colors.white.withOpacity(0.04)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            const Text('Sleep Schedule', style: TextStyle(color: Colors.white,
                fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _accent.withOpacity(0.3))),
              child: Text(_fmtDur(sleepDuration), style: const TextStyle(
                  color: _accent, fontSize: 10, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _timeCard('Bedtime', bedTime,
                Icons.bedtime_rounded, _accent, () => _pickTime(true))),
            const SizedBox(width: 10),
            Expanded(child: _timeCard('Wake Up', wakeUpTime,
                Icons.wb_sunny_rounded, const Color(0xFFFFC857), () => _pickTime(false))),
          ]),
        ]),
      ),
    ),
  ));

  Widget _timeCard(String title, TimeOfDay t, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.35), width: 1.2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Text(title, style: TextStyle(color: color, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(_fmtTime(t), style: const TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('Tap to change', style: TextStyle(
                color: Colors.white.withOpacity(0.3), fontSize: 9)),
          ]),
        ),
      );

  Widget _weekHistoryCard() {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    return _animCard(2, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_accent, _accentDark]),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16)),
              const SizedBox(width: 10),
              const Text('This Week', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF4ECCA3).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.3))),
                child: const Text('REAL DATA', style: TextStyle(color: Color(0xFF4ECCA3),
                    fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.6))),
            ]),
            const SizedBox(height: 16),
            if (_loadingHistory)
              const Center(child: Padding(padding: EdgeInsets.all(10),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent)))))
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
                  final entry = weekHistory.length > i ? weekHistory[i] : null;
                  final hours = (entry?['hours'] as num?)?.toDouble() ?? 0.0;
                  final quality = (entry?['quality'] as num?)?.toInt() ?? 0;
                  final hasData = hours > 0;
                  final entryDate = entry?['date'] as String? ?? '';
                  final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
                  final isToday = entryDate == todayStr;
                  final dayIdx = now.subtract(Duration(days: 6 - i)).weekday - 1;
                  Color barColor = Colors.white.withOpacity(0.12);
                  if (hasData && quality > 0) {
                    barColor = (qualities.firstWhere((q) => q['value'] == quality,
                        orElse: () => qualities[2])['color'] as Color);
                  }
                  return Column(children: [
                    Container(width: 32, height: 52,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: isToday ? Border.all(color: _accent.withOpacity(0.5),
                              width: 1.5) : null),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          width: 32,
                          height: hasData ? (hours / 10 * 52).clamp(8.0, 52.0) : 0,
                          decoration: BoxDecoration(
                            gradient: hasData ? LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [barColor.withOpacity(0.9), barColor.withOpacity(0.4)]) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        if (hasData) Positioned(top: 3,
                            child: Icon(hours < 5 ? Icons.sentiment_very_dissatisfied_rounded : hours < 7 ? Icons.sentiment_dissatisfied_rounded : Icons.sentiment_very_satisfied_rounded,
                                color: Colors.white.withOpacity(0.8), size: 12)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(dayLabels[dayIdx], style: TextStyle(
                        color: isToday ? _accent : Colors.white.withOpacity(0.4),
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.w900 : FontWeight.w600)),
                    if (hasData) Text('${hours.toStringAsFixed(1)}h',
                        style: TextStyle(color: Colors.white.withOpacity(0.3),
                            fontSize: 8, fontWeight: FontWeight.w500)),
                  ]);
                }),
              ),
            if (!_loadingHistory) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(Icons.calendar_today_rounded, '${weekHistory.where((e) => (e['hours'] as double? ?? 0) > 0).length}/7', 'Logged'),
                _vDiv(),
                _stat(Icons.timer_rounded,
                    weekHistory.where((e) => (e['hours'] as double? ?? 0) > 0).isEmpty ? '--'
                        : '${(weekHistory.where((e) => (e['hours'] as double? ?? 0) > 0).map((e) => e['hours'] as double).reduce((a, b) => a + b) / weekHistory.where((e) => (e['hours'] as double? ?? 0) > 0).length).toStringAsFixed(1)}h',
                    'Avg'),
                _vDiv(),
                _stat(Icons.nightlight_round, _fmtDur(sleepDuration), 'Tonight'),
              ]),
            ],
          ]),
        ),
      ),
    ));
  }

  Widget _stat(IconData icon, String v, String l) => Column(children: [
    Icon(icon, color: _accent.withOpacity(0.7), size: 16),
    const SizedBox(height: 3),
    Text(v, style: const TextStyle(color: Colors.white, fontSize: 13,
        fontWeight: FontWeight.w900, height: 1)),
    Text(l, style: TextStyle(color: Colors.white.withOpacity(0.4),
        fontSize: 9, fontWeight: FontWeight.w600)),
  ]);

  Widget _vDiv() => Container(width: 1, height: 34, color: Colors.white.withOpacity(0.1));

  Widget _factorsCard() {
    final color = _currentQ['color'] as Color;
    return _animCard(3, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                    borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 16)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sleep Factors', style: TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('What affected your sleep?', style: TextStyle(
                      color: Color(0xFF00D9FF), fontSize: 10, fontWeight: FontWeight.w600)),
                ])),
              if (selectedFactors.isNotEmpty)
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('${selectedFactors.length} selected',
                      style: const TextStyle(color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8,
              children: factors.map((f) {
                final sel = selectedFactors.contains(f['label']);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (sel) selectedFactors.remove(f['label']);
                      else selectedFactors.add(f['label'] as String);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: sel ? LinearGradient(
                          colors: [color, color.withOpacity(0.7)]) : null,
                      color: sel ? null : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? color.withOpacity(0.6) : Colors.white.withOpacity(0.15),
                          width: sel ? 1.5 : 1),
                      boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.3),
                          blurRadius: 8, offset: const Offset(0, 3))] : [],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(f['icon'] as IconData,
                          color: sel ? Colors.white : _accent, size: 14),
                      const SizedBox(width: 6),
                      Text(f['label'] as String, style: TextStyle(
                          color: sel ? Colors.white : Colors.white.withOpacity(0.75),
                          fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ]),
        ),
      ),
    ));
  }

  Widget _noteCard() => _animCard(4, ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white.withOpacity(0.09),
              Colors.white.withOpacity(0.04)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sleep Notes', style: TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w800)),
                Text('Any dreams or thoughts?', style: TextStyle(
                    color: _accent, fontSize: 10, fontWeight: FontWeight.w600)),
              ])),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _noteCtrl, maxLines: 3, maxLength: 300,
            style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500, height: 1.5),
            decoration: InputDecoration(
              hintText: 'How did you sleep? Any dreams?',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              filled: true, fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _accent, width: 1.8)),
              contentPadding: const EdgeInsets.all(14),
              counterStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
            ),
          ),
        ]),
      ),
    ),
  ));

  Widget _saveButton() {
    final q = _currentQ;
    final colors = q['colors'] as List<Color>;
    final color = q['color'] as Color;
    return GestureDetector(
      onTap: isLoading ? null : _saveSleepData,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: color.withOpacity(0.45),
              blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: isLoading
            ? const Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white))))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(q['icon'] as IconData, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(_alreadyLogged ? 'Update Sleep Log' : 'Save Sleep Log',
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w900, letterSpacing: 0.3)),
              ]),
      ),
    );
  }
}

