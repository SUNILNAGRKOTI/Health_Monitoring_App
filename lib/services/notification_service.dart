import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'app_logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // ✅ Set your timezone

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions
    if (Platform.isAndroid) {
      final androidImplementation =
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
    }

    _initialized = true;
    AppLogger.success('NotificationService initialized');

    // ✅ AUTO-SCHEDULE ALL REMINDERS ON INIT
    await autoScheduleReminders();
  }

  void _onNotificationTap(NotificationResponse response) {
    AppLogger.log('🔔 Notification tapped: ${response.payload}');
  }

  // ✅ AUTO-SCHEDULE ALL REMINDERS
  Future<void> autoScheduleReminders() async {
    try {
      AppLogger.log('🔄 Auto-scheduling all reminders...');

      // Check permission
      final hasPermission = await checkExactAlarmPermission();
      if (!hasPermission) {
        AppLogger.warning('No exact alarm permission - skipping auto-schedule');
        return;
      }

      // Get current states from Firebase
      final states = await getReminderStates();

      // Schedule enabled reminders
      if (states['water'] == true) {
        await scheduleWaterReminders();
      }

      if (states['sleep'] == true) {
        await scheduleSleepReminder();
      }

      if (states['morning'] == true) {
        await scheduleMorningReminder();
      }

      if (states['activity'] == true) {
        await scheduleActivityReminder();
      }

      AppLogger.success('Auto-schedule complete!');
    } catch (e) {
      AppLogger.error('Auto-schedule error: $e');
    }
  }

  // ✅ ENABLE ALL REMINDERS BY DEFAULT FOR NEW USERS
  Future<void> enableAllRemindersForNewUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('reminders')
          .get();

      // If no reminder settings exist, enable all by default
      if (!doc.exists) {
        AppLogger.log('🆕 New user - enabling all reminders');

        // Enable all in Firebase
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('reminders')
            .set({
          'water': true,
          'sleep': true,
          'morning': true,
          'activity': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Schedule all
        await scheduleWaterReminders();
        await scheduleSleepReminder();
        await scheduleMorningReminder();
        await scheduleActivityReminder();

        AppLogger.success('All reminders enabled for new user');
      }
    } catch (e) {
      AppLogger.error('Error enabling reminders for new user: $e');
    }
  }

  // ✅ Exact alarm permission
  Future<bool> checkExactAlarmPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isDenied) {
        final result = await Permission.scheduleExactAlarm.request();
        return result.isGranted;
      }
      return status.isGranted;
    }
    return true;
  }

  // ---------------- WATER REMINDER ----------------

  Future<void> scheduleWaterReminders() async {
    await _cancelNotificationsByType('water');

    final hours = [8, 10, 12, 14, 16, 18, 20, 22];

    for (int i = 0; i < hours.length; i++) {
      await _scheduleNotification(
        id: 1000 + i,
        title: '💧 Time to Drink Water!',
        body: 'Stay hydrated! Drink a glass of water now.',
        hour: hours[i],
        minute: 0,
        payload: 'water',
      );
    }

    await _saveReminderState('water', true);
    AppLogger.success('Water reminders scheduled (8 times/day)');
  }

  // ---------------- SLEEP REMINDER ----------------

  Future<void> scheduleSleepReminder() async {
    await _cancelNotificationsByType('sleep');

    await _scheduleNotification(
      id: 2000,
      title: '😴 Time for Bed!',
      body: 'Get quality sleep. Your body needs 7-8 hours of rest.',
      hour: 22,
      minute: 0,
      payload: 'sleep',
    );

    await _saveReminderState('sleep', true);
    AppLogger.success('Sleep reminder scheduled (10:00 PM)');
  }

  // ---------------- MORNING REMINDER ----------------

  Future<void> scheduleMorningReminder() async {
    await _cancelNotificationsByType('morning');

    await _scheduleNotification(
      id: 3000,
      title: '🌅 Good Morning!',
      body: 'Start your day with positivity! Don\'t forget to log your health.',
      hour: 8,
      minute: 0,
      payload: 'morning',
    );

    await _saveReminderState('morning', true);
    AppLogger.success('Morning reminder scheduled (8:00 AM)');
  }

  // ---------------- ACTIVITY REMINDER ----------------

  Future<void> scheduleActivityReminder() async {
    await _cancelNotificationsByType('activity');

    await _scheduleNotification(
      id: 4000,
      title: '🏃 Time to Move!',
      body: 'Take a walk or do some exercise. Stay active!',
      hour: 18,
      minute: 0,
      payload: 'activity',
    );

    await _saveReminderState('activity', true);
    AppLogger.success('Activity reminder scheduled (6:00 PM)');
  }

  // ---------------- CORE SCHEDULER ----------------

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'healthify_reminders',
          'Health Reminders',
          channelDescription: 'Daily health and wellness reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true, // ✅ Show even when locked
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // ✅ CRITICAL
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // ✅ Repeat daily
      payload: payload,
    );

    AppLogger.log('⏰ Scheduled: $title at $hour:${minute.toString().padLeft(2, '0')}');
  }

  // ---------------- TEST ----------------

  Future<void> sendTestNotification() async {
    await _notifications.show(
      9999,
      '🔔 Test Notification',
      'If you see this, notifications are working perfectly!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'healthify_reminders',
          'Health Reminders',
          channelDescription: 'Daily health and wellness reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
    AppLogger.success('Test notification sent');
  }

  // ---------------- DEBUG ----------------

  Future<void> debugPendingNotifications() async {
    final pending = await _notifications.pendingNotificationRequests();

    AppLogger.log('\n📋 PENDING NOTIFICATIONS:');
    if (pending.isEmpty) {
      AppLogger.warning('No pending notifications');
    } else {
      for (var notif in pending) {
        AppLogger.log('  ✅ ID: ${notif.id} - ${notif.title}');
      }
    }
    AppLogger.log('');
  }

  // ---------------- CANCEL ----------------

  Future<void> cancelReminder(String type) async {
    await _cancelNotificationsByType(type);
    await _saveReminderState(type, false);
    AppLogger.log('❌ $type reminder canceled');
  }

  Future<void> _cancelNotificationsByType(String type) async {
    final Map<String, List<int>> typeIds = {
      'water': List.generate(8, (i) => 1000 + i),
      'sleep': [2000],
      'morning': [3000],
      'activity': [4000],
    };

    final ids = typeIds[type] ?? [];

    for (final id in ids) {
      await _notifications.cancel(id);
    }
  }

  // ---------------- FIREBASE SAVE ----------------

  Future<void> _saveReminderState(String type, bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('reminders')
          .set({
        type: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<Map<String, bool>> getReminderStates() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {
        'water': false,
        'sleep': false,
        'morning': false,
        'activity': false,
      };
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('settings')
        .doc('reminders')
        .get();

    if (!doc.exists) {
      // ✅ Default: ALL ENABLED for new users
      return {
        'water': true,
        'sleep': true,
        'morning': true,
        'activity': true,
      };
    }

    final data = doc.data()!;

    return {
      'water': data['water'] ?? true,
      'sleep': data['sleep'] ?? true,
      'morning': data['morning'] ?? true,
      'activity': data['activity'] ?? true,
    };
  }

  Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('reminders')
          .set({
        'water': false,
        'sleep': false,
        'morning': false,
        'activity': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    AppLogger.log('🗑️ All reminders cancelled');
  }
}