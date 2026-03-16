import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import '../../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({Key? key}) : super(key: key);
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> with TickerProviderStateMixin {
  final NotificationService _notificationService = NotificationService();

  late AnimationController _fadeCtrl;
  late AnimationController _staggerCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _bellCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _staggerAnims;

  bool _isLoading = true;
  Map<String, bool> _reminderStates = {
    'water': false, 'sleep': false, 'morning': false, 'activity': false,
  };

  static const List<Map<String, dynamic>> _reminderData = [
    {
      'type': 'water', 'icon': Icons.water_drop_rounded, 'title': 'Hydration Reminder',
      'subtitle': 'Every 2 hours', 'schedule': '8 AM – 10 PM',
      'color': Color(0xFF00D9FF), 'gradColors': [Color(0xFF00D9FF), Color(0xFF0EA5E9)],
      'benefit': 'Boosts metabolism by 30%',
    },
    {
      'type': 'sleep', 'icon': Icons.bedtime_rounded, 'title': 'Sleep Reminder',
      'subtitle': 'Daily', 'schedule': '10:00 PM',
      'color': Color(0xFF9D84B7), 'gradColors': [Color(0xFF9D84B7), Color(0xFF7B2CBF)],
      'benefit': 'Improves memory consolidation',
    },
    {
      'type': 'morning', 'icon': Icons.wb_sunny_rounded, 'title': 'Morning Check-in',
      'subtitle': 'Daily', 'schedule': '8:00 AM',
      'color': Color(0xFFFFC857), 'gradColors': [Color(0xFFFFC857), Color(0xFFFF9F1C)],
      'benefit': 'Sets a positive daily tone',
    },
    {
      'type': 'activity', 'icon': Icons.directions_run_rounded, 'title': 'Activity Reminder',
      'subtitle': 'Daily', 'schedule': '6:00 PM',
      'color': Color(0xFF4ECCA3), 'gradColors': [Color(0xFF4ECCA3), Color(0xFF2EC4B6)],
      'benefit': 'Reduces heart disease risk 40%',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _bellCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _staggerAnims = List.generate(7, (i) {
      final s = (i * 0.10).clamp(0.0, 0.7);
      final e = (s + 0.30).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _staggerCtrl, curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });

    _initializeReminders();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose(); _staggerCtrl.dispose();
    _pulseCtrl.dispose(); _bellCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ALL LOGIC — COMPLETELY UNTOUCHED
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _initializeReminders() async {
    try {
      await _notificationService.initialize().timeout(const Duration(seconds: 5));
      final states = await _notificationService.getReminderStates().timeout(const Duration(seconds: 5));
      if (mounted) setState(() { _reminderStates = states; _isLoading = false; });
    } catch (e) {
      debugPrint("Reminder initialization error: $e");
      if (mounted) setState(() { _isLoading = false; });
    }
    _fadeCtrl.forward();
    _staggerCtrl.forward();
  }

  Future<void> _toggleReminder(String type, bool value) async {
    HapticFeedback.mediumImpact();
    if (value) {
      final hasPermission = await _notificationService.checkExactAlarmPermission();
      if (!hasPermission) { _showPermissionDialog(); return; }
    }
    setState(() { _reminderStates[type] = value; });
    try {
      if (value) {
        switch (type) {
          case 'water': await _notificationService.scheduleWaterReminders(); break;
          case 'sleep': await _notificationService.scheduleSleepReminder(); break;
          case 'morning': await _notificationService.scheduleMorningReminder(); break;
          case 'activity': await _notificationService.scheduleActivityReminder(); break;
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18), const SizedBox(width: 10),
            Text('${_getReminderTitle(type)} enabled!', style: const TextStyle(fontWeight: FontWeight.w600))]),
          backgroundColor: const Color(0xFF4ECCA3), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), duration: const Duration(seconds: 2)));
      } else {
        await _notificationService.cancelReminder(type);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_getReminderTitle(type)} disabled'), backgroundColor: Colors.white.withOpacity(0.15),
          behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      debugPrint("Toggle reminder error: $e");
      if (mounted) { setState(() { _reminderStates[type] = !value; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'),
          backgroundColor: const Color(0xFFFF6B6B), behavior: SnackBarBehavior.floating)); }
    }
  }

  void _showPermissionDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF141830),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF9068), Color(0xFFFF6B6B)]),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18)),
        const SizedBox(width: 12),
        const Text('Permission Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      ]),
      content: Text('This app needs permission to schedule exact alarms for reminders. Please enable it in settings.',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () { Navigator.pop(ctx); openAppSettings(); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(10)),
            child: const Text('Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
      ],
    ));
  }

  String _getReminderTitle(String type) {
    switch (type) { case 'water': return 'Hydration Reminder'; case 'sleep': return 'Sleep Reminder';
      case 'morning': return 'Morning Check-in'; case 'activity': return 'Activity Reminder'; default: return 'Reminder'; }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: _isLoading ? _buildLoading() : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF2EC4B6))));
  }

  Widget _staggerWrap(int index, Widget child) {
    final idx = index.clamp(0, _staggerAnims.length - 1);
    return AnimatedBuilder(
      animation: _staggerAnims[idx],
      builder: (_, __) => Opacity(
        opacity: _staggerAnims[idx].value,
        child: Transform.translate(offset: Offset(0, (1 - _staggerAnims[idx].value) * 24), child: child),
      ),
    );
  }

  Widget _buildContent() {
    final enabledCount = _reminderStates.values.where((v) => v).length;

    return Stack(children: [
      Positioned(top: -60, right: -40, child: AnimatedBuilder(animation: _pulseAnim,
        builder: (_, __) => Container(width: 200 + _pulseAnim.value * 20, height: 200 + _pulseAnim.value * 20,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.08 + _pulseAnim.value * 0.03), Colors.transparent]))))),
      Positioned(bottom: 80, left: -60, child: AnimatedBuilder(animation: _pulseAnim,
        builder: (_, __) => Container(width: 180 + _pulseAnim.value * 15, height: 180 + _pulseAnim.value * 15,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [const Color(0xFF7B2CBF).withOpacity(0.06 + _pulseAnim.value * 0.02), Colors.transparent]))))),

      SafeArea(child: Column(children: [
        _buildHeader(enabledCount),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _staggerWrap(0, _buildStatusCard(enabledCount)),
                const SizedBox(height: 20),
                _staggerWrap(1, _buildSectionLabel('Your Reminders', '$enabledCount active')),
                const SizedBox(height: 12),
                ..._reminderData.asMap().entries.map((e) =>
                  Padding(padding: const EdgeInsets.only(bottom: 12),
                    child: _staggerWrap(2 + e.key, _buildReminderCard(e.value)))),
                const SizedBox(height: 8),
                _staggerWrap(6, _buildPermissionCard()),
                const SizedBox(height: 12),
                _staggerWrap(6, _buildTestButton()),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      ])),
    ]);
  }

  Widget _buildHeader(int enabledCount) {
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
          const Text('Smart Reminders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text('$enabledCount of ${_reminderStates.length} active',
            style: TextStyle(fontSize: 12, color: const Color(0xFF4ECCA3).withOpacity(0.85), fontWeight: FontWeight.w600)),
        ])),
        AnimatedBuilder(
          animation: _bellCtrl,
          builder: (_, __) {
            final angle = math.sin(_bellCtrl.value * math.pi * 4) * 0.12;
            return Transform.rotate(
              angle: _bellCtrl.value < 0.5 ? angle : 0,
              child: Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))]),
                child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20)),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildStatusCard(int enabledCount) {
    final pct = enabledCount / _reminderStates.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [const Color(0xFF2EC4B6).withOpacity(0.14), const Color(0xFF7B2CBF).withOpacity(0.10)]),
            border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.22)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Row(children: [
            SizedBox(width: 68, height: 68,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 68, height: 68,
                  child: CircularProgressIndicator(
                    value: pct, strokeWidth: 6, strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation(pct == 1.0 ? const Color(0xFF4ECCA3) : const Color(0xFF2EC4B6)))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$enabledCount', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1)),
                  Text('/${_reminderStates.length}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                enabledCount == 0 ? 'No Reminders Active'
                : enabledCount == _reminderStates.length ? 'All Reminders Active'
                : 'Building Healthy Habits',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
              const SizedBox(height: 5),
              Text(
                enabledCount == 0 ? 'Enable reminders to stay on track with your health goals'
                : enabledCount == _reminderStates.length ? 'Great job! You\'ll never miss a health check-in'
                : '${_reminderStates.length - enabledCount} more to complete your routine',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.50), fontWeight: FontWeight.w500, height: 1.4)),
              if (enabledCount == _reminderStates.length) ...[
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF4ECCA3), Color(0xFF2EC4B6)]),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified_rounded, color: Colors.white, size: 12), SizedBox(width: 5),
                    Text('Fully Protected', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                  ])),
              ],
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title, String trailing) {
    return Row(children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.65), letterSpacing: 0.2)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF2EC4B6).withOpacity(0.3), Colors.transparent]),
        borderRadius: BorderRadius.circular(1)))),
      const SizedBox(width: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFF4ECCA3).withOpacity(0.12), borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.25))),
        child: Text(trailing, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF4ECCA3), letterSpacing: 0.4))),
    ]);
  }

  Widget _buildReminderCard(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final isEnabled = _reminderStates[type] ?? false;
    final color = data['color'] as Color;
    final gradColors = data['gradColors'] as List<Color>;
    final icon = data['icon'] as IconData;

    return GestureDetector(
      onTap: () => _toggleReminder(type, !isEnabled),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: isEnabled
                  ? [color.withOpacity(0.16), color.withOpacity(0.06)]
                  : [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.03)]),
              border: Border.all(color: isEnabled ? color.withOpacity(0.35) : Colors.white.withOpacity(0.08), width: 1.2),
              boxShadow: isEnabled
                ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 6))]
                : []),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: isEnabled ? LinearGradient(colors: gradColors) : null,
                  color: isEnabled ? null : Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isEnabled
                    ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))]
                    : []),
                child: Icon(icon, color: isEnabled ? Colors.white : Colors.white.withOpacity(0.4), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(data['title'] as String,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: isEnabled ? Colors.white : Colors.white.withOpacity(0.6))),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 12,
                    color: isEnabled ? color.withOpacity(0.9) : Colors.white.withOpacity(0.3)),
                  const SizedBox(width: 5),
                  Flexible(child: Text('${data['subtitle']} • ${data['schedule']}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: isEnabled ? color.withOpacity(0.85) : Colors.white.withOpacity(0.35)),
                    overflow: TextOverflow.ellipsis)),
                ]),
                if (isEnabled) ...[
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.18))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 10, color: color.withOpacity(0.8)),
                      const SizedBox(width: 4),
                      Flexible(child: Text(data['benefit'] as String,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color.withOpacity(0.8)),
                        overflow: TextOverflow.ellipsis)),
                    ])),
                ],
              ])),
              const SizedBox(width: 8),
              _buildToggle(isEnabled, color),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(bool isEnabled, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 52, height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: isEnabled ? LinearGradient(colors: [color, color.withOpacity(0.7)]) : null,
        color: isEnabled ? null : Colors.white.withOpacity(0.08),
        border: Border.all(color: isEnabled ? Colors.transparent : Colors.white.withOpacity(0.12)),
        boxShadow: isEnabled
          ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
          : []),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))]),
          child: isEnabled
            ? Icon(Icons.check_rounded, size: 14, color: color)
            : null,
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFFF9068).withOpacity(0.08),
            border: Border.all(color: const Color(0xFFFF9068).withOpacity(0.18))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF9068), Color(0xFFFF6B6B)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: const Color(0xFFFF9068).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
              child: const Icon(Icons.security_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notification Permission', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.85))),
              const SizedBox(height: 3),
              Text('Ensure notifications are enabled in your phone settings for reminders to work',
                style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.42), fontWeight: FontWeight.w500, height: 1.4)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); openAppSettings(); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF9068), Color(0xFFFF6B6B)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.2), blurRadius: 6)]),
                child: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTestButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        await _notificationService.sendTestNotification();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white, size: 18), SizedBox(width: 10),
            Text('Test notification sent!', style: TextStyle(fontWeight: FontWeight.w600))]),
          backgroundColor: const Color(0xFF4ECCA3), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), duration: const Duration(seconds: 3)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.10))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.notification_add_rounded, color: Colors.white.withOpacity(0.55), size: 16)),
              const SizedBox(width: 10),
              Text('Send Test Notification', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
