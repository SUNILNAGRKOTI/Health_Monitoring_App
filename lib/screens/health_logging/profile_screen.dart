// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../../services/auth_service.dart';
import '../auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────────
  late AnimationController _mainController;
  late AnimationController _statsController;
  late AnimationController _cardController;
  late AnimationController _shimmerController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _statsFadeAnim;
  late Animation<double> _cardFadeAnim;
  late List<Animation<double>> _cardScaleAnims;

  // ── Services ─────────────────────────────────────────────────────────────
  final AuthService _authService = AuthService();
  User? user;
  Map<String, dynamic>? userProfile;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isUploadingPhoto = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  String? _selectedGender;

  // ── Health data ───────────────────────────────────────────────────────────
  int currentStreak = 0;
  double healthScore = 0.0;
  int todayWaterGlasses = 0;
  double todaySleepHours = 0.0;
  int todaySteps = 0;

  final List<StreamSubscription> _subscriptions = [];
  final ImagePicker _picker = ImagePicker();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
  }

  void _setupAnimations() {
    _mainController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _statsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _cardController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _shimmerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _mainController, curve: Curves.easeOutCubic));
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _mainController, curve: Curves.easeOutCubic));
    _statsFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _statsController, curve: Curves.easeOutCubic));
    _cardFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic));

    // Staggered scale anims for settings items
    _cardScaleAnims = List.generate(4, (i) {
      final start = 0.1 + i * 0.18;
      final end = math.min(start + 0.35, 1.0);
      return Tween<double>(begin: 0.88, end: 1.0).animate(CurvedAnimation(
          parent: _cardController,
          curve: Interval(start, end, curve: Curves.elasticOut)));
    });
  }

  Future<void> _initializeData() async {
    await _loadUserData();
    _setupRealTimeListeners();
    if (mounted) {
      _mainController.forward();
      Future.delayed(const Duration(milliseconds: 250),
          () => mounted ? _statsController.forward() : null);
      Future.delayed(const Duration(milliseconds: 420),
          () => mounted ? _cardController.forward() : null);
    }
  }

  void _setupRealTimeListeners() {
    if (user == null) return;
    final today = _todayString();
    final ref =
        FirebaseFirestore.instance.collection('users').doc(user!.uid);

    _subscriptions.add(ref
        .collection('water_logs')
        .doc(today)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists) {
        setState(() => todayWaterGlasses = doc.data()?['glasses'] ?? 0);
      }
    }));
    _subscriptions.add(ref
        .collection('sleep_logs')
        .doc(today)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists) {
        setState(
            () => todaySleepHours = (doc.data()?['hours'] ?? 0.0).toDouble());
      }
    }));
    _subscriptions.add(ref
        .collection('activity_logs')
        .doc(today)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists) {
        setState(() => todaySteps = doc.data()?['steps'] ?? 0);
      }
    }));
  }

  String _todayString() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadUserData() async {
    try {
      user = _authService.currentUser;
      if (user != null) {
        userProfile = await _authService.getUserProfile();
        await _calcStats();
        if (userProfile != null && mounted) {
          _nameController.text = (userProfile!['name']?.toString().trim().isNotEmpty == true
              ? userProfile!['name'].toString().trim()
              : user!.displayName?.trim()) ?? '';
          final hp = userProfile!['healthProfile'] as Map<String, dynamic>?;
          if (hp != null) {
            _ageController.text = hp['age']?.toString() ?? '';
            _heightController.text = hp['height']?.toString() ?? '';
            _weightController.text = hp['weight']?.toString() ?? '';
            _selectedGender = hp['gender'];
          }
        }
      }
    } catch (e) {
      debugPrint('Load user error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calcStats() async {
    if (user == null) return;
    try {
      final ref =
          FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final now = DateTime.now();
      int streak = 0;
      double total = 0;
      for (int i = 0; i < 7; i++) {
        final d = now.subtract(Duration(days: i));
        final ds =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final futures = await Future.wait([
          ref.collection('water_logs').doc(ds).get(),
          ref.collection('sleep_logs').doc(ds).get(),
          ref.collection('activity_logs').doc(ds).get(),
        ]);
        final count = futures.where((d) => d.exists).length;
        if (count >= 2) {
          if (i == streak) streak++;
          total += count * 30.0;
        } else if (streak == i) {
          break;
        }
      }
      if (mounted) {
        setState(() {
          currentStreak = streak;
          healthScore = (total / (7 * 3 * 30) * 100).clamp(0, 100);
        });
      }
    } catch (_) {}
  }

  // ── Photo ────────────────────────────────────────────────────────────────
  void _showFullscreenPhoto() {
    final p = userProfile?['photoURL'] as String?;
    if (p == null || p.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          Center(
            child: InteractiveViewer(
              child: p.startsWith('data:image')
                  ? Image.memory(base64Decode(p.split(',')[1]))
                  : Image.network(p),
            ),
          ),
          Positioned(
            top: 48,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showPhotoPickerDialog() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoPickerSheet(
        onCamera: () => _pickPhoto(ImageSource.camera),
        onGallery: () => _pickPhoto(ImageSource.gallery),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final img = await _picker.pickImage(
          source: source,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 70);
      if (img == null) return;
      setState(() => _isUploadingPhoto = true);
      final bytes = await img.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .set({'photoURL': b64, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          userProfile = doc.data();
          _isUploadingPhoto = false;
        });
        _showSnack('✓ Photo updated!', const Color(0xFF4ECCA3));
      }
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
      _showSnack('Error: $e', const Color(0xFFFF6B6B));
    }
  }

  // ── Save profile ─────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    if (!_isEditing) return;
    try {
      if (user == null) throw Exception('Not authenticated');
      if (_nameController.text.trim().isNotEmpty) {
        await user!.updateDisplayName(_nameController.text.trim());
      }
      final data = {
        'uid': user!.uid,
        'email': user!.email,
        'name': _nameController.text.trim(),
        'healthProfile': {
          'age': int.tryParse(_ageController.text.trim()),
          'gender': _selectedGender,
          'height': double.tryParse(_heightController.text.trim()),
          'weight': double.tryParse(_weightController.text.trim()),
        },
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .set(data, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          userProfile = data;
          _isEditing = false;
        });
        _showSnack('✓ Profile saved!', const Color(0xFF4ECCA3));
        _loadUserData();
      }
    } catch (e) {
      _showSnack('Error: $e', const Color(0xFFFF6B6B));
    }
  }

  // ── Sign out ─────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Sign Out',
        message: 'Are you sure you want to sign out?',
        confirmLabel: 'Sign Out',
        confirmColor: const Color(0xFFFF6B6B),
      ),
    );
    if (confirmed == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (r) => false,
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SETTINGS BOTTOM SHEETS
  // ════════════════════════════════════════════════════════════════════════

  void _showAccountSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ThemedSheet(
        title: 'Account Settings',
        icon: Icons.manage_accounts_rounded,
        iconColor: const Color(0xFF00D9FF),
        children: [
          _sheetInfoTile(Icons.email_rounded, 'Email Address',
              user?.email ?? 'Not set', const Color(0xFF2EC4B6)),
          _sheetInfoTile(Icons.fingerprint_rounded, 'User ID',
              '${user?.uid.substring(0, 12)}...', const Color(0xFF9D84B7)),
          _sheetInfoTile(
              Icons.verified_user_rounded,
              'Account Status',
              user?.emailVerified == true ? 'Verified' : 'Not Verified',
              user?.emailVerified == true
                  ? const Color(0xFF4ECCA3)
                  : const Color(0xFFFFC857)),
          const SizedBox(height: 8),
          _sheetActionTile(
            Icons.edit_rounded,
            'Edit Profile',
            'Update your personal information',
            const Color(0xFF2EC4B6),
            () {
              Navigator.pop(context);
              setState(() => _isEditing = true);
            },
          ),
        ],
      ),
    );
  }

  void _showPrivacySecurity() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ThemedSheet(
        title: 'Privacy & Security',
        icon: Icons.security_rounded,
        iconColor: const Color(0xFF7B2CBF),
        children: [
          _sheetActionTile(
            Icons.lock_reset_rounded,
            'Change Password',
            'Send a password reset email',
            const Color(0xFF7B2CBF),
            () {
              Navigator.pop(context);
              _showChangePasswordDialog();
            },
          ),
          _sheetActionTile(
            Icons.privacy_tip_rounded,
            'Data Privacy',
            'Your data is encrypted & secure',
            const Color(0xFF9D84B7),
            () => Navigator.pop(context),
          ),
          _sheetActionTile(
            Icons.description_rounded,
            'View Privacy Policy',
            'Read our privacy policy',
            const Color(0xFF2EC4B6),
            () async {
              Navigator.pop(context);
              final policy = await DefaultAssetBundle.of(context).loadString('assets/privacy_policy.txt');
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF141830),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(children: [
                    const Icon(Icons.description_rounded, color: Color(0xFF2EC4B6)),
                    SizedBox(width: 10),
                    const Text('Privacy Policy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ]),
                  content: SizedBox(
                    width: 320,
                    child: SingleChildScrollView(
                      child: Text(policy, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(color: Color(0xFF2EC4B6), fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            },
          ),
          _sheetInfoTile(Icons.shield_rounded, 'Data Storage',
              'Firebase (Google Cloud)', const Color(0xFF4ECCA3)),
        ],
      ),
    );
    }

  void _showHelpSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ThemedSheet(
        title: 'Help & Support',
        icon: Icons.support_agent_rounded,
        iconColor: const Color(0xFFFF9068),
        children: [
          // Developer info card
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2EC4B6).withOpacity(0.15),
                  const Color(0xFF7B2CBF).withOpacity(0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF2EC4B6).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('SN',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sunil Nagarkoti',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text('Developer & Creator',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Phone
          _sheetActionTile(
            Icons.phone_rounded,
            'Call Support',
            '8650743567 • Tap to call',
            const Color(0xFF4ECCA3),
            () {
              Navigator.pop(context);
              _launchPhone('8650743567');
            },
          ),
          // Email — FIXED
          _sheetActionTile(
            Icons.email_rounded,
            'Email Support',
            'sunilsinghnagarkoti108@gmail.com',
            const Color(0xFF7B2CBF),
            () {
              Navigator.pop(context);
              _launchEmail('sunilsinghnagarkoti108@gmail.com');
            },
          ),
          // About
          _sheetActionTile(
            Icons.info_rounded,
            'About Healthify',
            'Version 1.0.0 • College Major Project',
            const Color(0xFFFF9068),
            () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
        ],
      ),
    );
  }

  // ── Email launch — FIXED ─────────────────────────────────────────────────
  Future<void> _launchEmail(String email) async {
    // Primary: use mailto with SENDTO action (most reliable on Android)
    final Uri mailtoUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Healthify App Support',
        'body': 'Hi Sunil,\n\nI need help with:\n\n',
      },
    );

    try {
      final launched =
          await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('Could not open email app');
    } catch (e) {
      debugPrint('Email launch error: $e');
      // Fallback: copy email + show instructions
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: email));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Email copied to clipboard!',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(email,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 11)),
              ],
            ),
            backgroundColor: const Color(0xFF7B2CBF),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(String phone) async {
    final Uri uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showSnack('Could not open dialer', const Color(0xFFFF6B6B));
    }
  }

  // ── Change password ───────────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Reset Password',
        message:
            'A password reset link will be sent to:\n\n${user?.email ?? 'No email'}',
        confirmLabel: 'Send Email',
        confirmColor: const Color(0xFF2EC4B6),
        onConfirm: () async {
          try {
            if (user?.email != null) {
              await FirebaseAuth.instance
                  .sendPasswordResetEmail(email: user!.email!);
              _showSnack(
                  '✓ Reset email sent to ${user!.email}', const Color(0xFF4ECCA3),
                  duration: 4);
            }
          } catch (e) {
            _showSnack('Failed: $e', const Color(0xFFFF6B6B));
          }
        },
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A1F3A).withOpacity(0.95),
                    const Color(0xFF0A0E21).withOpacity(0.95),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF2EC4B6).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8))
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text('Healthify',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Version 1.0.0',
                      style: TextStyle(
                          color: const Color(0xFF2EC4B6),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Text(
                    'AI-powered personal health companion.\nTrack, analyze & improve your wellness.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                        height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                              child: Text('SN',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13))),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sunil Nagarkoti',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                            Text('Developer • College Major Project',
                                style: TextStyle(
                                    color: Color(0xFF2EC4B6), fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Close',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMenuOptions() {
    HapticFeedback.lightImpact();
    setState(() => _isEditing = true);
  }

  // ── Shared snackbar helper ────────────────────────────────────────────────
  void _showSnack(String msg, Color color, {int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: Duration(seconds: duration),
    ));
  }

  String _getDisplayName() {
    if (_isEditing && _nameController.text.isNotEmpty) return _nameController.text;
    if (userProfile?['name']?.toString().isNotEmpty == true)
      return userProfile!['name'].toString();
    if (user?.displayName?.isNotEmpty == true) return user!.displayName!;
    return 'User';
  }

  @override
  void dispose() {
    _mainController.dispose();
    _statsController.dispose();
    _cardController.dispose();
    _shimmerController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: _isLoading ? _buildLoading() : _buildBody(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (_, __) => Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: const [Color(0xFF2EC4B6), Color(0xFF7B2CBF)],
                  transform:
                      GradientRotation(_shimmerController.value * 2 * math.pi),
                ),
              ),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 20),
          Text('Loading Profile...',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Stack(children: [
      // Ambient background blobs
      Positioned(top: -80, right: -60, child: Container(width: 240, height: 240,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2EC4B6).withOpacity(0.08)))),
      Positioned(bottom: 120, left: -70, child: Container(width: 200, height: 200,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7B2CBF).withOpacity(0.07)))),
      CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(position: _slideAnim, child: _buildProfileCard()),
                ),
                const SizedBox(height: 16),
                FadeTransition(opacity: _statsFadeAnim, child: _buildStatsRow()),
                const SizedBox(height: 16),
                FadeTransition(opacity: _statsFadeAnim, child: _buildTodayHealth()),
                const SizedBox(height: 16),
                if (_isEditing) ...[
                  FadeTransition(opacity: _fadeAnim, child: _buildEditForm()),
                  const SizedBox(height: 16),
                ],
                FadeTransition(opacity: _cardFadeAnim, child: _buildSettings()),
              ]),
            ),
          ),
        ],
      ),
    ]);
  }

  // ── Sliver App Bar ────────────────────────────────────────────────────────
  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0A0E21),
      elevation: 0,
      pinned: true,
      expandedHeight: 70,
      collapsedHeight: 65,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A0E21),
                const Color(0xFF1A1F3A).withOpacity(0.9),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('My Profile',
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2)),
                        Text(_isEditing ? 'Editing mode' : 'Your health profile',
                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (_isEditing) ...[
                    GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); setState(() => _isEditing = false); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () { HapticFeedback.mediumImpact(); _saveProfile(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF4ECCA3)]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_rounded, color: Colors.white, size: 14), SizedBox(width: 5),
                          Text('Save', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ] else
                    GestureDetector(
                      onTap: _showMenuOptions,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.edit_rounded, color: Colors.white, size: 14), SizedBox(width: 5),
                          Text('Edit', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Profile Card ──────────────────────────────────────────────────────────
  Widget _buildProfileCard() {
    final name = _getDisplayName();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final photo = userProfile?['photoURL'] as String?;
    final createdAt = userProfile?['createdAt'];
    String memberSince = 'New member';
    if (createdAt is Timestamp) {
      final d = createdAt.toDate();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      memberSince = 'Member since ${months[d.month - 1]} ${d.year}';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(0.13), Colors.white.withOpacity(0.06)]),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            Row(children: [
              // Avatar
              GestureDetector(
                onTap: photo != null ? _showFullscreenPhoto : null,
                child: Stack(children: [
                  Container(
                    width: 85, height: 85,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: photo != null && photo.isNotEmpty
                        ? Container(
                            decoration: BoxDecoration(shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF2EC4B6), width: 3)),
                            child: ClipOval(
                              child: photo.startsWith('data:image')
                                  ? Image.memory(base64Decode(photo.split(',')[1]), fit: BoxFit.cover, width: 85, height: 85,
                                      errorBuilder: (_, __, ___) => _avatar(letter, 85))
                                  : Image.network(photo, fit: BoxFit.cover, width: 85, height: 85,
                                      errorBuilder: (_, __, ___) => _avatar(letter, 85)),
                            ),
                          )
                        : _avatar(letter, 85),
                  ),
                  Positioned(bottom: 0, right: 0, child: GestureDetector(
                    onTap: _showPhotoPickerDialog,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF4ECCA3)]),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0A0E21), width: 2.5),
                        boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 3))]),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                    ),
                  )),
                  if (_isUploadingPhoto)
                    Positioned.fill(child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.65)),
                      child: const Center(child: SizedBox(width: 28, height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))),
                    )),
                ]),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(user?.email ?? '', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(memberSince, style: TextStyle(fontSize: 9, color: const Color(0xFF2EC4B6).withOpacity(0.8), fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  _badge('$currentStreak day streak', const Color(0xFFFF6B6B)),
                  const SizedBox(width: 6),
                  _badge('${healthScore.toInt()} pts', const Color(0xFF2EC4B6)),
                ]),
              ])),
            ]),
            // Quick BMI row (if data exists)
            if (userProfile?['healthProfile'] != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _profileQuickStat(Icons.cake_rounded, '${(userProfile!['healthProfile'] as Map<String, dynamic>?)?['age'] ?? '--'}', 'Age'),
                  _profileDivider(),
                  _profileQuickStat(Icons.straighten_rounded, '${(userProfile!['healthProfile'] as Map<String, dynamic>?)?['height'] ?? '--'}', 'cm'),
                  _profileDivider(),
                  _profileQuickStat(Icons.monitor_weight_rounded, '${(userProfile!['healthProfile'] as Map<String, dynamic>?)?['weight'] ?? '--'}', 'kg'),
                  _profileDivider(),
                  _profileQuickStat(Icons.person_rounded, '${(userProfile!['healthProfile'] as Map<String, dynamic>?)?['gender'] ?? '--'}', 'Gender'),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _profileQuickStat(IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, color: const Color(0xFF2EC4B6).withOpacity(0.7), size: 16),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, height: 1),
        maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _profileDivider() {
    return Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1));
  }

  Widget _avatar(String letter, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
        border: Border.all(color: const Color(0xFF2EC4B6), width: 3),
      ),
      child: Center(
        child: Text(letter,
            style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final hp = userProfile?['healthProfile'] as Map<String, dynamic>?;
    final stats = [
      {
        'label': 'Streak',
        'value': '$currentStreak',
        'unit': 'days',
        'icon': Icons.local_fire_department_rounded,
        'color': const Color(0xFFFF6B6B),
      },
      {
        'label': 'Health',
        'value': '${healthScore.toInt()}',
        'unit': 'score',
        'icon': Icons.favorite_rounded,
        'color': const Color(0xFF2EC4B6),
      },
      {
        'label': 'Weight',
        'value': hp?['weight']?.toString() ?? '--',
        'unit': 'kg',
        'icon': Icons.monitor_weight_rounded,
        'color': const Color(0xFF9D84B7),
      },
      {
        'label': 'Height',
        'value': hp?['height']?.toString() ?? '--',
        'unit': 'cm',
        'icon': Icons.height_rounded,
        'color': const Color(0xFF4ECCA3),
      },
    ];

    return Row(
      children: stats.asMap().entries.map((e) {
        final s = e.value;
        final color = s['color'] as Color;
        return Expanded(
          child: AnimatedBuilder(
            animation: _cardScaleAnims[e.key],
            builder: (_, __) => Transform.scale(
              scale: _cardScaleAnims[e.key].value,
              child: Container(
                margin: EdgeInsets.only(
                    left: e.key == 0 ? 0 : 6,
                    right: e.key == stats.length - 1 ? 0 : 6),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.18),
                      color.withOpacity(0.08),
                    ],
                  ),
                  border: Border.all(color: color.withOpacity(0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 5))
                  ],
                ),
                child: Column(
                  children: [
                    Icon(s['icon'] as IconData, color: color, size: 22),
                    const SizedBox(height: 6),
                    Text(s['value'] as String,
                        style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1)),
                    const SizedBox(height: 2),
                    Text(s['unit'] as String,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Today's Health ────────────────────────────────────────────────────────
  Widget _buildTodayHealth() {
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
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
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
                    child: const Icon(Icons.today_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text("Today's Health",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECCA3).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF4ECCA3).withOpacity(0.4)),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Color(0xFF4ECCA3),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                      child: _healthTile(Icons.water_drop_rounded, 'Water',
                          '$todayWaterGlasses/8 glasses',
                          todayWaterGlasses / 8, const Color(0xFF2EC4B6))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _healthTile(
                          Icons.bedtime_rounded,
                          'Sleep',
                          '${todaySleepHours.toStringAsFixed(1)}/8 hrs',
                          todaySleepHours / 8,
                          const Color(0xFF9D84B7))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _healthTile(
                          Icons.directions_walk_rounded,
                          'Steps',
                          '$todaySteps',
                          todaySteps / 10000,
                          const Color(0xFF4ECCA3))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _healthTile(IconData icon, String label, String value, double progress,
      Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 3.5,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ── Edit Form ─────────────────────────────────────────────────────────────
  Widget _buildEditForm() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2EC4B6).withOpacity(0.1),
                const Color(0xFF7B2CBF).withOpacity(0.08),
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
                          colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('Edit Profile',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 18),
              _formField('Full Name', _nameController, Icons.person_rounded,
                  const Color(0xFF2EC4B6)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _formField('Age', _ageController,
                          Icons.cake_rounded, const Color(0xFFFFC857),
                          keyboard: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _formField('Height (cm)', _heightController,
                          Icons.height_rounded, const Color(0xFF4ECCA3),
                          keyboard: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _formField('Weight (kg)', _weightController,
                          Icons.monitor_weight_rounded, const Color(0xFF9D84B7),
                          keyboard: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _genderDropdown()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formField(String hint, TextEditingController ctrl, IconData icon,
      Color color,
      {TextInputType keyboard = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.35), fontSize: 12),
          prefixIcon: Icon(icon, color: color, size: 18),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _genderDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFFF9068).withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender,
          hint: Text('Gender',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.35), fontSize: 12)),
          dropdownColor: const Color(0xFF1A1F3A),
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded,
              color: Color(0xFFFF9068), size: 18),
          items: ['Male', 'Female', 'Other'].map((g) {
            return DropdownMenuItem(
                value: g,
                child: Text(g,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)));
          }).toList(),
          onChanged: (v) => setState(() => _selectedGender = v),
        ),
      ),
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────
  Widget _buildSettings() {
    final items = [
      {
        'title': 'Account Settings',
        'subtitle': 'Email, ID & profile details',
        'icon': Icons.manage_accounts_rounded,
        'color': const Color(0xFF00D9FF),
        'onTap': _showAccountSettings,
        'destructive': false,
      },
      {
        'title': 'Privacy & Security',
        'subtitle': 'Password & data privacy',
        'icon': Icons.security_rounded,
        'color': const Color(0xFF7B2CBF),
        'onTap': _showPrivacySecurity,
        'destructive': false,
      },
      {
        'title': 'Help & Support',
        'subtitle': 'Contact developer • sunilsinghnagarkoti108@gmail.com',
        'icon': Icons.support_agent_rounded,
        'color': const Color(0xFFFF9068),
        'onTap': _showHelpSupport,
        'destructive': false,
      },
      {
        'title': 'Sign Out',
        'subtitle': 'Log out from your account',
        'icon': Icons.logout_rounded,
        'color': const Color(0xFFFF6B6B),
        'onTap': _signOut,
        'destructive': true,
      },
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border:
                Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final item = e.value;
              final isLast = e.key == items.length - 1;
              final color = item['color'] as Color;
              final isDestructive = item['destructive'] as bool;

              return Column(
                children: [
                  AnimatedBuilder(
                    animation: e.key < _cardScaleAnims.length
                        ? _cardScaleAnims[e.key]
                        : _cardFadeAnim,
                    builder: (_, __) => GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        (item['onTap'] as VoidCallback)();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: isLast
                              ? const BorderRadius.only(
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(20))
                              : BorderRadius.zero,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withOpacity(0.25),
                                    color.withOpacity(0.12),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color: color.withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: Icon(item['icon'] as IconData,
                                  color: color, size: 18),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['title'] as String,
                                      style: TextStyle(
                                          color: isDestructive
                                              ? const Color(0xFFFF6B6B)
                                              : Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(item['subtitle'] as String,
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.45),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white.withOpacity(0.5), size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isLast)
                    Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        color: Colors.white.withOpacity(0.08)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }


  // ── Sheet helper widgets ──────────────────────────────────────────────────
  Widget _sheetInfoTile(
      IconData icon, String title, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetActionTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: color.withOpacity(0.5), size: 14),
          ],
        ),
      ),
    );
  }
}

/// Themed bottom sheet used for all settings panels
class _ThemedSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _ThemedSheet({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1F3A).withOpacity(0.98),
                const Color(0xFF0A0E21).withOpacity(0.98),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
                top: BorderSide(
                    color: Colors.white.withOpacity(0.12), width: 1)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 14, bottom: 22),
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            iconColor,
                            iconColor.withOpacity(0.7)
                          ]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: iconColor.withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable confirm/alert dialog
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback? onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1F3A).withOpacity(0.97),
                  const Color(0xFF0A0E21).withOpacity(0.97),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withOpacity(0.15), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: confirmColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: confirmColor.withOpacity(0.4)),
                  ),
                  child: Icon(
                    confirmLabel == 'Sign Out'
                        ? Icons.logout_rounded
                        : Icons.email_rounded,
                    color: confirmColor,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 13,
                        height: 1.5)),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.15)),
                          ),
                          child: const Text('Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop(true);
                          onConfirm?.call();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              confirmColor,
                              confirmColor.withOpacity(0.8)
                            ]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: confirmColor.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4))
                            ],
                          ),
                          child: Text(confirmLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Photo picker bottom sheet
class _PhotoPickerSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _PhotoPickerSheet(
      {required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1F3A).withOpacity(0.98),
                const Color(0xFF0A0E21).withOpacity(0.98),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 14, bottom: 20),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Text('Update Photo',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                _pickerOption(context, Icons.camera_alt_rounded, 'Take Photo',
                    'Use your camera', const Color(0xFF2EC4B6), onCamera),
                const SizedBox(height: 10),
                _pickerOption(
                    context,
                    Icons.photo_library_rounded,
                    'Choose from Gallery',
                    'Pick an existing photo',
                    const Color(0xFF7B2CBF),
                    onGallery),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Text('Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerOption(BuildContext context, IconData icon, String title,
      String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [color, color.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

