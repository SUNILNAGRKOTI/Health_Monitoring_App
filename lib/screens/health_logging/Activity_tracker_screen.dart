import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';

class ActivityTrackerScreen extends StatefulWidget {
  const ActivityTrackerScreen({super.key});
  @override
  State<ActivityTrackerScreen> createState() => _ActivityTrackerScreenState();
}

class _ActivityTrackerScreenState extends State<ActivityTrackerScreen>
    with TickerProviderStateMixin {

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _cardCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _cardAnims;

  String selectedActivity = 'Walking';
  double duration = 30.0;
  double intensity = 3.0;
  int steps = 0;
  bool isLoading = false;
  bool _loadingHistory = true;
  List<Map<String, dynamic>> weekHistory = [];

  final List<Map<String, dynamic>> activities = [
    {'name': 'Walking',  'emoji': '🚶', 'icon': Icons.directions_walk_rounded,  'color': Color(0xFF4ECCA3), 'colors': [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]},
    {'name': 'Running',  'emoji': '🏃', 'icon': Icons.directions_run_rounded,   'color': Color(0xFFFF9F1C), 'colors': [Color(0xFFFF9F1C), Color(0xFFFF6B6B)]},
    {'name': 'Cycling',  'emoji': '🚴', 'icon': Icons.directions_bike_rounded,  'color': Color(0xFF00D9FF), 'colors': [Color(0xFF00D9FF), Color(0xFF0EA5E9)]},
    {'name': 'Swimming', 'emoji': '🏊', 'icon': Icons.pool_rounded,             'color': Color(0xFF4FC3F7), 'colors': [Color(0xFF4FC3F7), Color(0xFF0288D1)]},
    {'name': 'Gym',      'emoji': '💪', 'icon': Icons.fitness_center_rounded,   'color': Color(0xFFFF6B6B), 'colors': [Color(0xFFFF6B6B), Color(0xFFEE5A6F)]},
    {'name': 'Yoga',     'emoji': '🧘', 'icon': Icons.self_improvement_rounded, 'color': Color(0xFF9D84B7), 'colors': [Color(0xFF9D84B7), Color(0xFF7B2CBF)]},
    {'name': 'Dancing',  'emoji': '💃', 'icon': Icons.music_note_rounded,       'color': Color(0xFFFF69B4), 'colors': [Color(0xFFFF69B4), Color(0xFFE91E63)]},
    {'name': 'Sports',   'emoji': '⚽', 'icon': Icons.sports_soccer_rounded,   'color': Color(0xFF6BCF7F), 'colors': [Color(0xFF6BCF7F), Color(0xFF4CAF50)]},
  ];

  final List<Map<String, dynamic>> intensityLevels = [
    {'label': 'Light',    'desc': 'Easy, minimal effort',     'icon': Icons.spa_rounded,                  'icolor': Color(0xFF4ECCA3)},
    {'label': 'Moderate', 'desc': 'Comfortable challenge',    'icon': Icons.trending_up_rounded,          'icolor': Color(0xFFFFC857)},
    {'label': 'Vigorous', 'desc': 'Hard, pushing limits',     'icon': Icons.bolt_rounded,                 'icolor': Color(0xFFFF9F1C)},
    {'label': 'Max',      'desc': 'All-out, very intense',    'icon': Icons.whatshot_rounded,              'icolor': Color(0xFFFF6B6B)},
    {'label': 'Elite',    'desc': 'Extreme performance',      'icon': Icons.local_fire_department_rounded, 'icolor': Color(0xFFE91E63)},
  ];

  Map<String, dynamic> get _currentActivity =>
      activities.firstWhere((a) => a['name'] == selectedActivity);

  Color get _color => _currentActivity['color'] as Color;
  List<Color> get _colors => _currentActivity['colors'] as List<Color>;

  int get _estimatedCalories {
    final base = {'Walking': 4, 'Running': 10, 'Cycling': 7, 'Swimming': 9,
                  'Gym': 8, 'Yoga': 3, 'Dancing': 6, 'Sports': 8};
    final met = base[selectedActivity] ?? 6;
    return (met * duration * intensity / 3).round();
  }

  @override
  void initState() {
    super.initState();
    _initAnims();
    _loadHistory();
  }

  void _initAnims() {
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _cardAnims = List.generate(4, (i) {
      final s = (i * 0.15).clamp(0.0, 1.0);
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { setState(() => _loadingHistory = false); return; }
      final now = DateTime.now();
      final List<Map<String, dynamic>> hist = [];
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final ds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid)
            .collection('activity_logs').doc(ds).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          hist.add({'date': ds, 'duration': (data['duration'] as num?)?.toInt() ?? 0,
                    'activity': data['activity'] ?? '', 'steps': (data['steps'] as num?)?.toInt() ?? 0});
        } else {
          hist.add({'date': ds, 'duration': 0, 'activity': '', 'steps': 0});
        }
      }
      if (mounted) setState(() { weekHistory = hist; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _logActivity() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { _snack('Please log in first', error: true); return; }
      final now = DateTime.now();
      final ds = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('activity_logs').doc(ds).set({
        'activity': selectedActivity, 'duration': duration.toInt(),
        'steps': steps, 'intensity': intensity.toInt(),
        'estimatedCalories': _estimatedCalories,
        'emoji': _currentActivity['emoji'],
        'timestamp': FieldValue.serverTimestamp(), 'date': ds,
        'created_at': now.millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('daily_summary').doc(ds).set({
        'activity': {'duration': duration.toInt(), 'type': selectedActivity,
                     'steps': steps, 'calories': _estimatedCalories},
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      HapticFeedback.heavyImpact();
      _snack('Activity logged! Great work 💪');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Failed to log: $e', error: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: error ? const Color(0xFFFF6B6B) : _color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  void dispose() {
    _entryCtrl.dispose(); _pulseCtrl.dispose(); _cardCtrl.dispose();
    super.dispose();
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

  // ═══════════════════════════════════════════════════════════════════════
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
              Expanded(child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverList(delegate: SliverChildListDelegate([
                    _heroCard(),       const SizedBox(height: 14),
                    _activityGrid(),   const SizedBox(height: 14),
                    _detailsCard(),    const SizedBox(height: 14),
                    _weekHistoryCard(), const SizedBox(height: 20),
                    _logButton(),      const SizedBox(height: 30),
                  ])),
                )],
              )),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _blobs() => Stack(children: [
    Positioned(top: -60, right: -40, child: AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: 200, height: 200,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: _color.withOpacity(0.09)),
    )),
    Positioned(bottom: 120, left: -60, child: Container(width: 180, height: 180,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: const Color(0xFF7B2CBF).withOpacity(0.07)))),
  ]);

  Widget _header() => Padding(
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
        const Text('Activity Tracker', style: TextStyle(fontSize: 21,
            fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2)),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 400),
          style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w600),
          child: Text('Log your ${selectedActivity.toLowerCase()} session'),
        ),
      ])),
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _colors),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [BoxShadow(color: _color.withOpacity(0.35),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_currentActivity['icon'] as IconData, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text('${duration.toInt()}min', style: const TextStyle(color: Colors.white,
              fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
      ),
    ]),
  );

  // ── Hero card ──────────────────────────────────────────────────────────
  Widget _heroCard() => _animCard(0, ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_color.withOpacity(0.16), _color.withOpacity(0.06)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _color.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: _color.withOpacity(0.18),
              blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          AnimatedBuilder(animation: _pulseAnim,
            builder: (_, __) => Transform.scale(scale: _pulseAnim.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 90, height: 90,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: _colors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: _color.withOpacity(0.45),
                      blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Center(child: Icon(_currentActivity['icon'] as IconData,
                    color: Colors.white, size: 44)),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Activity', style: TextStyle(color: Colors.white.withOpacity(0.55),
                fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(selectedActivity,
                  key: ValueKey(selectedActivity),
                  style: TextStyle(color: _color, fontSize: 26,
                      fontWeight: FontWeight.w900, height: 1)),
            ),
            const SizedBox(height: 10),
            // Stats row
            Row(children: [
              _heroStat(Icons.timer_rounded, '${duration.toInt()}m', 'Duration'),
              const SizedBox(width: 14),
              _heroStat(Icons.local_fire_department_rounded,
                  '$_estimatedCalories', 'Calories'),
              if (selectedActivity == 'Walking' || selectedActivity == 'Running') ...[
                const SizedBox(width: 14),
                _heroStat(Icons.directions_walk_rounded, '$steps', 'Steps'),
              ],
            ]),
          ])),
        ]),
      ),
    ),
  ));

  Widget _heroStat(IconData icon, String val, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(icon, color: _color, size: 12),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45),
            fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
      Text(val, style: TextStyle(color: _color, fontSize: 16,
          fontWeight: FontWeight.w900, height: 1.1)),
    ],
  );

  // ── Activity grid ──────────────────────────────────────────────────────
  Widget _activityGrid() => _animCard(1, ClipRRect(
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
                  gradient: LinearGradient(colors: _colors),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.sports_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Choose Activity', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800)),
              Text('Select your workout type', style: TextStyle(
                  color: Color(0xFF00D9FF), fontSize: 10, fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, childAspectRatio: 0.85,
              crossAxisSpacing: 8, mainAxisSpacing: 8,
            ),
            itemCount: activities.length,
            itemBuilder: (_, i) {
              final a = activities[i];
              final sel = a['name'] == selectedActivity;
              final ac = a['color'] as Color;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => selectedActivity = a['name'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  decoration: BoxDecoration(
                    gradient: sel ? LinearGradient(
                        colors: a['colors'] as List<Color>,
                        begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    color: sel ? null : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: sel ? ac : Colors.white.withOpacity(0.15),
                        width: sel ? 1.8 : 1),
                    boxShadow: sel ? [BoxShadow(color: ac.withOpacity(0.4),
                        blurRadius: 12, offset: const Offset(0, 5))] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(a['icon'] as IconData,
                        color: sel ? Colors.white : Colors.white.withOpacity(0.45),
                        size: sel ? 26 : 22),
                    const SizedBox(height: 4),
                    Text(a['name'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: sel ? Colors.white : Colors.white.withOpacity(0.55),
                            fontSize: 9, fontWeight: sel ? FontWeight.w900 : FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
        ]),
      ),
    ),
  ));

  // ── Details card ───────────────────────────────────────────────────────
  Widget _detailsCard() => _animCard(2, ClipRRect(
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
                  gradient: LinearGradient(colors: _colors),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
            const Text('Session Details', style: TextStyle(color: Colors.white,
                fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 18),

          // Duration slider
          _sliderSection(
            label: 'Duration',
            value: duration,
            min: 5, max: 120, divisions: 23,
            displayVal: '${duration.toInt()} min',
            icon: Icons.timer_rounded,
            onChanged: (v) => setState(() => duration = v),
          ),
          const SizedBox(height: 18),

          // Intensity picker
          Row(children: [
            Icon(Icons.local_fire_department_rounded, color: _color, size: 16),
            const SizedBox(width: 8),
            Text('Intensity', style: TextStyle(color: Colors.white.withOpacity(0.7),
                fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w900),
              child: Text(intensityLevels[(intensity - 1).toInt().clamp(0, 4)]['label'] as String),
            ),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final sel = (intensity - 1).toInt() == i;
              final lvl = intensityLevels[i];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => intensity = (i + 1).toDouble());
                },
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: sel ? 48 : 38, height: sel ? 48 : 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: sel ? LinearGradient(colors: _colors,
                          begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                      color: sel ? null : Colors.white.withOpacity(0.07),
                      border: Border.all(
                          color: sel ? _color : Colors.white.withOpacity(0.18),
                          width: sel ? 2 : 1),
                      boxShadow: sel ? [BoxShadow(color: _color.withOpacity(0.4),
                          blurRadius: 12, offset: const Offset(0, 4))] : [],
                    ),
                    child: Center(child: Icon(lvl['icon'] as IconData,
                        color: sel ? Colors.white : (lvl['icolor'] as Color).withOpacity(0.5),
                        size: sel ? 20 : 16)),
                  ),
                  const SizedBox(height: 4),
                  Text(lvl['label'] as String, style: TextStyle(
                      color: sel ? _color : Colors.white.withOpacity(0.35),
                      fontSize: 9, fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                ]),
              );
            }),
          ),

          // Steps input for walking/running
          if (selectedActivity == 'Walking' || selectedActivity == 'Running') ...[
            const SizedBox(height: 18),
            _sliderSection(
              label: 'Steps',
              value: steps.toDouble(),
              min: 0, max: 20000, divisions: 40,
              displayVal: '$steps steps',
              icon: Icons.directions_walk_rounded,
              onChanged: (v) => setState(() => steps = v.toInt()),
            ),
          ],
        ]),
      ),
    ),
  ));

  Widget _sliderSection({
    required String label, required double value,
    required double min, required double max, required int divisions,
    required String displayVal, required IconData icon,
    required ValueChanged<double> onChanged,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(icon, color: _color, size: 16),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7),
          fontSize: 12, fontWeight: FontWeight.w700)),
      const Spacer(),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(displayVal, key: ValueKey(displayVal),
            style: TextStyle(color: _color, fontSize: 13, fontWeight: FontWeight.w900)),
      ),
    ]),
    const SizedBox(height: 6),
    SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _color,
        inactiveTrackColor: Colors.white.withOpacity(0.1),
        thumbColor: _color,
        overlayColor: _color.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        trackHeight: 4,
      ),
      child: Slider(value: value, min: min, max: max,
          divisions: divisions, onChanged: onChanged),
    ),
  ]);

  // ── Week history ───────────────────────────────────────────────────────
  Widget _weekHistoryCard() {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
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
                    gradient: LinearGradient(colors: _colors),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16)),
              const SizedBox(width: 10),
              const Text('Activity This Week', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF4ECCA3).withOpacity(0.12),
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
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4ECCA3))))))
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
                  final entry = weekHistory.length > i ? weekHistory[i] : null;
                  final dur = (entry?['duration'] as num?)?.toInt() ?? 0;
                  final act = entry?['activity'] as String? ?? '';
                  final hasData = dur > 0;
                  final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
                  final entryDate = now.subtract(Duration(days: 6 - i));
                  final entryDs = '${entryDate.year}-${entryDate.month.toString().padLeft(2,'0')}-${entryDate.day.toString().padLeft(2,'0')}';
                  final isToday = entryDs == todayStr;
                  final dayIdx = entryDate.weekday - 1;
                  final actData = hasData ? activities.firstWhere(
                      (a) => a['name'] == act, orElse: () => activities[0]) : null;
                  final barColor = actData?['color'] as Color? ?? const Color(0xFF4ECCA3);

                  return Column(children: [
                    Container(width: 32, height: 52,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: isToday ? Border.all(color: _color.withOpacity(0.5),
                              width: 1.5) : null),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          width: 32,
                          height: hasData ? (dur / 90 * 52).clamp(8.0, 52.0) : 0,
                          decoration: BoxDecoration(
                            gradient: hasData ? LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [barColor.withOpacity(0.9), barColor.withOpacity(0.4)]) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        if (hasData && actData != null)
                          Positioned(top: 2, child: Icon(actData['icon'] as IconData,
                              color: Colors.white.withOpacity(0.8), size: 11)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(dayLabels[dayIdx], style: TextStyle(
                        color: isToday ? _color : Colors.white.withOpacity(0.4),
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.w900 : FontWeight.w600)),
                    if (hasData) Text('${dur}m', style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 8, fontWeight: FontWeight.w500)),
                  ]);
                }),
              ),
            if (!_loadingHistory) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(Icons.calendar_today_rounded, '${weekHistory.where((e) => ((e['duration'] as num?)?.toInt() ?? 0) > 0).length}/7', 'Active days'),
                _vDiv(),
                _stat(Icons.timer_rounded,
                    weekHistory.where((e) => ((e['duration'] as num?)?.toInt() ?? 0) > 0).isEmpty ? '--'
                        : '${(weekHistory.where((e) => ((e['duration'] as num?)?.toInt() ?? 0) > 0).map((e) => (e['duration'] as num?)?.toInt() ?? 0).reduce((a, b) => a + b) / weekHistory.where((e) => ((e['duration'] as num?)?.toInt() ?? 0) > 0).length).toStringAsFixed(0)}m',
                    'Avg session'),
                _vDiv(),
                _stat(Icons.local_fire_department_rounded, '$_estimatedCalories', 'Cal today', iconColor: const Color(0xFFFF6B6B)),
              ]),
            ],
          ]),
        ),
      ),
    ));
  }

  Widget _stat(IconData icon, String v, String l, {Color? iconColor}) => Column(children: [
    Icon(icon, color: iconColor ?? _color.withOpacity(0.7), size: 16),
    const SizedBox(height: 3),
    Text(v, style: const TextStyle(color: Colors.white, fontSize: 13,
        fontWeight: FontWeight.w900, height: 1)),
    Text(l, style: TextStyle(color: Colors.white.withOpacity(0.4),
        fontSize: 9, fontWeight: FontWeight.w600)),
  ]);

  Widget _vDiv() => Container(width: 1, height: 34, color: Colors.white.withOpacity(0.1));

  Widget _logButton() => GestureDetector(
    onTap: isLoading ? null : _logActivity,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _colors),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _color.withOpacity(0.45),
            blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: isLoading
          ? const Center(child: SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white))))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_currentActivity['icon'] as IconData,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text('Log ${duration.toInt()}min of $selectedActivity',
                  style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w900, letterSpacing: 0.3)),
            ]),
    ),
  );
}

