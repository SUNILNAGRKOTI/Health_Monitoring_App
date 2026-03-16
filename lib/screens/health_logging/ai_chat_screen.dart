import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import '/services/gemini_service.dart';
import '/services/app_logger.dart';

class AIChatScreen extends StatefulWidget {
  final bool embedded;
  const AIChatScreen({Key? key, this.embedded = false}) : super(key: key);
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin {
  // ── Animations ─────────────────────────────────────────────────────
  late AnimationController _animationController;
  late AnimationController _typingController;
  late AnimationController _pulseCtrl;
  late AnimationController _orbCtrl;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final FocusNode _messageFocusNode = FocusNode();

  final GeminiService _geminiService = GeminiService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isTyping = false;
  bool _isInitialized = false;
  File? _selectedImage;
  User? user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic> userHealthData = {};

  // ── Quick suggestion chips ─────────────────────────────────────────
  final List<Map<String, String>> _quickSuggestions = [
    {'emoji': '💧', 'label': 'Water tips', 'query': 'Give me tips to drink more water daily'},
    {'emoji': '😴', 'label': 'Sleep advice', 'query': 'How can I improve my sleep quality?'},
    {'emoji': '💪', 'label': 'Activity ideas', 'query': 'Suggest some easy exercises for beginners'},
    {'emoji': '😊', 'label': 'Mood boost', 'query': 'What can I do to improve my mood today?'},
    {'emoji': '🧘', 'label': 'Stress relief', 'query': 'Give me stress management techniques'},
  ];

  // ── Floating Orbs ──────────────────────────────────────────────────
  late List<_ChatOrb> _orbs;

  // ═════════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _initOrbs();
    _initializeAnimations();
    _initializeChat();
  }

  void _initOrbs() {
    final r = math.Random(42);
    _orbs = List.generate(4, (i) => _ChatOrb(
      Offset(r.nextDouble() * 400, r.nextDouble() * 800),
      50 + r.nextDouble() * 60,
      0.2 + r.nextDouble() * 0.35,
      r.nextDouble() * math.pi * 2,
      [const Color(0xFF7B2CBF), const Color(0xFF2EC4B6), const Color(0xFF00D9FF), const Color(0xFF9D84B7)][i],
    ));
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _typingController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _orbCtrl = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
  }

  // ═════════════════════════════════════════════════════════════════════
  //  DATA / API LOGIC — UNTOUCHED
  // ═════════════════════════════════════════════════════════════════════
  Future<void> _initializeChat() async {
    try {
      await _loadUserHealthData();
      _addWelcomeMessage();
      if (mounted) {
        _animationController.forward();
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      AppLogger.error('Error initializing chat: $e');
      if (mounted) setState(() => _isInitialized = true);
    }
  }

  Future<void> _loadUserHealthData() async {
    if (user == null) return;
    try {
      final today = DateTime.now();
      final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final userRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);

      final List<DocumentSnapshot> futures = await Future.wait([
        userRef.collection('mood_logs').doc(dateString).get(),
        userRef.collection('sleep_logs').doc(dateString).get(),
        userRef.collection('water_logs').doc(dateString).get(),
        userRef.collection('activity_logs').doc(dateString).get(),
      ]);

      Map<String, dynamic>? moodData;
      Map<String, dynamic>? sleepData;
      Map<String, dynamic>? waterData;
      Map<String, dynamic>? activityData;

      try { moodData = futures[0].exists ? (futures[0].data() as Map<String, dynamic>?) : null; } catch (e) { AppLogger.error('Error parsing mood data: $e'); }
      try { sleepData = futures[1].exists ? (futures[1].data() as Map<String, dynamic>?) : null; } catch (e) { AppLogger.error('Error parsing sleep data: $e'); }
      try { waterData = futures[2].exists ? (futures[2].data() as Map<String, dynamic>?) : null; } catch (e) { AppLogger.error('Error parsing water data: $e'); }
      try { activityData = futures[3].exists ? (futures[3].data() as Map<String, dynamic>?) : null; } catch (e) { AppLogger.error('Error parsing activity data: $e'); }

      final glassesVal = waterData?['glasses'];
      final int waterCount = glassesVal is num ? (glassesVal).toInt() : int.tryParse(glassesVal?.toString() ?? '') ?? 0;
      final dynamic sleepValue = sleepData?['hours'];
      final dynamic moodValue = moodData?['rating'];

      userHealthData = {
        'mood': moodValue,
        'sleep': sleepValue,
        'water': waterCount,
        'activity': activityData,
        'completedToday': _getCompletedCategories(futures),
      };
    } catch (e) {
      AppLogger.error('Error loading health data: $e');
      userHealthData = { 'mood': null, 'sleep': null, 'water': 0, 'activity': null, 'completedToday': <String>[] };
    }
  }

  List<String> _getCompletedCategories(List<DocumentSnapshot> futures) {
    final List<String> completed = [];
    try {
      if (futures[0].exists) completed.add('mood');
      if (futures[1].exists) completed.add('sleep');
      if (futures[2].exists) {
        try {
          final Map<String, dynamic>? data = futures[2].data() as Map<String, dynamic>?;
          final glassesVal = data?['glasses'];
          final int glassesCount = glassesVal is num ? (glassesVal).toInt() : int.tryParse(glassesVal?.toString() ?? '') ?? 0;
          if (glassesCount > 0) completed.add('water');
        } catch (e) { AppLogger.error('Error parsing water completion: $e'); }
      }
      if (futures[3].exists) completed.add('activity');
    } catch (e) { AppLogger.error('Error getting completed categories: $e'); }
    return completed;
  }

  void _addWelcomeMessage() {
    final welcomeMessage = ChatMessage(
      text: "Hi there! 👋 I'm your AI Health Coach. I can help you with wellness advice, answer health questions, and provide personalized recommendations based on your logged data. How can I assist you today?",
      isUser: false,
      timestamp: DateTime.now(),
    );
    if (mounted) setState(() => _messages.add(welcomeMessage));
  }

  void _sendMessage() async {
    if ((_messageController.text.trim().isEmpty && _selectedImage == null) || _isTyping) return;

    final messageText = _messageController.text.trim();
    final imageFile = _selectedImage;
    final userMessage = ChatMessage(
      text: messageText,
      isUser: true,
      timestamp: DateTime.now(),
      imagePath: imageFile?.path,
    );

    if (mounted) setState(() {
      _messages.add(userMessage);
      _isTyping = true;
      _selectedImage = null;
    });

    _messageController.clear();
    _messageFocusNode.unfocus();

    Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottomSmooth());
    _typingController.repeat();

    try {
      String aiResponse;
      if (imageFile != null) {
        // Use Gemini Vision for image + text
        aiResponse = await _geminiService.generateWithImage(
          userMessage: messageText,
          imageFile: imageFile,
          healthData: userHealthData,
        );
      } else {
        // Text only
        aiResponse = await _geminiService.generateHealthResponse(
          userMessage: messageText,
          healthData: userHealthData,
        );
      }
      final aiMessage = ChatMessage(text: aiResponse, isUser: false, timestamp: DateTime.now());
      if (mounted) {
        setState(() { _messages.add(aiMessage); _isTyping = false; });
        _typingController.stop();
        Future.delayed(const Duration(milliseconds: 200), () => _scrollToBottomSmooth());
      }
    } catch (e) {
      AppLogger.error('Error sending message: $e');
      final fallbackResponse = _generateFallbackResponse(messageText);
      final aiMessage = ChatMessage(text: fallbackResponse, isUser: false, timestamp: DateTime.now());
      if (mounted) {
        setState(() { _messages.add(aiMessage); _isTyping = false; });
        _typingController.stop();
        Future.delayed(const Duration(milliseconds: 200), () => _scrollToBottomSmooth());
      }
    }
  }

  void _scrollToBottomSmooth() {
    if (_scrollController.hasClients && mounted) {
      try {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } catch (e) { AppLogger.error('Error scrolling: $e'); }
    }
  }

  String _generateFallbackResponse(String userInput) {
    try {
      final input = userInput.toLowerCase();
      final completedCategories = userHealthData['completedToday'] as List<String>? ?? [];
      final waterCount = userHealthData['water'] as int? ?? 0;
      final mood = userHealthData['mood'];
      final sleep = userHealthData['sleep'];
      final activity = userHealthData['activity'];

      if (input.contains(RegExp(r'\b(hi|hello|hey|good morning|good afternoon|good evening)\b'))) {
        return "Hello! 👋 I'm here to help you on your wellness journey. Based on your data today, you've completed ${completedCategories.length}/4 health categories. What would you like to know about?";
      }
      if (input.contains(RegExp(r'\b(water|hydration|drink|thirsty)\b'))) {
        if (waterCount >= 8) return "Excellent! 💧 You've reached your daily water goal of 8 glasses. Keep up the great hydration!";
        else if (waterCount >= 4) return "Good progress on hydration! 👍 You've logged $waterCount glasses today. Try to reach 8 glasses for optimal hydration.";
        else return "I notice you've only logged $waterCount glasses of water today. Staying hydrated is crucial! 💦 Aim for 8 glasses throughout the day.";
      }
      if (input.contains(RegExp(r'\b(sleep|tired|exhausted|insomnia|rest)\b'))) {
        if (sleep != null) {
          final num? sleepNum = sleep is num ? sleep as num : num.tryParse(sleep.toString());
          if (sleepNum != null && sleepNum >= 7 && sleepNum <= 9) return "Great job! 😴 You logged ${sleepNum}h of sleep, which is in the optimal range of 7-9 hours.";
          else if (sleepNum != null && sleepNum < 7) return "I see you only got ${sleepNum}h of sleep. 😴 Most adults need 7-9 hours for optimal health.";
          else return "You logged ${sleep}h of sleep. Consider evaluating your sleep quality and habits.";
        } else return "I notice you haven't logged your sleep yet today. Quality sleep is fundamental! 🌙 Aim for 7-9 hours nightly.";
      }
      if (input.contains(RegExp(r'\b(mood|feeling|emotions|sad|happy|stressed|anxious)\b'))) {
        if (mood != null) {
          final int? moodInt = mood is num ? (mood as num).toInt() : int.tryParse(mood.toString());
          if (moodInt != null && moodInt >= 4) return "I'm glad to see you're feeling positive today! 😊 Keep doing whatever is working for you!";
          else if (moodInt == 3) return "You're feeling okay today, which is normal. 😌 Consider some light exercise or spending time in nature.";
          else return "I notice you're not feeling your best today. It's okay to have difficult days. 💙 Your mental health matters.";
        } else return "I don't see a mood entry for today yet. Tracking your emotions can help! How are you feeling? 😊";
      }
      if (input.contains(RegExp(r'\b(exercise|activity|workout|fitness|walk|run|gym)\b'))) {
        if (activity != null && activity is Map<String, dynamic>) {
          final activityType = activity['activity']?.toString() ?? 'activity';
          final durationVal = activity['duration'];
          final int duration = durationVal is num ? durationVal.toInt() : int.tryParse(durationVal?.toString() ?? '') ?? 0;
          return "Awesome! 💪 I see you did $activityType for ${duration} minutes today. Keep up the great work!";
        } else return "I don't see any activity logged today yet. Even 15-30 minutes of movement can make a huge difference! 🏃";
      }
      if (input.contains(RegExp(r'\b(motivation|encourage|help|support)\b'))) {
        final completionPercentage = (completedCategories.length / 4 * 100).toInt();
        return "You're doing great! 🌟 You've completed $completionPercentage% of your health tracking today. Keep it up!";
      }
      return "I'm here to help with your health journey! Ask me about sleep, water, mood, or activity. 😊";
    } catch (e) {
      AppLogger.error('Error generating fallback response: $e');
      return "I'm here to help! What would you like to know about your health? 😊";
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _typingController.dispose();
    _pulseCtrl.dispose();
    _orbCtrl.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        // Floating orbs background
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _orbCtrl,
            builder: (_, __) => CustomPaint(
                painter: _ChatOrbPainter(_orbCtrl.value * math.pi * 2, _orbs)),
          ),
        ),
        // Main content
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(children: [
                _buildHeader(),
                if (_messages.length <= 1 && !_isTyping) _buildQuickSuggestions(),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _messageFocusNode.unfocus(),
                    child: _buildChatArea(),
                  ),
                ),
                _buildInputArea(),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  HEADER — with pulsing glow
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1)),
      ),
      child: Row(children: [
        // Back button (hidden when embedded in dashboard tab)
        if (!widget.embedded) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.14))),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
        ],
        // AI Icon with pulsing glow
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [BoxShadow(
                  color: const Color(0xFF7B2CBF).withOpacity(0.2 + _pulseCtrl.value * 0.25),
                  blurRadius: 12 + _pulseCtrl.value * 8,
                  offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        // Title
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Health Coach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4ECCA3),
                      boxShadow: [BoxShadow(color: const Color(0xFF4ECCA3).withOpacity(0.5), blurRadius: 4)])),
              const SizedBox(width: 5),
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]).createShader(r),
                child: const Text('Powered by Healthify AI', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF4ECCA3).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4ECCA3).withOpacity(0.3))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, color: Color(0xFF4ECCA3), size: 6),
            SizedBox(width: 4),
            Text('Online', style: TextStyle(color: Color(0xFF4ECCA3), fontSize: 9, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  QUICK SUGGESTION CHIPS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildQuickSuggestions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Quick Questions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.45))),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _quickSuggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = _quickSuggestions[i];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _messageController.text = s['query']!;
                  _sendMessage();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.14))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s['emoji']!, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(s['label']!, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  CHAT AREA
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildChatArea() {
    if (!_isInitialized) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 50, height: 50,
            decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]),
                shape: BoxShape.circle),
            child: const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white))),
          ),
          const SizedBox(height: 12),
          Text('Initializing AI...', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isTyping) return _buildTypingIndicator();
        if (index < _messages.length) return _buildMessageBubble(_messages[index]);
        return const SizedBox.shrink();
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  MESSAGE BUBBLE — with timestamp
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildMessageBubble(ChatMessage message) {
    final time = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';
    final hasImage = message.imagePath != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI avatar
              if (!message.isUser) ...[
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.25), blurRadius: 8)]),
                  child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
              ],
              // Bubble
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: message.isUser
                        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF7B2CBF), Color(0xFF9D84B7)])
                        : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.06)]),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 16),
                    ),
                    border: Border.all(
                        color: message.isUser
                            ? const Color(0xFF7B2CBF).withOpacity(0.5)
                            : Colors.white.withOpacity(0.14),
                        width: 1),
                    boxShadow: message.isUser
                        ? [BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
                        : [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show image if attached
                      if (hasImage)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(message.imagePath!),
                              width: double.infinity,
                              height: 170,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 24)),
                              ),
                            ),
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        SelectableText(
                          message.text,
                          style: TextStyle(
                              color: Colors.white.withOpacity(message.isUser ? 1.0 : 0.92),
                              fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
              ),
              // User avatar
              if (message.isUser) ...[
                const SizedBox(width: 10),
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF2EC4B6), Color(0xFF7B2CBF)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: const Color(0xFF2EC4B6).withOpacity(0.25), blurRadius: 8)]),
                  child: Center(
                    child: Text(
                        (user?.displayName?.isNotEmpty == true
                            ? user!.displayName![0]
                            : user?.email?.isNotEmpty == true
                            ? user!.email![0] : 'U').toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
          // Timestamp
          Padding(
            padding: EdgeInsets.only(
                top: 4,
                left: message.isUser ? 0 : 44,
                right: message.isUser ? 44 : 0),
            child: Text(time, style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  TYPING INDICATOR — gradient pulsing dots
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: const Color(0xFF7B2CBF).withOpacity(0.25), blurRadius: 8)]),
          child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.06)]),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16)),
              border: Border.all(color: Colors.white.withOpacity(0.14))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _buildDot(0), const SizedBox(width: 5),
            _buildDot(1), const SizedBox(width: 5),
            _buildDot(2),
            const SizedBox(width: 8),
            Text('Thinking...', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _typingController,
      builder: (_, __) {
        final val = (_typingController.value + (index * 0.2)) % 1.0;
        final scale = 0.7 + 0.5 * math.sin(val * 2 * math.pi);
        return Transform.scale(
          scale: scale,
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)]).createShader(r),
            child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  //  INPUT AREA — ChatGPT Style (Centered & Polished)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildInputArea() {
    final hasText = _messageController.text.trim().isNotEmpty || _selectedImage != null;
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.05)]),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.14), width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Image Preview Strip ──────────────────────────
                if (_selectedImage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2EC4B6).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(_selectedImage!, width: 54, height: 54, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Image attached',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('Ready to analyze with AI',
                                  style: TextStyle(color: const Color(0xFF2EC4B6).withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _selectedImage = null),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Color(0xFFFF6B6B), size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ── Input Row (Centered ChatGPT Style) ───────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // ── Text field ─────────────────────────────────
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          maxLines: null,
                          maxLength: 500,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          enabled: !_isTyping,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: _selectedImage != null
                                ? 'Ask about this image...'
                                : 'Message AI Health Coach...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      // ── Send button ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 6, top: 6),
                        child: GestureDetector(
                          onTap: _isTyping ? null : (hasText ? _sendMessage : null),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: _isTyping
                                  ? LinearGradient(
                                colors: [
                                  Colors.grey.withOpacity(0.25),
                                  Colors.grey.withOpacity(0.18)
                                ],
                              )
                                  : hasText
                                  ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF7B2CBF), Color(0xFF2EC4B6)],
                              )
                                  : LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.08)
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: hasText && !_isTyping
                                  ? [
                                BoxShadow(
                                  color: const Color(0xFF7B2CBF).withOpacity(0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                )
                              ]
                                  : [],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                _isTyping
                                    ? Icons.hourglass_empty_rounded
                                    : Icons.send_rounded,
                                key: ValueKey(_isTyping ? 'loading' : 'send'),
                                color: _isTyping
                                    ? Colors.white38
                                    : hasText
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.45),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CHAT MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════════════
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? imagePath;
  ChatMessage({required this.text, required this.isUser, required this.timestamp, this.imagePath});
}

// ═══════════════════════════════════════════════════════════════════════════
//  FLOATING ORBS (chat-specific)
// ═══════════════════════════════════════════════════════════════════════════
class _ChatOrb {
  final Offset pos;
  final double radius, speed, angle;
  final Color color;
  const _ChatOrb(this.pos, this.radius, this.speed, this.angle, this.color);
}

class _ChatOrbPainter extends CustomPainter {
  final double tick;
  final List<_ChatOrb> orbs;
  _ChatOrbPainter(this.tick, this.orbs);

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in orbs) {
      final dx = math.sin(tick * o.speed + o.angle) * 25;
      final dy = math.cos(tick * o.speed * 0.7 + o.angle) * 16;
      final c = o.pos + Offset(dx, dy);
      canvas.drawCircle(
        c, o.radius,
        Paint()
          ..shader = RadialGradient(
            colors: [o.color.withOpacity(0.22), o.color.withOpacity(0.0)],
          ).createShader(Rect.fromCircle(center: c, radius: o.radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChatOrbPainter old) => true;
}