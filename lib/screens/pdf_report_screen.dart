import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:math' as math;

class PdfReportScreen extends StatefulWidget {
  const PdfReportScreen({Key? key}) : super(key: key);

  @override
  State<PdfReportScreen> createState() => _PdfReportScreenState();
}

class _PdfReportScreenState extends State<PdfReportScreen> with TickerProviderStateMixin {
  late AnimationController _animCtrl;
  late AnimationController _staggerCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _staggerAnims;

  String selectedPeriod = 'weekly';
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  bool isGenerating = false;
  Map<String, dynamic> reportData = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _staggerAnims = List.generate(8, (i) {
      final s = (i * 0.09).clamp(0.0, 0.7);
      final e = (s + 0.28).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _staggerCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });

    _animCtrl.forward();
    _staggerCtrl.forward();
    _loadReportData();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ALL DATA LOGIC — UNTOUCHED
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _loadReportData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final moodLogs = await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('mood_logs')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate)).get();
      final sleepLogs = await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('sleep_logs')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate)).get();
      final waterLogs = await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('water_logs')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate)).get();
      final activityLogs = await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('activity_logs')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate)).get();
      final healthScores = await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .collection('health_scores').get();

      setState(() {
        reportData = {
          'moodLogs': moodLogs.docs,
          'sleepLogs': sleepLogs.docs,
          'waterLogs': waterLogs.docs,
          'activityLogs': activityLogs.docs,
          'healthScores': healthScores.docs,
          'totalDays': endDate.difference(startDate).inDays,
        };
      });
    } catch (e) { debugPrint('Error loading report data: $e'); }
  }

  Future<void> _generatePdf() async {
    setState(() => isGenerating = true);
    HapticFeedback.mediumImpact();
    try {
      final pdf = pw.Document();
      final user = FirebaseAuth.instance.currentUser;
      final moodCount = reportData['moodLogs']?.length ?? 0;
      final sleepCount = reportData['sleepLogs']?.length ?? 0;
      final waterCount = reportData['waterLogs']?.length ?? 0;
      final activityCount = reportData['activityLogs']?.length ?? 0;
      final totalDays = reportData['totalDays'] ?? 7;

      double avgSleep = 0;
      if (sleepCount > 0) {
        double totalSleep = 0;
        for (var log in reportData['sleepLogs'] as List) { totalSleep += (log.data()?['hours'] ?? 0).toDouble(); }
        avgSleep = totalSleep / sleepCount;
      }
      double avgWater = 0;
      if (waterCount > 0) {
        double totalWater = 0;
        for (var log in reportData['waterLogs'] as List) { totalWater += (log.data()?['glasses'] ?? 0).toDouble(); }
        avgWater = totalWater / waterCount;
      }

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(colors: [PdfColor.fromInt(0xFF2EC4B6), PdfColor.fromInt(0xFF4ECCA3)]),
                borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Healthify', style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  pw.SizedBox(height: 4),
                  pw.Text('Health Report', style: const pw.TextStyle(fontSize: 16, color: PdfColors.white)),
                ]),
                pw.Container(width: 60, height: 60,
                  decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(30)),
                  child: pw.Center(child: pw.Icon(const pw.IconData(0xe87e), color: const PdfColor.fromInt(0xFF2EC4B6), size: 32))),
              ])),
            pw.SizedBox(height: 24),
            pw.Container(padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF5F5F5), borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Report Period', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text('${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Generated', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text(DateFormat('MMM dd, yyyy').format(DateTime.now()), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ]),
              ])),
            pw.SizedBox(height: 24),
            pw.Text('Activity Summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0A0E21))),
            pw.SizedBox(height: 16),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _buildPdfStatCard('Mood Logs', moodCount.toString(), 'entries', const PdfColor.fromInt(0xFFFFC857)),
              _buildPdfStatCard('Sleep Logs', sleepCount.toString(), 'nights', const PdfColor.fromInt(0xFF9D84B7)),
            ]),
            pw.SizedBox(height: 12),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              _buildPdfStatCard('Water Intake', waterCount.toString(), 'logs', const PdfColor.fromInt(0xFF2EC4B6)),
              _buildPdfStatCard('Activities', activityCount.toString(), 'sessions', const PdfColor.fromInt(0xFF4ECCA3)),
            ]),
            pw.SizedBox(height: 24),
            pw.Text('Daily Averages', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0A0E21))),
            pw.SizedBox(height: 16),
            _buildPdfProgressBar('Average Sleep', '${avgSleep.toStringAsFixed(1)} hrs', avgSleep / 8, const PdfColor.fromInt(0xFF9D84B7)),
            pw.SizedBox(height: 12),
            _buildPdfProgressBar('Average Water', '${avgWater.toStringAsFixed(1)} glasses', avgWater / 8, const PdfColor.fromInt(0xFF2EC4B6)),
            pw.SizedBox(height: 12),
            _buildPdfProgressBar('Activity Rate', '${((activityCount / totalDays) * 100).toStringAsFixed(0)}%', activityCount / totalDays, const PdfColor.fromInt(0xFF4ECCA3)),
            pw.Spacer(),
            pw.Container(padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF5F5F5), borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Row(children: [
                  pw.Icon(const pw.IconData(0xe88f), size: 16, color: const PdfColor.fromInt(0xFF2EC4B6)),
                  pw.SizedBox(width: 8),
                  pw.Text('Important Note', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.SizedBox(height: 8),
                pw.Text('This report is generated based on your logged data and AI analysis. It is not a medical diagnosis. Please consult with a healthcare professional for medical advice.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, lineSpacing: 1.5)),
              ])),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('Generated by Healthify • Your Intelligent Health Companion', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600))),
          ]);
        },
      ));

      // await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
      setState(() => isGenerating = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white, size: 18), SizedBox(width: 10), Text('PDF generated successfully!')]),
        backgroundColor: const Color(0xFF4ECCA3), behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      setState(() => isGenerating = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error generating PDF: $e'), backgroundColor: const Color(0xFFFF6B6B),
        behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  pw.Widget _buildPdfStatCard(String label, String value, String unit, PdfColor color) {
    return pw.Container(width: 120, padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: PdfColor(color.red, color.green, color.blue, 0.1), borderRadius: pw.BorderRadius.circular(12), border: pw.Border.all(color: color, width: 2)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Text(value, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: color)),
        pw.SizedBox(height: 4),
        pw.Text(unit, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      ]));
  }

  pw.Widget _buildPdfProgressBar(String label, String value, double progress, PdfColor color) {
    return pw.Container(padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF5F5F5), borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, color: color, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 8),
        pw.Stack(children: [
          pw.Container(height: 8, decoration: pw.BoxDecoration(color: PdfColors.grey300, borderRadius: pw.BorderRadius.circular(4))),
          pw.Container(height: 8, width: 250 * progress.clamp(0.0, 1.0),
            decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(4))),
        ]),
      ]));
  }

  @override
  void dispose() { _animCtrl.dispose(); _staggerCtrl.dispose(); _pulseCtrl.dispose(); _shimmerCtrl.dispose(); super.dispose(); }

  Widget _staggerWrap(int index, Widget child) {
    final idx = index.clamp(0, _staggerAnims.length - 1);
    return AnimatedBuilder(
      animation: _staggerAnims[idx],
      builder: (_, __) => Opacity(
        opacity: _staggerAnims[idx].value,
        child: Transform.translate(offset: Offset(0, (1 - _staggerAnims[idx].value) * 22), child: child),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final moodCount = reportData['moodLogs']?.length ?? 0;
    final sleepCount = reportData['sleepLogs']?.length ?? 0;
    final waterCount = reportData['waterLogs']?.length ?? 0;
    final activityCount = reportData['activityLogs']?.length ?? 0;
    final totalEntries = moodCount + sleepCount + waterCount + activityCount;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(children: [
        // Animated ambient orbs
        Positioned(top: -80, right: -60, child: AnimatedBuilder(animation: _pulseAnim,
          builder: (_, __) => Container(width: 220 + _pulseAnim.value * 20, height: 220 + _pulseAnim.value * 20,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.08 + _pulseAnim.value * 0.03), Colors.transparent]))))),
        Positioned(bottom: 100, left: -80, child: AnimatedBuilder(animation: _pulseAnim,
          builder: (_, __) => Container(width: 200 + _pulseAnim.value * 15, height: 200 + _pulseAnim.value * 15,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [const Color(0xFF7B2CBF).withOpacity(0.06 + _pulseAnim.value * 0.02), Colors.transparent]))))),

        SafeArea(
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _staggerWrap(0, _buildHeroCard(totalEntries)),
                    const SizedBox(height: 22),
                    _staggerWrap(1, _buildSectionLabel('Report Period')),
                    const SizedBox(height: 10),
                    _staggerWrap(2, _buildPeriodSelector()),
                    const SizedBox(height: 14),
                    _staggerWrap(3, _buildDateRange()),
                    const SizedBox(height: 22),
                    _staggerWrap(4, _buildSectionLabel('Data Preview')),
                    const SizedBox(height: 10),
                    _staggerWrap(5, _buildDataGrid(moodCount, sleepCount, waterCount, activityCount)),
                    const SizedBox(height: 22),
                    _staggerWrap(6, _buildIncludesCard()),
                    const SizedBox(height: 26),
                    _staggerWrap(7, _buildGenerateButton()),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
          child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.10))),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Health Report', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text('Export & share your health data', style: TextStyle(fontSize: 12, color: const Color(0xFF2EC4B6).withOpacity(0.8), fontWeight: FontWeight.w600)),
        ])),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))]),
          child: const Icon(Icons.description_rounded, color: Colors.white, size: 20)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SECTION LABEL
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildSectionLabel(String title) {
    return Row(children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.65), letterSpacing: 0.2)),
      const SizedBox(width: 12),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.3), const Color(0xFF7B2CBF).withOpacity(0.12), Colors.transparent]),
        borderRadius: BorderRadius.circular(1)))),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HERO CARD
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHeroCard(int totalEntries) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [const Color(0xFF2EC4B6).withOpacity(0.15), const Color(0xFF7B2CBF).withOpacity(0.10)]),
            border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.25)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))]),
              child: const Icon(Icons.assessment_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Professional Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.2)),
              const SizedBox(height: 5),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECCA3).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.data_usage_rounded, color: Color(0xFF4ECCA3), size: 11),
                    const SizedBox(width: 4),
                    Text('$totalEntries entries', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF4ECCA3))),
                  ])),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9D84B7).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF9D84B7).withOpacity(0.3))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF9D84B7), size: 11),
                    SizedBox(width: 4),
                    Text('PDF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF9D84B7))),
                  ])),
              ]),
              const SizedBox(height: 5),
              Text('Share with your doctor or keep for records', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.42), fontWeight: FontWeight.w500)),
            ])),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PERIOD SELECTOR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildPeriodSelector() {
    return Row(children: [
      _buildPeriodChip('Weekly', 'weekly', Icons.calendar_view_week_rounded, 7),
      const SizedBox(width: 12),
      _buildPeriodChip('Monthly', 'monthly', Icons.calendar_month_rounded, 30),
    ]);
  }

  Widget _buildPeriodChip(String label, String value, IconData icon, int days) {
    final isSelected = selectedPeriod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            selectedPeriod = value;
            startDate = DateTime.now().subtract(Duration(days: days));
            endDate = DateTime.now();
          });
          _loadReportData();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: isSelected ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]) : null,
                color: isSelected ? null : Colors.white.withOpacity(0.06),
                border: Border.all(color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.10)),
                boxShadow: isSelected
                  ? [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.30), blurRadius: 16, offset: const Offset(0, 6))]
                  : []),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.white.withOpacity(0.45)),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.55))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATE RANGE
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildDateRange() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)]),
            border: Border.all(color: Colors.white.withOpacity(0.10))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: const Color(0xFF2EC4B6).withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.date_range_rounded, size: 16, color: const Color(0xFF2EC4B6).withOpacity(0.8))),
            const SizedBox(width: 12),
            Text(DateFormat('MMM dd').format(startDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(width: 20, height: 1, color: Colors.white.withOpacity(0.2))),
            Text(DateFormat('MMM dd, yyyy').format(endDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.18), const Color(0xFF2EC4B6).withOpacity(0.08)]),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.25))),
              child: Text('${endDate.difference(startDate).inDays} days',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF2EC4B6))),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA GRID — icon-based, no emojis
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildDataGrid(int mood, int sleep, int water, int activity) {
    final items = [
      {'icon': Icons.mood_rounded, 'label': 'Mood', 'count': mood, 'color': const Color(0xFFFFC857)},
      {'icon': Icons.bedtime_rounded, 'label': 'Sleep', 'count': sleep, 'color': const Color(0xFF9D84B7)},
      {'icon': Icons.water_drop_rounded, 'label': 'Water', 'count': water, 'color': const Color(0xFF2EC4B6)},
      {'icon': Icons.directions_run_rounded, 'label': 'Activity', 'count': activity, 'color': const Color(0xFF4ECCA3)},
    ];

    return Row(children: items.asMap().entries.map((e) {
      final i = e.key;
      final item = e.value;
      final color = item['color'] as Color;
      return Expanded(child: Padding(
        padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.12), color.withOpacity(0.04)]),
                border: Border.all(color: color.withOpacity(0.20))),
              child: Column(children: [
                Container(padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(item['icon'] as IconData, color: color, size: 18)),
                const SizedBox(height: 8),
                Text('${item['count']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1)),
                const SizedBox(height: 3),
                Text(item['label'] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.45))),
              ]),
            ),
          ),
        ),
      ));
    }).toList());
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INCLUDES CARD — checkmarks instead of emojis
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildIncludesCard() {
    final items = [
      {'icon': Icons.analytics_rounded, 'text': 'Activity summary & comprehensive stats', 'color': const Color(0xFF2EC4B6)},
      {'icon': Icons.trending_up_rounded, 'text': 'Daily averages & health trends', 'color': const Color(0xFF4ECCA3)},
      {'icon': Icons.psychology_rounded, 'text': 'AI-powered health insights', 'color': const Color(0xFF9D84B7)},
      {'icon': Icons.local_hospital_rounded, 'text': 'Doctor-ready professional format', 'color': const Color(0xFFFF6B6B)},
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)]),
            border: Border.all(color: Colors.white.withOpacity(0.10))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF9D84B7)]),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 15)),
              const SizedBox(width: 10),
              Text('Report Includes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.75))),
            ]),
            const SizedBox(height: 16),
            ...items.map((item) {
              final color = item['color'] as Color;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(width: 26, height: 26,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.25))),
                    child: Icon(item['icon'] as IconData, color: color, size: 14)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item['text'] as String,
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.60), fontWeight: FontWeight.w600))),
                ]),
              );
            }),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  GENERATE BUTTON
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildGenerateButton() {
    return GestureDetector(
      onTap: isGenerating ? null : _generatePdf,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isGenerating
              ? LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)])
              : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2EC4B6), Color(0xFF239B8F), Color(0xFF7B2CBF)]),
          boxShadow: isGenerating ? [] : [
            BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8)),
            BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 4))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isGenerating)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
          else
            Container(padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Text(isGenerating ? 'Generating Report...' : 'Generate PDF Report',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

