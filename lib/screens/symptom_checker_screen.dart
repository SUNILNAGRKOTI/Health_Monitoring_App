import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../data/symptom_database.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SEVERITY ARC PAINTER
// ═══════════════════════════════════════════════════════════════════════════
class _SeverityArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  _SeverityArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide / 2) - 8;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi, false,
      Paint()..color = Colors.white.withOpacity(0.08)..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * progress, false,
        Paint()
          ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: 3 * math.pi / 2,
            colors: [color, color.withOpacity(0.5), color]).createShader(Rect.fromCircle(center: c, radius: r))
          ..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeverityArcPainter old) => old.progress != progress || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
//                     SYMPTOM CHECKER SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class SymptomCheckerScreen extends StatefulWidget {
  const SymptomCheckerScreen({Key? key}) : super(key: key);
  @override
  State<SymptomCheckerScreen> createState() => _SymptomCheckerScreenState();
}

class _SymptomCheckerScreenState extends State<SymptomCheckerScreen>
    with TickerProviderStateMixin {

  // ── Animations ─────────────────────────────────────────────────────
  late AnimationController _mainCtrl, _resultCtrl, _pulseCtrl, _analyzeCtrl, _ringCtrl;
  late Animation<double> _fadeAnim, _resultFade, _pulseAnim, _ringAnim;
  late Animation<Offset> _slideAnim;

  // ── State ──────────────────────────────────────────────────────────
  Set<String> selectedSymptoms = {};
  Map<String, String> symptomDurations = {};
  int _screenIndex = 0;  // 0=selection, 1=analyzing, 2=results
  bool isEmergency = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> matchedConditions = [];
  List<Map<String, dynamic>> recentChecks = [];
  bool _loadingHistory = true;
  Set<int> _expandedCards = {};

  String searchQuery = '';
  String _selectedRegion = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  static const Map<String, List<String>> _regionCategories = {
    'Head': ['Neurological'],
    'Chest': ['Respiratory', 'Cardiovascular'],
    'Stomach': ['Digestive'],
    'Body': ['General', 'Skin', 'Other'],
  };

  static const List<Map<String, dynamic>> _regions = [
    {'key': 'All', 'icon': Icons.apps_rounded, 'label': 'All'},
    {'key': 'Head', 'icon': Icons.face_rounded, 'label': 'Head'},
    {'key': 'Chest', 'icon': Icons.airline_seat_flat_rounded, 'label': 'Chest'},
    {'key': 'Stomach', 'icon': Icons.set_meal_rounded, 'label': 'Stomach'},
    {'key': 'Body', 'icon': Icons.accessibility_new_rounded, 'label': 'Body'},
  ];

  static const List<String> _durationLabels = ['Just now', 'Few hours', '1-2 days', '3+ days'];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadHistory();
  }

  void _initAnimations() {
    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _resultCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _analyzeCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _fadeAnim = CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOutCubic));
    _resultFade = CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOutCubic);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOutCubic));

    _mainCtrl.forward();
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _resultCtrl.dispose();
    _pulseCtrl.dispose();
    _analyzeCtrl.dispose();
    _ringCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { setState(() => _loadingHistory = false); return; }
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('symptom_checks')
          .orderBy('timestamp', descending: true).limit(5).get();
      if (mounted) setState(() { recentChecks = snap.docs.map((d) => d.data()).toList(); _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _analyzeSymptoms() async {
    if (selectedSymptoms.isEmpty) {
      _showSnack('Please select at least one symptom', const Color(0xFFFF6B6B));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _screenIndex = 1);

    await Future.delayed(const Duration(milliseconds: 2500));

    isEmergency = SymptomData.isEmergency(selectedSymptoms);
    matchedConditions = SymptomData.matchConditions(selectedSymptoms);
    _expandedCards.clear();

    if (mounted) {
      setState(() => _screenIndex = 2);
      _resultCtrl.forward(from: 0);
      _ringCtrl.forward(from: 0);
    }
    _saveToFirebase();
  }

  Future<void> _saveToFirebase() async {
    try {
      setState(() => _isSaving = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour}-${now.minute}-${now.second}';
      await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('symptom_checks').doc(ts).set({
        'symptoms': selectedSymptoms.toList(),
        'durations': symptomDurations,
        'isEmergency': isEmergency,
        'matchedConditions': matchedConditions.take(3).map((c) => c['name']).toList(),
        'topMatchPercentage': matchedConditions.isNotEmpty ? matchedConditions[0]['matchPercentage'] : 0,
        'timestamp': FieldValue.serverTimestamp(),
        'date': ts,
      });
      _loadHistory();
    } catch (e) { debugPrint('Save error: $e'); }
    finally { if (mounted) setState(() => _isSaving = false); }
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _resultCtrl.reset();
    _ringCtrl.reset();
    setState(() {
      selectedSymptoms.clear();
      symptomDurations.clear();
      _screenIndex = 0;
      isEmergency = false;
      matchedConditions.clear();
      _expandedCards.clear();
      searchQuery = '';
      _searchCtrl.clear();
      _selectedRegion = 'All';
    });
    _mainCtrl.forward(from: 0);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(seconds: 3),
    ));
  }

  IconData _icon(String name) {
    const map = {
      'thermostat': Icons.thermostat_rounded, 'air': Icons.air_rounded, 'coronavirus': Icons.coronavirus_outlined,
      'wind_power': Icons.wind_power_rounded, 'water_drop': Icons.water_drop_rounded, 'blur_on': Icons.blur_on_rounded,
      'ac_unit': Icons.ac_unit_rounded, 'sick': Icons.sick_outlined, 'warning': Icons.warning_rounded,
      'emergency': Icons.emergency_rounded, 'restaurant': Icons.restaurant_rounded, 'no_meals': Icons.no_meals_rounded,
      'fitness_center': Icons.fitness_center_rounded, 'psychology': Icons.psychology_outlined,
      'refresh': Icons.refresh_rounded, 'help': Icons.help_outline_rounded, 'visibility_off': Icons.visibility_off_rounded,
      'battery_0_bar': Icons.battery_0_bar_rounded, 'accessibility_new': Icons.accessibility_new_rounded,
      'trending_down': Icons.trending_down_rounded, 'favorite_border': Icons.favorite_border_rounded,
      'favorite': Icons.favorite_rounded, 'water': Icons.water_rounded, 'healing': Icons.healing_rounded,
      'pest_control': Icons.pest_control_rounded, 'back_hand': Icons.back_hand_rounded,
      'airline_seat_recline_normal': Icons.airline_seat_recline_normal_rounded, 'hearing': Icons.hearing_rounded,
    };
    return map[name] ?? Icons.circle_outlined;
  }

  String get _severityLabel {
    if (isEmergency) return 'EMERGENCY';
    if (matchedConditions.isEmpty) return 'MILD';
    final s = matchedConditions[0]['severity'] as String;
    if (s.contains('Severe') || s.contains('EMERGENCY')) return 'SEVERE';
    if (s.contains('Moderate')) return 'MODERATE';
    return 'MILD';
  }

  Color get _severityColor {
    switch (_severityLabel) {
      case 'EMERGENCY': case 'SEVERE': return const Color(0xFFFF6B6B);
      case 'MODERATE': return const Color(0xFFFFC857);
      default: return const Color(0xFF4ECCA3);
    }
  }

  double get _severityScore {
    switch (_severityLabel) {
      case 'EMERGENCY': return 0.95;
      case 'SEVERE': return 0.8;
      case 'MODERATE': return 0.55;
      default: return 0.3;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(children: [
        _ambientBlobs(),
        SafeArea(
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _screenIndex == 1
                    ? _buildAnalyzingView()
                    : _screenIndex == 2
                        ? _buildResultsView()
                        : _buildSelectionView(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _ambientBlobs() {
    return Stack(children: [
      Positioned(top: -70, right: -50, child: Container(width: 220, height: 220,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF00D9FF).withOpacity(0.06)))),
      Positioned(bottom: 80, left: -60, child: Container(width: 200, height: 200,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7B2CBF).withOpacity(0.07)))),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════
  //  HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(children: [
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.15))),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Symptom Checker', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2)),
          Text(
            _screenIndex == 2 ? '${selectedSymptoms.length} symptoms analysed'
                : _screenIndex == 1 ? 'AI analyzing...'
                : 'Tap symptoms you feel',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
        ])),
        if (_screenIndex == 2)
          GestureDetector(
            onTap: _reset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [BoxShadow(color: const Color(0xFF00D9FF).withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))]),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 14), SizedBox(width: 5),
                Text('New Check', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(10)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 11), SizedBox(width: 4),
              Text('AI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ]),
          ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  SELECTION VIEW
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSelectionView() {
    List<String> filtered;
    if (_selectedRegion == 'All') {
      filtered = SymptomData.symptoms.keys.toList();
    } else {
      final cats = _regionCategories[_selectedRegion] ?? [];
      filtered = SymptomData.symptoms.entries
          .where((e) => cats.contains(e.value['category']))
          .map((e) => e.key).toList();
    }
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((k) {
        final label = (SymptomData.symptoms[k]!['label'] as String).toLowerCase();
        return label.contains(searchQuery.toLowerCase());
      }).toList();
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Column(children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  sliver: SliverList(delegate: SliverChildListDelegate([
                    _infoCard(),
                    const SizedBox(height: 14),
                    _searchBar(),
                    const SizedBox(height: 14),
                    _bodyRegionSelector(),
                    const SizedBox(height: 16),
                    _countRow(filtered.length),
                    const SizedBox(height: 12),
                  ])),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _symptomTile(filtered[i]),
                      childCount: filtered.length,
                    ),
                  ),
                ),
                if (selectedSymptoms.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    sliver: SliverList(delegate: SliverChildListDelegate([_selectedSummaryCard()])),
                  ),
                if (!_loadingHistory && recentChecks.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    sliver: SliverList(delegate: SliverChildListDelegate([_recentHistorySection()])),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
              ],
            ),
          ),
          _analyzeButton(),
        ]),
      ),
    );
  }

  Widget _infoCard() {
    return _glass(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFF00D9FF).withOpacity(0.3),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
            borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.medical_information_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(
          'Select symptoms you\'re experiencing. Tap a symptom to set its duration for more accurate analysis.',
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11, height: 1.5, fontWeight: FontWeight.w500),
        )),
      ]),
    );
  }

  Widget _searchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18))),
      child: Row(children: [
        Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5), size: 18),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => searchQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search symptoms...', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13)),
        )),
        if (searchQuery.isNotEmpty)
          GestureDetector(
            onTap: () { _searchCtrl.clear(); setState(() => searchQuery = ''); },
            child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5), size: 16)),
      ]),
    );
  }

  Widget _bodyRegionSelector() {
    return SizedBox(
      height: 80,
      child: Row(
        children: _regions.map((r) {
          final key = r['key'] as String;
          final sel = _selectedRegion == key;
          return Expanded(
            child: GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _selectedRegion = key); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: sel ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]) : null,
                  color: sel ? null : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? Colors.transparent : Colors.white.withOpacity(0.12)),
                  boxShadow: sel ? [BoxShadow(color: const Color(0xFF00D9FF).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(r['icon'] as IconData, color: sel ? Colors.white : Colors.white.withOpacity(0.5), size: 22),
                  const SizedBox(height: 6),
                  Text(r['label'] as String, style: TextStyle(
                    color: sel ? Colors.white : Colors.white.withOpacity(0.5),
                    fontSize: 9, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _countRow(int total) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(_selectedRegion == 'All' ? 'All Symptoms' : '$_selectedRegion Symptoms',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      Row(children: [
        Text('$total available', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11, fontWeight: FontWeight.w600)),
        if (selectedSymptoms.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${selectedSymptoms.length} selected', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    ]);
  }

  Widget _symptomTile(String key) {
    final symptom = SymptomData.symptoms[key]!;
    final isSelected = selectedSymptoms.contains(key);
    final color = Color(symptom['color'] as int);
    final isEmerg = symptom['emergency'] == true;
    final duration = symptomDurations[key];

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (isSelected) { selectedSymptoms.remove(key); symptomDurations.remove(key); }
          else { selectedSymptoms.add(key); symptomDurations[key] = 'Just now'; }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isSelected
              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.22), color.withOpacity(0.08)])
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 1.5 : 1),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 5))] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withOpacity(isSelected ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(11)),
              child: Icon(_icon(symptom['icon'] as String), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(symptom['label'] as String, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: isSelected ? color : Colors.white.withOpacity(0.88))),
              Text(symptom['category'] as String, style: TextStyle(
                fontSize: 9, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
            ])),
            if (isEmerg && !isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.15), borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B6B), size: 10),
                  SizedBox(width: 3),
                  Text('Urgent', style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 8, fontWeight: FontWeight.w800)),
                ]),
              ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
              ),
          ]),
          if (isSelected) ...[
            const SizedBox(height: 10),
            Row(children: _durationLabels.map((d) {
              final sel = duration == d;
              return Expanded(
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => symptomDurations[key] = d); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? color.withOpacity(0.3) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sel ? color.withOpacity(0.6) : Colors.white.withOpacity(0.1))),
                    child: Text(d, textAlign: TextAlign.center, style: TextStyle(
                      color: sel ? color : Colors.white.withOpacity(0.5),
                      fontSize: 8, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                  ),
                ),
              );
            }).toList()),
          ],
        ]),
      ),
    );
  }

  Widget _selectedSummaryCard() {
    return _glass(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 8),
          Text('Selected (${selectedSymptoms.length})', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: selectedSymptoms.map((key) {
          final s = SymptomData.symptoms[key]!;
          final c = Color(s['color'] as int);
          final dur = symptomDurations[key] ?? '';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icon(s['icon'] as String), color: c, size: 12), const SizedBox(width: 4),
              Text(s['label'] as String, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
              if (dur.isNotEmpty) ...[
                Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: Colors.white.withOpacity(0.15)),
                Text(dur, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.w600)),
              ],
            ]),
          );
        }).toList()),
      ]),
    );
  }

  Widget _recentHistorySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9D84B7), Color(0xFF7B2CBF)]),
            borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.history_rounded, color: Colors.white, size: 14)),
        const SizedBox(width: 8),
        const Text('Recent Checks', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 10),
      ...recentChecks.take(3).map((c) {
        final symptoms = (c['symptoms'] as List?)?.cast<String>() ?? [];
        final pct = c['topMatchPercentage'] ?? 0;
        final emergency = c['isEmergency'] == true;
        final conditions = (c['matchedConditions'] as List?)?.cast<String>() ?? [];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(13),
            border: Border.all(color: emergency ? const Color(0xFFFF6B6B).withOpacity(0.3) : Colors.white.withOpacity(0.1))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: emergency ? const Color(0xFFFF6B6B).withOpacity(0.15) : const Color(0xFF4ECCA3).withOpacity(0.12),
                borderRadius: BorderRadius.circular(9)),
              child: Icon(emergency ? Icons.warning_rounded : Icons.check_circle_rounded,
                color: emergency ? const Color(0xFFFF6B6B) : const Color(0xFF4ECCA3), size: 14)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(conditions.isNotEmpty ? conditions.first : '${symptoms.length} symptoms checked',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${symptoms.length} symptoms • $pct% match',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w500)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (pct >= 70 ? const Color(0xFFFF6B6B) : pct >= 40 ? const Color(0xFFFFC857) : const Color(0xFF4ECCA3)).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
              child: Text('$pct%', style: TextStyle(
                color: pct >= 70 ? const Color(0xFFFF6B6B) : pct >= 40 ? const Color(0xFFFFC857) : const Color(0xFF4ECCA3),
                fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ]),
        );
      }),
    ]);
  }

  Widget _analyzeButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [const Color(0xFF0A0E21).withOpacity(0.0), const Color(0xFF0A0E21)])),
      child: GestureDetector(
        onTap: _analyzeSymptoms,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            gradient: selectedSymptoms.isNotEmpty
                ? const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]) : null,
            color: selectedSymptoms.isEmpty ? Colors.white.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(17),
            boxShadow: selectedSymptoms.isNotEmpty
                ? [BoxShadow(color: const Color(0xFF00D9FF).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))] : []),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.biotech_rounded,
              color: selectedSymptoms.isNotEmpty ? Colors.white : Colors.white.withOpacity(0.4), size: 20),
            const SizedBox(width: 10),
            Text(
              selectedSymptoms.isEmpty ? 'Select symptoms to analyse'
                  : 'Analyse ${selectedSymptoms.length} Symptom${selectedSymptoms.length > 1 ? 's' : ''}',
              style: TextStyle(
                color: selectedSymptoms.isNotEmpty ? Colors.white : Colors.white.withOpacity(0.4),
                fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  ANALYZING VIEW
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildAnalyzingView() {
    return Center(
      key: const ValueKey('analyzing'),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          width: 130, height: 130,
          child: AnimatedBuilder(
            animation: _analyzeCtrl,
            builder: (_, __) => Stack(alignment: Alignment.center, children: [
              Transform.rotate(angle: _analyzeCtrl.value * math.pi * 2,
                child: Container(width: 130, height: 130,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00D9FF).withOpacity(0.3), width: 3)))),
              Transform.rotate(angle: -_analyzeCtrl.value * math.pi * 2 * 0.7,
                child: Container(width: 100, height: 100,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7B2CBF).withOpacity(0.3), width: 2)))),
              Container(width: 70, height: 70,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF00D9FF).withOpacity(0.4), blurRadius: 20, spreadRadius: 3)]),
                child: const Icon(Icons.biotech_rounded, color: Colors.white, size: 30)),
            ]),
          ),
        ),
        const SizedBox(height: 30),
        const Text('Analyzing Symptoms...', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 10),
        Text('Matching ${selectedSymptoms.length} symptoms against medical database',
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text('Duration data enhances accuracy', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 30),
        SizedBox(width: 200, child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF00D9FF))))),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  RESULTS VIEW
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildResultsView() {
    return FadeTransition(
      opacity: _resultFade,
      child: CustomScrollView(
        key: const ValueKey('results'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
            sliver: SliverList(delegate: SliverChildListDelegate([
              _severityRingCard(),
              const SizedBox(height: 16),
              _selectedSymptomsResultCard(),
              const SizedBox(height: 16),
              if (matchedConditions.isNotEmpty) ...[
                _buildConditionsSection(),
                const SizedBox(height: 16),
              ],
              if (isEmergency) ...[_emergencyButton(), const SizedBox(height: 12)],
              _consultButton(),
              const SizedBox(height: 14),
              if (_isSaving)
                Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF2EC4B6)))),
                  const SizedBox(width: 8),
                  Text('Saving...', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w600)),
                ])),
              const SizedBox(height: 10),
              _disclaimerCard(),
            ])),
          ),
        ],
      ),
    );
  }

  Widget _severityRingCard() {
    final color = _severityColor;
    final label = _severityLabel;
    final isEmerg = label == 'EMERGENCY';

    return _glass(
      padding: const EdgeInsets.all(22),
      borderColor: color.withOpacity(0.4),
      child: Row(children: [
        SizedBox(
          width: 100, height: 100,
          child: AnimatedBuilder(
            animation: _ringAnim,
            builder: (_, __) => Stack(alignment: Alignment.center, children: [
              CustomPaint(size: const Size(100, 100),
                painter: _SeverityArcPainter(progress: _severityScore * _ringAnim.value, color: color)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(isEmerg ? Icons.emergency_rounded
                    : label == 'SEVERE' ? Icons.error_rounded
                    : label == 'MODERATE' ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded, color: color, size: 24),
                const SizedBox(height: 2),
                Text('${(_severityScore * 100 * _ringAnim.value).toInt()}%',
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Severity Level', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5, height: 1)),
          const SizedBox(height: 8),
          Text(
            isEmerg ? 'Seek immediate medical attention!'
                : label == 'SEVERE' ? 'See a doctor soon'
                : label == 'MODERATE' ? 'Monitor symptoms closely'
                : 'Rest & self-care recommended',
            style: TextStyle(color: color.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w600, height: 1.3)),
          if (matchedConditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(7)),
              child: Text('Top match: ${matchedConditions[0]['matchPercentage']}%',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ],
        ])),
      ]),
    );
  }

  Widget _selectedSymptomsResultCard() {
    return _glass(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 14)),
          const SizedBox(width: 8),
          Text('Your Symptoms (${selectedSymptoms.length})', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: selectedSymptoms.map((key) {
          final s = SymptomData.symptoms[key]!;
          final c = Color(s['color'] as int);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icon(s['icon'] as String), color: c, size: 12), const SizedBox(width: 4),
              Text(s['label'] as String, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          );
        }).toList()),
      ]),
    );
  }

  Widget _buildConditionsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF9D84B7)]),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
          child: const Icon(Icons.biotech_rounded, color: Colors.white, size: 14)),
        const SizedBox(width: 8),
        const Text('Possible Conditions', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF7B2CBF).withOpacity(0.2), borderRadius: BorderRadius.circular(7)),
          child: const Text('AI Analysis', style: TextStyle(color: Color(0xFF9D84B7), fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 12),
      ...matchedConditions.take(4).toList().asMap().entries.map((e) => _conditionCard(e.key, e.value)),
    ]);
  }

  Widget _conditionCard(int index, Map<String, dynamic> cond) {
    final pct = cond['matchPercentage'] as int;
    final color = pct >= 70 ? const Color(0xFFFF6B6B) : pct >= 50 ? const Color(0xFFFFC857) : const Color(0xFF4ECCA3);
    final expanded = _expandedCards.contains(index);
    final recs = cond['recommendations'] as List;
    final urgency = cond['urgency'] as String;

    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); setState(() { expanded ? _expandedCards.remove(index) : _expandedCards.add(index); }); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: expanded ? color.withOpacity(0.4) : Colors.white.withOpacity(0.1), width: expanded ? 1.5 : 1),
          boxShadow: expanded ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 4))] : []),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 28, height: 28,
              decoration: BoxDecoration(
                gradient: index == 0
                    ? const LinearGradient(colors: [Color(0xFFFF9068), Color(0xFFFF6B6B)])
                    : LinearGradient(colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.1)]),
                shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cond['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(cond['description'] as String, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.4))),
              child: Text('$pct%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 4,
              backgroundColor: Colors.white.withOpacity(0.08), valueColor: AlwaysStoppedAnimation(color))),
          if (!expanded)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.3), size: 16),
                Text('  Tap for details', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w600)),
              ])),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 14),
              Container(height: 1, color: Colors.white.withOpacity(0.08)),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: color.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.speed_rounded, color: color, size: 12), const SizedBox(width: 4),
                    Text(cond['severity'] as String, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text('${cond['matchedSymptoms']} of ${(cond['matchingSymptoms'] as List).length} symptoms matched',
                  style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 9, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 14),
              const Text('Recommendations', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...recs.asMap().entries.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 20, height: 20, margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]),
                      borderRadius: BorderRadius.circular(6)),
                    child: Center(child: Text('${r.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.value as String, style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600, height: 1.4))),
                ]),
              )),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC857).withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFC857).withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, color: Color(0xFFFFC857), size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(urgency, style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w600, height: 1.3))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _emergencyButton() {
    return GestureDetector(
      onTap: () { HapticFeedback.heavyImpact(); _showSnack('Call 108 or 102 immediately for emergency services', const Color(0xFFFF6B6B)); },
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE63946), Color(0xFFFF6B6B)]),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [BoxShadow(color: const Color(0xFFE63946).withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 8))]),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.local_hospital_rounded, color: Colors.white, size: 20), SizedBox(width: 10),
          Text('CALL EMERGENCY  108 / 102', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  Widget _consultButton() {
    return GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); _showSnack('Doctor consultation feature coming soon!', const Color(0xFF00D9FF)); },
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF7B2CBF)]),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [BoxShadow(color: const Color(0xFF00D9FF).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))]),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.medical_services_rounded, color: Colors.white, size: 20), SizedBox(width: 10),
          Text('Consult a Doctor', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ]),
      ),
    );
  }

  Widget _disclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.1))),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.4), size: 15),
        const SizedBox(width: 9),
        Expanded(child: Text(
          'Not a medical diagnosis. Always consult a qualified healthcare professional for medical advice.',
          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, height: 1.5, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _glass({required Widget child, EdgeInsets? padding, Color? borderColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.05)]),
            border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.15), width: 1.2)),
          child: child,
        ),
      ),
    );
  }
}

