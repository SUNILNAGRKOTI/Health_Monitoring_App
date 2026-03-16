import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/app_logger.dart';
import 'dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _glowController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _glowAnimation;

  bool isLogin = true;
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _slideController.forward();
    });

    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('remember_me') ?? false;
    if (saved) {
      final email = prefs.getString('saved_email') ?? '';
      final password = prefs.getString('saved_password') ?? '';
      if (mounted) {
        setState(() {
          _rememberMe = true;
          _emailController.text = email;
          _passwordController.text = password;
        });
      }
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_email', _emailController.text.trim());
      await prefs.setString('saved_password', _passwordController.text);
    } else {
      await prefs.remove('remember_me');
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _glowController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════
  //  ALL LOGIC — COMPLETELY UNTOUCHED
  // ═════════════════════════════════════════════════════════════════════

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: isError ? const Color(0xFFE74C3C) : const Color(0xFF4ECCA3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        elevation: 8,
      ),
    );
  }

  bool _validateInputs() {
    if (_emailController.text.trim().isEmpty) {
      _showSnackBar('Please enter your email address', isError: true);
      return false;
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      _showSnackBar('Please enter a valid email address', isError: true);
      return false;
    }
    if (_passwordController.text.isEmpty) {
      _showSnackBar('Please enter your password', isError: true);
      return false;
    }
    if (!isLogin) {
      if (_nameController.text.trim().isEmpty) {
        _showSnackBar('Please enter your full name', isError: true);
        return false;
      }
      if (_passwordController.text.length < 6) {
        _showSnackBar('Password must be at least 6 characters long', isError: true);
        return false;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnackBar('Passwords do not match', isError: true);
        return false;
      }
    }
    return true;
  }

  void _handleAuth() async {
    if (!_validateInputs()) return;
    setState(() { isLoading = true; });
    HapticFeedback.lightImpact();

    try {
      Map<String, dynamic> result;
      if (isLogin) {
        result = await _authService.signInWithEmailPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        result = await _authService.signUpWithEmailPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
        );
      }

      if (!mounted) return;
      AppLogger.log('Auth completed');
      AppLogger.log('Success: ${result['success']}');
      AppLogger.log('Type: ${result['success'].runtimeType}');

      bool isSuccess = result['success'] == true || result['success'] == 'true';

      if (isSuccess) {
        String message = result['message'] ?? (isLogin ? 'Welcome back!' : 'Account created successfully!');
        _showSnackBar(message);
        HapticFeedback.selectionClick();

        if (isLogin) {
          await _saveCredentials();
          _clearAllFields();
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        } else {
          _clearAllFields();
          setState(() { isLogin = true; });
          _slideController.reset();
          _slideController.forward();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _showSnackBar('Account created successfully! Please sign in with your credentials');
          });
        }
      } else {
        String errorMessage = result['message'] ?? 'An error occurred. Please try again.';
        AppLogger.error('Auth error: $errorMessage');
        _showSnackBar(errorMessage, isError: true);
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (!mounted) return;
      AppLogger.error('Exception in _handleAuth: $e');
      _showSnackBar('Network error. Please check your connection and try again.', isError: true);
      HapticFeedback.heavyImpact();
    }

    if (mounted) setState(() { isLoading = false; });
  }

  void _clearAllFields() {
    _emailController.clear();
    _passwordController.clear();
    _nameController.clear();
    _confirmPasswordController.clear();
  }

  void _handleSocialLogin(String provider) async {
    if (provider == 'google') {
      setState(() { isLoading = true; });
      HapticFeedback.lightImpact();

      try {
        Map<String, dynamic> result = await _authService.signInWithGoogle();
        if (!mounted) return;

        final isSuccess = result['success'] == true;

        if (isSuccess) {
          _showSnackBar(result['message'] ?? 'Google sign-in successful!');
          HapticFeedback.selectionClick();
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        } else {
          _showSnackBar(result['message'] ?? 'Google sign-in failed. Please try again.', isError: true);
          HapticFeedback.heavyImpact();
        }
      } catch (e) {
        if (!mounted) return;
        AppLogger.error('Google sign-in exception: $e');
        String errorMsg = 'Google sign-in failed.';
        final eStr = e.toString().toLowerCase();
        if (eStr.contains('sign_in_failed') || eStr.contains('apiexception: 10')) {
          errorMsg = 'Google sign-in failed. Please check SHA-1 fingerprint in Firebase Console.';
        } else if (eStr.contains('network')) {
          errorMsg = 'Network error. Please check your internet connection.';
        } else if (eStr.contains('cancel')) {
          errorMsg = 'Google sign-in was cancelled.';
        }
        _showSnackBar(errorMsg, isError: true);
        HapticFeedback.heavyImpact();
      }

      if (mounted) setState(() { isLoading = false; });
    }
  }


  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141830),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          const Text('Reset Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Enter your email and we'll send a reset link.",
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55), height: 1.4)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12))),
            child: TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.email_rounded, color: Colors.white.withOpacity(0.4), size: 18),
                hintText: 'Email address',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () async {
              if (emailController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop();
                Map<String, dynamic> result = await _authService.resetPassword(emailController.text.trim());
                _showSnackBar(result['message'], isError: !result['success']);
              } else {
                _showSnackBar('Please enter your email address', isError: true);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(10)),
              child: const Text('Send Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  BUILD — DARK THEME REDESIGN
  // ═════════════════════════════════════════════════════════════════════
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
          // Breathing ambient orbs
          Positioned(top: -80, right: -60,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (_, __) => Container(
                width: 220 + _glowAnimation.value * 30,
                height: 220 + _glowAnimation.value * 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF2EC4B6).withOpacity(0.08 + _glowAnimation.value * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          Positioned(bottom: 120, left: -80,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (_, __) => Container(
                width: 200 + _glowAnimation.value * 20,
                height: 200 + _glowAnimation.value * 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF7B2CBF).withOpacity(0.06 + _glowAnimation.value * 0.03),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          Positioned(top: 200, left: 60,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (_, __) => Container(
                width: 120 + _glowAnimation.value * 15,
                height: 120 + _glowAnimation.value * 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF00D9FF).withOpacity(0.04 + _glowAnimation.value * 0.02),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(children: [
                        SizedBox(height: isLogin ? 50 : 30),
                        _buildHeader(),
                        const SizedBox(height: 36),
                        _buildFormCard(),
                        const SizedBox(height: 24),
                        _buildToggleSection(),
                        const SizedBox(height: 30),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Column(children: [
      // Logo
      AnimatedBuilder(
        animation: _glowAnimation,
        builder: (_, __) => Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2EC4B6).withOpacity(0.2 + _glowAnimation.value * 0.1),
                blurRadius: 25 + _glowAnimation.value * 8,
                offset: const Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.favorite_rounded, size: 36, color: Colors.white),
        ),
      ),
      const SizedBox(height: 28),
      // Title
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          isLogin ? 'Welcome Back' : 'Create Account',
          key: ValueKey(isLogin),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3),
        ),
      ),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          isLogin ? 'Sign in to continue your health journey' : 'Join thousands improving their health daily',
          key: ValueKey('sub_$isLogin'),
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w500, height: 1.4),
          textAlign: TextAlign.center,
        ),
      ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════
  //  FORM CARD — glassmorphic
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.05)]),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Name field (signup only)
            if (!isLogin) ...[
              _buildInputField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_rounded,
                keyboardType: TextInputType.name,
              ),
              const SizedBox(height: 18),
            ],

            // Email
            _buildInputField(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 18),

            // Password
            _buildInputField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_rounded,
              isPassword: true,
              obscureText: _obscurePassword,
              onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
            ),

            // Confirm password (signup only)
            if (!isLogin) ...[
              const SizedBox(height: 18),
              _buildInputField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_rounded,
                isPassword: true,
                obscureText: _obscureConfirmPassword,
                onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ],

            // Forgot password (login only)
            if (isLogin) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Remember Me
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: _rememberMe
                              ? const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)])
                              : null,
                          color: _rememberMe ? null : Colors.transparent,
                          border: Border.all(
                            color: _rememberMe ? Colors.transparent : Colors.white.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: _rememberMe
                            ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text('Remember me',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.5))),
                    ]),
                  ),
                  // Forgot Password
                  GestureDetector(
                    onTap: _showForgotPasswordDialog,
                    child: Text('Forgot Password?',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2EC4B6).withOpacity(0.8))),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Main button
            _buildMainButton(),

            const SizedBox(height: 24),

            // Divider
            Row(children: [
              Expanded(child: Container(height: 1, color: Colors.white.withOpacity(0.08))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('or continue with', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              Expanded(child: Container(height: 1, color: Colors.white.withOpacity(0.08))),
            ]),

            const SizedBox(height: 20),

            // Google button
            _buildGoogleButton(),
          ]),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  INPUT FIELD
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5), letterSpacing: 0.3)),
      const SizedBox(height: 8),
      Focus(
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(focused ? 0.09 : 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? const Color(0xFF2EC4B6).withOpacity(0.50)
                    : Colors.white.withOpacity(0.10),
                width: focused ? 1.5 : 1.0,
              ),
              boxShadow: focused
                  ? [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))]
                  : [],
            ),
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(icon, color: focused ? const Color(0xFF2EC4B6).withOpacity(0.75) : Colors.white.withOpacity(0.35), size: 18),
                ),
                suffixIcon: isPassword
                    ? IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.white.withOpacity(0.35), size: 18),
                        onPressed: onToggleVisibility)
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                hintText: 'Enter your ${label.toLowerCase()}',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13, fontWeight: FontWeight.w400),
              ),
            ),
          );
        }),
      ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════
  //  MAIN BUTTON
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildMainButton() {
    return GestureDetector(
      onTap: isLoading ? null : _handleAuth,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isLoading
              ? LinearGradient(colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.05)])
              : const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
          boxShadow: isLoading ? [] : [
            BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Text(
                  isLogin ? 'Sign In' : 'Create Account',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  GOOGLE BUTTON
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildGoogleButton() {
    return GestureDetector(
      onTap: isLoading ? null : () => _handleSocialLogin('google'),
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Google multi-color G icon
          SizedBox(
            width: 22, height: 22,
            child: CustomPaint(painter: _GoogleLogoPainter()),
          ),
          const SizedBox(width: 12),
          Text('Continue with Google',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }


  // ═════════════════════════════════════════════════════════════════════
  //  TOGGLE SECTION
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildToggleSection() {
    return GestureDetector(
      onTap: () {
        setState(() { isLogin = !isLogin; });
        _slideController.reset();
        _slideController.forward();
        HapticFeedback.selectionClick();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            isLogin ? "Don't have an account? " : "Already have an account? ",
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, fontWeight: FontWeight.w500),
          ),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]).createShader(r),
            child: Text(
              isLogin ? 'Sign Up' : 'Sign In',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.42;
    final strokeWidth = w * 0.18;

    // Blue arc (right)
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 4, math.pi / 2, false,
      Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt);
    // Green arc (bottom)
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi / 4, math.pi / 2, false,
      Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt);
    // Yellow arc (left-bottom)
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3 * math.pi / 4, math.pi / 2, false,
      Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt);
    // Red arc (top)
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3 * math.pi / 4, math.pi / 2, false,
      Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt);
    // Blue horizontal bar
    canvas.drawLine(Offset(w * 0.5, h * 0.40), Offset(w * 0.92, h * 0.40),
      Paint()..color = const Color(0xFF4285F4)..strokeWidth = strokeWidth..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF667eea).withOpacity(0.03)
      ..style = PaintingStyle.fill;

    const dotRadius = 1.5;
    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

