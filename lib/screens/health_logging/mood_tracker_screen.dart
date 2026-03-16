import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '/services/auth_service.dart';

class MoodTrackerScreen extends StatefulWidget {
  const MoodTrackerScreen({Key? key}) : super(key: key);

  @override
  State<MoodTrackerScreen> createState() => _MoodTrackerScreenState();
}

class _MoodTrackerScreenState extends State<MoodTrackerScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers ─────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _emojiCtrl;
  late AnimationController _cardCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _emojiScaleAnim;
  late List<Animation<double>> _cardAnims;

  // ── Services ──────────────────────────────────────────────────────────
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _noteCtrl = TextEditingController();
  final FocusNode _noteFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────
  int selectedMood = 3;
  bool isLoading = false;
  bool _loadingHistory = true;
  bool _alreadyLoggedToday = false;

  List<Map<String, dynamic>> weekHistory = [];
  int currentStreak = 0;

  // ── Mood data ─────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> moods = [
    {
      'value': 1, 'emoji': '😢', 'icon': Icons.sentiment_very_dissatisfied_rounded, 'label': 'Terrible',
      'sub': 'Really rough day',
      'color': const Color(0xFFFF6B6B),
      'colors': [const Color(0xFFFF6B6B), const Color(0xFFEE5A6F)],
    },
    {
      'value': 2, 'emoji': '😕', 'icon': Icons.sentiment_dissatisfied_rounded, 'label': 'Bad',
      'sub': 'Not great',
      'color': const Color(0xFFFF9068),
      'colors': [const Color(0xFFFF9068), const Color(0xFFFF6B6B)],
    },
    {
      'value': 3, 'emoji': '😐', 'icon': Icons.sentiment_neutral_rounded, 'label': 'Neutral',
      'sub': 'Could be better',
      'color': const Color(0xFFFFC857),
      'colors': [const Color(0xFFFFC857), const Color(0xFFFFD93D)],
    },
    {
      'value': 4, 'emoji': '😊', 'icon': Icons.sentiment_satisfied_rounded, 'label': 'Good',
      'sub': 'Feeling well',
      'color': const Color(0xFF2EC4B6),
      'colors': [const Color(0xFF2EC4B6), const Color(0xFF4ECCA3)],
    },
    {
      'value': 5, 'emoji': '🤩', 'icon': Icons.sentiment_very_satisfied_rounded, 'label': 'Amazing',
      'sub': 'On top of the world!',
      'color': const Color(0xFF4ECCA3),
      'colors': [const Color(0xFF4ECCA3), const Color(0xFF6BCF7F)],
    },
  ];

  final List<Map<String, dynamic>> moodFactors = [
    {'label': 'Work',     'icon': Icons.work_rounded},
    {'label': 'Love',     'icon': Icons.favorite_rounded},
    {'label': 'Health',   'icon': Icons.health_and_safety_rounded},
    {'label': 'Sleep',    'icon': Icons.bedtime_rounded},
    {'label': 'Exercise', 'icon': Icons.fitness_center_rounded},
    {'label': 'Social',   'icon': Icons.people_rounded},
    {'label': 'Family',   'icon': Icons.family_restroom_rounded},
    {'label': 'Weather',  'icon': Icons.wb_sunny_rounded},
    {'label': 'Money',    'icon': Icons.account_balance_wallet_rounded},
    {'label': 'Hobbies',  'icon': Icons.palette_rounded},
  ];

  List<String> selectedFactors = [];

  Map<String, dynamic> get _currentMood =>
      moods.firstWhere((m) => m['value'] == selectedMood);

  // ── Init ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadHistory();
  }

  void _initAnimations() {
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _emojiCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _emojiScaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _emojiCtrl, curve: Curves.elasticOut));

    _cardAnims = List.generate(4, (i) {
      final start = i * 0.15;
      final end = (start + 0.5).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _cardCtrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic)));
    });

    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _emojiCtrl.forward();
        _cardCtrl.forward();
      }
    });
  }

  // ── Firebase ─────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    try {
      final user = _authService.currentUser;
      if (user == null) { setState(() => _loadingHistory = false); return; }

      final now = DateTime.now();
      final days = List.generate(7, (i) {
        final d = now.subtract(Duration(days: i));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      final List<Map<String, dynamic>> history = [];
      int streak = 0;
      bool streakBroken = false;

      for (int i = 0; i < days.length; i++) {
        final doc = await _firestore
            .collection('users').doc(user.uid)
            .collection('mood_logs').doc(days[i]).get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          history.add({
            'date': days[i],
            'rating': data['rating'] ?? 0,
            'emoji': data['emoji'] ?? '😐',
            'label': data['label'] ?? '',
          });
          if (!streakBroken) streak++;
          if (i == 0) _alreadyLoggedToday = true;
        } else {
          history.add({'date': days[i], 'rating': 0, 'emoji': '', 'label': ''});
          if (i > 0) streakBroken = true; // only break on past days
        }
      }

      if (mounted) {
        setState(() {
          weekHistory = history.reversed.toList();
          currentStreak = streak;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _saveMoodData() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) { _snack('Please log in first', error: true); return; }

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      await _firestore.collection('users').doc(user.uid)
          .collection('mood_logs').doc(dateStr).set({
        'rating': selectedMood,
        'emoji': _currentMood['emoji'],
        'label': _currentMood['label'],
        'note': _noteCtrl.text.trim(),
        'factors': selectedFactors,
        'timestamp': FieldValue.serverTimestamp(),
        'date': dateStr,
        'created_at': now.millisecondsSinceEpoch,
      });

      await _firestore.collection('users').doc(user.uid)
          .collection('daily_summary').doc(dateStr).set({
        'mood': {
          'value': selectedMood,
          'emoji': _currentMood['emoji'],
          'label': _currentMood['label'],
        },
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      HapticFeedback.heavyImpact();
      _snack('Mood logged successfully!');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Failed to save: ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: error ? const Color(0xFFFF6B6B) : const Color(0xFF4ECCA3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: error ? 4 : 2),
    ));
  }

  void _selectMood(int value) {
    if (selectedMood == value) return;
    HapticFeedback.selectionClick();
    _emojiCtrl.reset();
    setState(() => selectedMood = value);
    _emojiCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _emojiCtrl.dispose();
    _cardCtrl.dispose();
    _noteCtrl.dispose();
    _noteFocus.dispose();
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
          _blobs(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  children: [
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
                                  _moodSelectorCard(),
                                  const SizedBox(height: 14),
                                  _weekHistoryCard(),
                                  const SizedBox(height: 14),
                                  _factorsCard(),
                                  const SizedBox(height: 14),
                                  _noteCard(),
                                  const SizedBox(height: 20),
                                  _saveButton(),
                                  const SizedBox(height: 30),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ambient blobs ──────────────────────────────────────────────────────
  Widget _blobs() {
    final color = _currentMood['color'] as Color;
    return Stack(children: [
      Positioned(
        top: -60,
        right: -40,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.08),
          ),
        ),
      ),
      Positioned(
        bottom: 120,
        left: -60,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7B2CBF).withOpacity(0.07),
          ),
        ),
      ),
    ]);
  }

  // ── Header ────────────────────────────────────────────────────────────
  Widget _header() {
    final color = _currentMood['color'] as Color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
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
                const Text('Mood Tracker',
                    style: TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: 0.2)),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 400),
                  style: TextStyle(
                      fontSize: 11, color: color,
                      fontWeight: FontWeight.w600),
                  child: Text(_currentMood['sub'] as String),
                ),
              ],
            ),
          ),
          // Streak badge
          if (currentStreak > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text('$currentStreak day${currentStreak > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mood_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('Daily', style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w900)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Mood Selector Card ────────────────────────────────────────────────
  Widget _animCard(int i, Widget child) {
    final idx = i.clamp(0, _cardAnims.length - 1);
    return AnimatedBuilder(
      animation: _cardAnims[idx],
      builder: (_, __) => Opacity(
        opacity: _cardAnims[idx].value,
        child: Transform.translate(
          offset: Offset(0, (1 - _cardAnims[idx].value) * 24),
          child: child,
        ),
      ),
    );
  }

  Widget _moodSelectorCard() {
    final mood = _currentMood;
    final color = mood['color'] as Color;
    final colors = mood['colors'] as List<Color>;

    return _animCard(0, ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.18),
                color.withOpacity(0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 28, offset: const Offset(0, 10))
            ],
          ),
          child: Column(
            children: [
              // ── Big emoji + label ──────────────────────────────────
              Row(
                children: [
                  // Pulsing emoji circle
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: ScaleTransition(
                        scale: _emojiScaleAnim,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: colors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            boxShadow: [
                              BoxShadow(
                                  color: color.withOpacity(0.45),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8))
                            ],
                          ),
                          child: Center(
                            child: Icon(mood['icon'] as IconData,
                                color: Colors.white, size: 44),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Label column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Today's Mood",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            mood['label'] as String,
                            key: ValueKey(selectedMood),
                            style: TextStyle(
                                color: color,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                height: 1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Rating pills
                        Row(
                          children: List.generate(5, (i) {
                            final filled = i < selectedMood;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(right: 4),
                              width: filled ? 20 : 14,
                              height: 6,
                              decoration: BoxDecoration(
                                color: filled
                                    ? color
                                    : Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 6),
                        Text('${selectedMood}/5  •  ${mood['sub']}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                        if (_alreadyLoggedToday) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Already logged today — updating',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ── Mood picker row ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: moods.map((m) {
                  final sel = m['value'] == selectedMood;
                  final mColor = m['color'] as Color;
                  return GestureDetector(
                    onTap: () => _selectMood(m['value'] as int),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          width: sel ? 56 : 44,
                          height: sel ? 56 : 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: sel
                                ? LinearGradient(
                                    colors: m['colors'] as List<Color>,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight)
                                : null,
                            color: sel ? null : Colors.white.withOpacity(0.08),
                            border: Border.all(
                              color: sel
                                  ? mColor
                                  : Colors.white.withOpacity(0.18),
                              width: sel ? 2.5 : 1.2,
                            ),
                            boxShadow: sel
                                ? [BoxShadow(
                                    color: mColor.withOpacity(0.45),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6))]
                                : [],
                          ),
                          child: Center(
                            child: Icon(m['icon'] as IconData,
                                color: sel ? Colors.white : Colors.white.withOpacity(0.45),
                                size: sel ? 28 : 20),
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: TextStyle(
                              color: sel ? mColor : Colors.white.withOpacity(0.4),
                              fontSize: sel ? 10 : 9,
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w500),
                          child: Text(m['label'] as String),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // ── Week History Card ─────────────────────────────────────────────────
  Widget _weekHistoryCard() {
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();

    return _animCard(1, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
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
                          colors: [Color(0xFF7B2CBF), Color(0xFF00D9FF)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('This Week',
                      style: TextStyle(
                          color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECCA3).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: const Color(0xFF4ECCA3).withOpacity(0.3)),
                    ),
                    child: const Text('REAL DATA',
                        style: TextStyle(
                            color: Color(0xFF4ECCA3), fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingHistory)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            const Color(0xFF2EC4B6)),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    final entry = weekHistory.length > i ? weekHistory[i] : null;
                    final rating = entry?['rating'] as int? ?? 0;
                    final hasData = rating > 0;

                    // Determine if this is today
                    final entryDate = entry?['date'] as String? ?? '';
                    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                    final isToday = entryDate == todayStr;

                    final dayIndex = now.subtract(Duration(days: 6 - i)).weekday - 1;
                    final moodColor = hasData
                        ? (moods.firstWhere((m) => m['value'] == rating,
                            orElse: () => moods[2])['color'] as Color)
                        : Colors.white.withOpacity(0.12);

                    return Column(
                      children: [
                        // Bar
                        Container(
                          width: 32,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(
                                    color: const Color(0xFF00D9FF).withOpacity(0.5),
                                    width: 1.5)
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                width: 32,
                                height: hasData
                                    ? (rating / 5 * 50).clamp(8.0, 50.0)
                                    : 0,
                                decoration: BoxDecoration(
                                  gradient: hasData
                                      ? LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            moodColor.withOpacity(0.9),
                                            moodColor.withOpacity(0.4)
                                          ])
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              if (hasData)
                                Positioned(
                                  top: 4,
                                  child: Icon(
                                      (moods.firstWhere((m) => m['value'] == rating,
                                          orElse: () => moods[2])['icon'] as IconData),
                                      color: Colors.white.withOpacity(0.8), size: 13),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(dayLabels[dayIndex],
                            style: TextStyle(
                                color: isToday
                                    ? const Color(0xFF00D9FF)
                                    : Colors.white.withOpacity(0.4),
                                fontSize: 10,
                                fontWeight: isToday
                                    ? FontWeight.w900
                                    : FontWeight.w600)),
                      ],
                    );
                  }),
                ),
              if (!_loadingHistory) ...[
                const SizedBox(height: 14),
                // Summary row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _weekStat(Icons.calendar_today_rounded,
                        '${weekHistory.where((e) => (e['rating'] as int? ?? 0) > 0).length}/7',
                        'Days logged'),
                    _vDiv(),
                    _weekStat(Icons.local_fire_department_rounded, '$currentStreak', 'Day streak'),
                    _vDiv(),
                    _weekStat(Icons.favorite_rounded,
                        weekHistory.where((e) =>
                            (e['rating'] as int? ?? 0) > 0).isEmpty
                            ? '--'
                            : '${(weekHistory.where((e) => (e['rating'] as int? ?? 0) > 0).map((e) => e['rating'] as int).reduce((a, b) => a + b) / weekHistory.where((e) => (e['rating'] as int? ?? 0) > 0).length).toStringAsFixed(1)}/5',
                        'Avg mood'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ));
  }

  Widget _weekStat(IconData icon, String val, String label) {
    return Column(
      children: [
        Icon(icon, color: _currentMood['color'] is Color ? (_currentMood['color'] as Color).withOpacity(0.7) : Colors.white.withOpacity(0.5), size: 16),
        const SizedBox(height: 3),
        Text(val,
            style: const TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w900, height: 1)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 9, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _vDiv() => Container(
      width: 1, height: 34, color: Colors.white.withOpacity(0.1));

  // ── Factors Card ──────────────────────────────────────────────────────
  Widget _factorsCard() {
    final color = _currentMood['color'] as Color;

    return _animCard(2, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
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
                    child: const Icon(Icons.tune_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("What's Influencing You?",
                            style: TextStyle(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        Text('Select all that apply',
                            style: TextStyle(
                                color: Color(0xFF00D9FF),
                                fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (selectedFactors.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [color, color.withOpacity(0.7)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${selectedFactors.length} selected',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Factor chips — Wrap to avoid overflow
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: moodFactors.map((f) {
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? LinearGradient(
                                colors: [color, color.withOpacity(0.7)])
                            : null,
                        color: sel ? null : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? color.withOpacity(0.6)
                              : Colors.white.withOpacity(0.15),
                          width: sel ? 1.5 : 1,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3))]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(f['icon'] as IconData,
                              color: sel
                                  ? Colors.white
                                  : const Color(0xFF00D9FF),
                              size: 14),
                          const SizedBox(width: 6),
                          Text(f['label'] as String,
                              style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.75),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // ── Note Card ─────────────────────────────────────────────────────────
  Widget _noteCard() {
    return _animCard(3, ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
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
                          colors: [Color(0xFF9D84B7), Color(0xFF7B2CBF)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Add a Note",
                            style: TextStyle(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        Text('Optional — how are you feeling?',
                            style: TextStyle(
                                color: Color(0xFF9D84B7),
                                fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                focusNode: _noteFocus,
                maxLines: 4,
                maxLength: 500,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w500, height: 1.5),
                decoration: InputDecoration(
                  hintText: "Write what's on your mind...",
                  hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.15))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.15))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: Color(0xFF7B2CBF), width: 1.8)),
                  contentPadding: const EdgeInsets.all(14),
                  counterStyle: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  // ── Save Button ───────────────────────────────────────────────────────
  Widget _saveButton() {
    final mood = _currentMood;
    final colors = mood['colors'] as List<Color>;
    final color = mood['color'] as Color;

    return GestureDetector(
      onTap: isLoading ? null : _saveMoodData,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.45),
                blurRadius: 22, offset: const Offset(0, 8))
          ],
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(mood['icon'] as IconData,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _alreadyLoggedToday
                        ? 'Update Today\'s Mood'
                        : 'Save Mood Entry',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                ],
              ),
      ),
    );
  }
}

