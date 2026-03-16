import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '/services/auth_service.dart';

class WaterTrackerScreen extends StatefulWidget {
  const WaterTrackerScreen({Key? key}) : super(key: key);
  @override
  State<WaterTrackerScreen> createState() => _WaterTrackerScreenState();
}

class _WaterTrackerScreenState extends State<WaterTrackerScreen>
    with TickerProviderStateMixin {

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _cardCtrl;
  late AnimationController _rippleCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;
  late List<Animation<double>> _cardAnims;

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _noteCtrl = TextEditingController();

  bool isLoading = false;
  bool _loadingData = true;

  int currentIntake = 0;
  int dailyGoal = 8;
  List<Map<String, dynamic>> todaysLog = [];
  List<int> weekData = List.filled(7, 0);

  static const Color _accent = Color(0xFF00D9FF);
  static const Color _accentDark = Color(0xFF0EA5E9);

  final List<Map<String, dynamic>> drinkTypes = [
    {'name': 'Water',    'icon': Icons.water_drop_rounded,       'ml': 250, 'color': Color(0xFF00D9FF)},
    {'name': 'Coffee',   'icon': Icons.coffee_rounded,           'ml': 200, 'color': Color(0xFFB5851B)},
    {'name': 'Tea',      'icon': Icons.emoji_food_beverage_rounded, 'ml': 200, 'color': Color(0xFF6BCF7F)},
    {'name': 'Juice',    'icon': Icons.local_drink_rounded,      'ml': 250, 'color': Color(0xFFFF9F1C)},
    {'name': 'Milk',     'icon': Icons.local_cafe_rounded,       'ml': 250, 'color': Color(0xFFE8E8E8)},
    {'name': 'Smoothie', 'icon': Icons.blender_rounded,          'ml': 300, 'color': Color(0xFFFF69B4)},
  ];

  double get _progress => (currentIntake / dailyGoal).clamp(0.0, 1.0);
  int get _totalMl => todaysLog.fold(0, (s, d) => s + ((d['ml'] as num?)?.toInt() ?? 0));

  String get _hydrationStatus {
    if (_progress >= 1.0) return 'Goal reached! Well done';
    if (_progress >= 0.75) return 'Almost there! Keep going';
    if (_progress >= 0.5) return 'Halfway there! Stay hydrated';
    if (_progress >= 0.25) return 'Just started — drink more!';
    return "Let's get hydrated!";
  }

  Color get _statusColor {
    if (_progress >= 1.0) return const Color(0xFF4ECCA3);
    if (_progress >= 0.5) return _accent;
    return const Color(0xFFFFC857);
  }

  IconData _getDrinkIcon(String name) {
    final match = drinkTypes.where((d) => d['name'] == name);
    return match.isNotEmpty ? match.first['icon'] as IconData : Icons.water_drop_rounded;
  }

  Color _getDrinkColor(String name) {
    final match = drinkTypes.where((d) => d['name'] == name);
    return match.isNotEmpty ? match.first['color'] as Color : _accent;
  }

  @override
  void initState() {
    super.initState();
    _initAnims();
    _loadData();
  }

  void _initAnims() {
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _cardCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _fadeAnim  = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _rippleAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));

    _cardAnims = List.generate(5, (i) {
      final s = (i * 0.13).clamp(0.0, 1.0);
      final e = (s + 0.5).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _cardCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });
    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _cardCtrl.forward();
    });
  }

  Future<void> _loadData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) { setState(() => _loadingData = false); return; }
      final now = DateTime.now();
      final ds = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

      final doc = await _firestore.collection('users').doc(user.uid)
          .collection('water_logs').doc(ds).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        currentIntake = data['glasses'] ?? 0;
        dailyGoal    = data['dailyGoal'] ?? 8;
        todaysLog    = List<Map<String, dynamic>>.from(data['drinks'] ?? []);
      }

      final List<int> wk = [];
      for (int i = 6; i >= 0; i--) {
        final d   = now.subtract(Duration(days: i));
        final dds = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        final wd  = await _firestore.collection('users').doc(user.uid)
            .collection('water_logs').doc(dds).get();
        wk.add(wd.exists ? (wd.data()?['glasses'] ?? 0) : 0);
      }
      if (mounted) setState(() { weekData = wk; _loadingData = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  void _addDrink(Map<String, dynamic> drink) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      currentIntake++;
      todaysLog.add({
        'name': drink['name'],
        'ml': drink['ml'], 'time': DateTime.now().millisecondsSinceEpoch,
      });
    });
    _rippleCtrl.forward(from: 0);
  }

  void _undoLast() {
    if (todaysLog.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() { currentIntake--; todaysLog.removeLast(); });
  }

  Future<void> _saveWaterData() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) { _snack('Please log in first', error: true); return; }
      final now = DateTime.now();
      final ds  = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      await _firestore.collection('users').doc(user.uid)
          .collection('water_logs').doc(ds).set({
        'glasses': currentIntake, 'totalMl': _totalMl,
        'dailyGoal': dailyGoal,   'progressPercentage': _progress,
        'drinks': todaysLog,      'note': _noteCtrl.text.trim(),
        'timestamp': FieldValue.serverTimestamp(), 'date': ds,
        'created_at': now.millisecondsSinceEpoch,
      });
      await _firestore.collection('users').doc(user.uid)
          .collection('daily_summary').doc(ds).set({
        'water': {'glasses': currentIntake, 'totalMl': _totalMl,
                  'goalAchieved': currentIntake >= dailyGoal},
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      HapticFeedback.heavyImpact();
      _snack('Water intake saved successfully!');
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

  @override
  void dispose() {
    _entryCtrl.dispose(); _pulseCtrl.dispose(); _cardCtrl.dispose();
    _rippleCtrl.dispose(); _noteCtrl.dispose();
    super.dispose();
  }

  Widget _ac(int i, Widget child) {
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

  Widget _glass(Color bg, [Color? border]) => Container(
    width: double.infinity, height: 4,
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(2),
    ),
  );

  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(children: [
        _blobs(),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(children: [
                _header(),
                Expanded(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _heroCard(),        const SizedBox(height: 14),
                              _weekCard(),        const SizedBox(height: 14),
                              _drinkTypesCard(),  const SizedBox(height: 14),
                              _logCard(),         const SizedBox(height: 14),
                              _noteCard(),        const SizedBox(height: 20),
                              _saveButton(),      const SizedBox(height: 30),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _blobs() {
    return Stack(children: [
      Positioned(
        top: -60, right: -40,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.07 * _progress + 0.03),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 120, left: -60,
        child: Container(
          width: 180, height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accentDark.withOpacity(0.06),
          ),
        ),
      ),
    ]);
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(children: [
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Water Tracker', style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: 0.2)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(_hydrationStatus,
                key: ValueKey(_hydrationStatus),
                style: const TextStyle(fontSize: 11, color: _accent,
                    fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        GestureDetector(
          onTap: todaysLog.isEmpty ? null : _undoLast,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: todaysLog.isEmpty
                  ? Colors.white.withOpacity(0.05)
                  : _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: todaysLog.isEmpty
                    ? Colors.white.withOpacity(0.1)
                    : _accent.withOpacity(0.4),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.undo_rounded,
                  color: todaysLog.isEmpty ? Colors.white.withOpacity(0.3) : _accent,
                  size: 13),
              const SizedBox(width: 4),
              Text('Undo', style: TextStyle(
                  color: todaysLog.isEmpty ? Colors.white.withOpacity(0.3) : _accent,
                  fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Hero card ──────────────────────────────────────────────────────────
  Widget _heroCard() {
    return _ac(0, ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_accent.withOpacity(0.16), _accent.withOpacity(0.06)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _accent.withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: _accent.withOpacity(0.18),
                blurRadius: 28, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            Row(children: [
              // Ripple + pulsing water circle
              AnimatedBuilder(
                animation: _rippleAnim,
                builder: (_, __) => Stack(alignment: Alignment.center, children: [
                  if (_rippleAnim.value > 0)
                    Transform.scale(
                      scale: 1 + _rippleAnim.value * 0.4,
                      child: Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withOpacity((1 - _rippleAnim.value) * 0.3),
                        ),
                      ),
                    ),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_accent, _accentDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [BoxShadow(color: _accent.withOpacity(0.45),
                              blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: Stack(alignment: Alignment.center, children: [
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              height: 90 * _progress,
                              width: 90,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.only(
                                  bottomLeft: const Radius.circular(45),
                                  bottomRight: const Radius.circular(45),
                                  topLeft: _progress >= 1
                                      ? const Radius.circular(45) : Radius.zero,
                                  topRight: _progress >= 1
                                      ? const Radius.circular(45) : Radius.zero,
                                ),
                              ),
                            ),
                          ),
                          Icon(Icons.water_drop_rounded, color: _accent, size: 36),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Today's Intake",
                      style: TextStyle(color: Colors.white.withOpacity(0.55),
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text('$currentIntake / $dailyGoal',
                        key: ValueKey(currentIntake),
                        style: const TextStyle(color: _accent, fontSize: 30,
                            fontWeight: FontWeight.w900, height: 1)),
                  ),
                  const SizedBox(height: 2),
                  Text('glasses  •  ${_totalMl}ml',
                      style: TextStyle(color: Colors.white.withOpacity(0.45),
                          fontSize: 11, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: _progress, minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(dailyGoal, (i) => Expanded(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300 + i * 50),
                        margin: const EdgeInsets.only(right: 2),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < currentIntake
                              ? _accent : Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    )),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => _addDrink(drinkTypes[0]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: _accent.withOpacity(0.35),
                      blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.water_drop_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('+1 Glass of Water', style: TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ));
  }

  // ── Week card ──────────────────────────────────────────────────────────
  Widget _weekCard() {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    return _ac(1, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              const Text('This Week', style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ECCA3).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.3)),
                ),
                child: const Text('REAL DATA', style: TextStyle(color: Color(0xFF4ECCA3),
                    fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              ),
            ]),
            const SizedBox(height: 16),
            _loadingData
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(_accent)))))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (i) {
                      final glasses = weekData.length > i ? weekData[i] : 0;
                      final hasData = glasses > 0;
                      final entryDate = now.subtract(Duration(days: 6 - i));
                      final entryDs = '${entryDate.year}-${entryDate.month.toString().padLeft(2,'0')}-${entryDate.day.toString().padLeft(2,'0')}';
                      final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
                      final isToday = entryDs == todayStr;
                      final dayIdx  = entryDate.weekday - 1;
                      final pct = hasData ? (glasses / dailyGoal).clamp(0.0, 1.0) : 0.0;
                      final barColor = pct >= 1
                          ? const Color(0xFF4ECCA3)
                          : pct >= 0.5
                              ? _accent
                              : const Color(0xFFFFC857);

                      return Column(children: [
                        Container(
                          width: 32, height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(color: _accent.withOpacity(0.5), width: 1.5)
                                : null,
                          ),
                          child: Stack(alignment: Alignment.bottomCenter, children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              width: 32,
                              height: hasData ? (pct * 52).clamp(8.0, 52.0) : 0,
                              decoration: BoxDecoration(
                                gradient: hasData ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [barColor.withOpacity(0.9),
                                             barColor.withOpacity(0.4)]) : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            if (hasData)
                              Positioned(top: 3,
                                  child: Icon(pct >= 1 ? Icons.check_circle_rounded : Icons.water_drop_rounded,
                                      color: Colors.white.withOpacity(0.8), size: 11)),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        Text(dayLabels[dayIdx], style: TextStyle(
                            color: isToday ? _accent : Colors.white.withOpacity(0.4),
                            fontSize: 10,
                            fontWeight: isToday ? FontWeight.w900 : FontWeight.w600)),
                        if (hasData)
                          Text('$glasses', style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 8, fontWeight: FontWeight.w500)),
                      ]);
                    }),
                  ),
            if (!_loadingData) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(Icons.calendar_today_rounded, '${weekData.where((g) => g > 0).length}/7', 'Days'),
                _vDiv(),
                _stat(Icons.emoji_events_rounded, '${weekData.where((g) => g >= dailyGoal).length}', 'Goals met'),
                _vDiv(),
                _stat(Icons.water_drop_rounded,
                    weekData.every((g) => g == 0)
                        ? '--'
                        : '${(weekData.where((g) => g > 0).map((g) => g).reduce((a, b) => a + b) / weekData.where((g) => g > 0).length).toStringAsFixed(1)}',
                    'Avg/day'),
              ]),
            ],
          ]),
        ),
      ),
    ));
  }

  Widget _stat(IconData icon, String v, String l) {
    return Column(children: [
      Icon(icon, color: _accent.withOpacity(0.7), size: 16),
      const SizedBox(height: 3),
      Text(v, style: const TextStyle(color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w900, height: 1)),
      Text(l, style: TextStyle(color: Colors.white.withOpacity(0.4),
          fontSize: 9, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _vDiv() => Container(width: 1, height: 34, color: Colors.white.withOpacity(0.1));

  // ── Drink types grid ───────────────────────────────────────────────────
  Widget _drinkTypesCard() {
    return _ac(2, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_drink_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Add a Drink', style: TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('Tap to log your intake', style: TextStyle(
                      color: _accent, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Text('$currentIntake glasses',
                    style: TextStyle(color: _accent,
                        fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: 1.0,
                crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: drinkTypes.length,
              itemBuilder: (_, i) {
                final d     = drinkTypes[i];
                final color = d['color'] as Color;
                return GestureDetector(
                  onTap: () => _addDrink(d),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withOpacity(0.3), width: 1.2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(d['icon'] as IconData, color: color, size: 28),
                      const SizedBox(height: 4),
                      Text(d['name'] as String, style: TextStyle(
                          color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                      Text('${d['ml']}ml', style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 9, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    ));
  }

  // ── Today's log ────────────────────────────────────────────────────────
  Widget _logCard() {
    return _ac(3, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.list_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              const Text("Today's Log", style: TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${todaysLog.length} entries',
                  style: TextStyle(color: Colors.white.withOpacity(0.4),
                      fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 14),
            todaysLog.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Icon(Icons.water_drop_outlined, color: _accent.withOpacity(0.4), size: 32),
                        const SizedBox(height: 8),
                        Text('No drinks logged yet.\nStart by adding a drink above!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.4),
                                fontSize: 12, height: 1.5)),
                      ]),
                    ),
                  )
                : Column(
                    children: [
                      ...todaysLog.reversed.take(5).map((d) {
                        final name    = d['name']  as String? ?? 'Water';
                        final drinkIcon = _getDrinkIcon(name);
                        final drinkColor = _getDrinkColor(name);
                        final ml      = (d['ml'] as num?)?.toInt() ?? 250;
                        final timeMs  = (d['time'] as num?)?.toInt() ?? 0;
                        final t = timeMs > 0
                            ? DateTime.fromMillisecondsSinceEpoch(timeMs) : null;
                        final timeStr = t != null
                            ? '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'
                            : '--:--';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: _accent.withOpacity(0.15)),
                          ),
                          child: Row(children: [
                            Icon(drinkIcon, color: drinkColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(
                                      color: Colors.white, fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                                  Text('${ml}ml', style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 10, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            Text(timeStr, style: TextStyle(
                                color: _accent.withOpacity(0.7),
                                fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        );
                      }),
                      if (todaysLog.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('+${todaysLog.length - 5} more entries',
                              style: TextStyle(color: _accent.withOpacity(0.6),
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
          ]),
        ),
      ),
    ));
  }

  // ── Note card ──────────────────────────────────────────────────────────
  Widget _noteCard() {
    return _ac(4, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accent, _accentDark]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Add a Note', style: TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800)),
                  Text('Optional', style: TextStyle(
                      color: _accent, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _noteCtrl, maxLines: 2, maxLength: 200,
              style: const TextStyle(color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w500, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Any hydration notes?',
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
  }

  // ── Save button ────────────────────────────────────────────────────────
  Widget _saveButton() {
    final goalMet = currentIntake >= dailyGoal;
    return GestureDetector(
      onTap: isLoading ? null : _saveWaterData,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: goalMet
                  ? [const Color(0xFF4ECCA3), const Color(0xFF2EC4B6)]
                  : [_accent, _accentDark]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
              color: (goalMet ? const Color(0xFF4ECCA3) : _accent).withOpacity(0.45),
              blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: isLoading
            ? const Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white))))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(goalMet ? Icons.emoji_events_rounded : Icons.water_drop_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(goalMet ? 'Goal Reached! Save Log' : 'Save Water Log',
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w900, letterSpacing: 0.3)),
              ]),
      ),
    );
  }
}

