import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Quiet pings: daily habit reminders and exam countdown alerts.
///
/// Every scheduling call is a no-op until [init] has succeeded, so the rest of
/// the app can call these freely on platforms with no notification support.
class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get isReady => _ready;

  /// Id ranges — kept apart so one kind can be rescheduled without disturbing
  /// the other.
  static const _habitIdBase = 1000;
  static const _habitIdMax = 1999;
  static const _eventIdBase = 2000;
  static const _eventIdMax = 2999;
  static const _repeatingIdHabits = 3001;
  static const _repeatingIdSyllabus = 3002;
  static const _repeatingIdGoals = 3003;
  static const _focusOngoingId = 9999;

  // Custom notification sound "pere pere", bundled as res/raw/swayra_notify.wav
  // (Android) and ios/Runner/swayra_notify.wav (iOS). Android caches a channel's
  // sound at creation, so the channel ids carry a `_snd` suffix — bump it if the
  // sound ever changes so existing installs pick up the new one.
  static const _sound = RawResourceAndroidNotificationSound('swayra_notify');
  static const _iosSound = 'swayra_notify.wav';

  static const _habitChannel = AndroidNotificationDetails(
    'studydesk_habits_snd',
    'Ritual reminders',
    channelDescription: 'Daily nudges for your habits',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    sound: _sound,
  );

  static const _eventChannel = AndroidNotificationDetails(
    'studydesk_events_snd',
    'Exam countdowns',
    channelDescription: 'Alerts as an exam or deadline approaches',
    importance: Importance.high,
    priority: Priority.high,
    sound: _sound,
  );

  static const _repeatingTabChannel = AndroidNotificationDetails(
    'studydesk_tab_repeating_snd',
    'Tab Reminders',
    channelDescription: 'Periodic nudges for Habits (5h), Syllabus (10h), Goals (13h)',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    sound: _sound,
  );

  static const _habitDetails = NotificationDetails(
    android: _habitChannel,
    iOS: DarwinNotificationDetails(sound: _iosSound),
  );

  static const _eventDetails = NotificationDetails(
    android: _eventChannel,
    iOS: DarwinNotificationDetails(sound: _iosSound),
  );

  static const _repeatingTabDetails = NotificationDetails(
    android: _repeatingTabChannel,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: _iosSound,
    ),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      // Reminders are wall-clock times, so they must follow the device's zone
      // (and its DST shifts) rather than UTC.
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
      await syncTabRepeatingNotifications();
    } catch (_) {
      // Unsupported platform (or a missing tz database) — the app still runs,
      // it just won't remind you.
      _ready = false;
    }
  }

  /// Asks the OS for permission. Must be triggered by a user gesture on web and
  /// iOS, so it is wired to the reminder toggle rather than to startup.
  Future<bool> requestPermission() async {
    if (!_ready) await init();
    if (!_ready) return false;
    try {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin>();
        return await web?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // Only the notification permission is requested. Reminders use inexact
        // alarms, so we intentionally do NOT ask for the exact-alarm
        // permission (which Play flags as high-risk).
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
                alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {}
    return false;
  }

  /// Next occurrence of [minutes] past midnight, optionally pinned to a
  /// [weekday] (`DateTime.monday`…`DateTime.sunday`).
  tz.TZDateTime _nextOccurrence(int minutes, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (weekday != null) {
      while (when.weekday != weekday) {
        when = when.add(const Duration(days: 1));
      }
    }
    if (!when.isAfter(now)) {
      when = when.add(Duration(days: weekday == null ? 1 : 7));
    }
    return when;
  }

  Future<void> _cancelRange(int from, int to) async {
    for (var id = from; id <= to; id++) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  /// Rebuilds every habit reminder from scratch. Cheap enough to call after any
  /// habit edit, and avoids having to track which ids belong to which habit.
  Future<void> syncHabitReminders(List<Habit> habits) async {
    if (!_ready) return;
    await _cancelRange(_habitIdBase, _habitIdMax);

    for (var i = 0; i < habits.length && i < 100; i++) {
      final habit = habits[i];
      final at = habit.reminderMinutes;
      if (at == null) continue;

      // A habit due every day gets one daily notification; a habit on selected
      // weekdays gets one weekly notification per day it is due.
      final slots = habit.isDaily
          ? <int?>[null]
          : (habit.days.toList()..sort()).cast<int?>();

      for (final weekday in slots) {
        final id = _habitIdBase + i * 10 + (weekday ?? 0);
        if (id > _habitIdMax) break;
        try {
          await _plugin.zonedSchedule(
            id: id,
            title: '${habit.emoji}  ${habit.name}',
            body: 'Time to show up. Tap to tick it off.',
            scheduledDate: _nextOccurrence(at, weekday: weekday),
            notificationDetails: _habitDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: weekday == null
                ? DateTimeComponents.time
                : DateTimeComponents.dayOfWeekAndTime,
            payload: 'habit:${habit.id}',
          );
        } catch (_) {}
      }
    }
  }

  /// One-shot 09:00 alerts a week out, the day before, and on the day itself.
  Future<void> syncEventReminders(List<StudyEvent> events) async {
    if (!_ready) return;
    await _cancelRange(_eventIdBase, _eventIdMax);

    const leadDays = [7, 1, 0];
    var id = _eventIdBase;
    final now = tz.TZDateTime.now(tz.local);

    for (final event in events) {
      final p = event.date.split('-').map(int.parse).toList();
      for (final lead in leadDays) {
        if (id > _eventIdMax) return;
        final when = tz.TZDateTime(tz.local, p[0], p[1], p[2], 9)
            .subtract(Duration(days: lead));
        if (!when.isAfter(now)) continue;
        try {
          await _plugin.zonedSchedule(
            id: id++,
            title: event.title,
            body: lead == 0
                ? 'Today is the day. Good luck.'
                : 'In $lead day${lead == 1 ? '' : 's'}.',
            scheduledDate: when,
            notificationDetails: _eventDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'event:${event.id}',
          );
        } catch (_) {}
      }
    }
  }

  /// Repeating notifications per tab (Android + iOS):
  /// - Habits: every 5 hours
  /// - Syllabus: every 10 hours
  /// - Goals: every 13 hours
  /// Uses default phone notification sound.
  Future<void> syncTabRepeatingNotifications() async {
    if (!_ready) return;

    try {
      await _plugin.cancel(id: _repeatingIdHabits);
      await _plugin.cancel(id: _repeatingIdSyllabus);
      await _plugin.cancel(id: _repeatingIdGoals);
    } catch (_) {}

    // 1. Habits -> every 5 hours
    try {
      await _plugin.periodicallyShowWithDuration(
        id: _repeatingIdHabits,
        title: '⚡ Habit Check-in',
        body: 'Time to track your daily habits! Keep up the momentum.',
        repeatDurationInterval: const Duration(hours: 5),
        notificationDetails: _repeatingTabDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'tab:habits',
      );
    } catch (_) {}

    // 2. Syllabus -> every 10 hours
    try {
      await _plugin.periodicallyShowWithDuration(
        id: _repeatingIdSyllabus,
        title: '📚 Syllabus Progress',
        body: 'Review your study subjects and mark completed topics.',
        repeatDurationInterval: const Duration(hours: 10),
        notificationDetails: _repeatingTabDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'tab:syllabus',
      );
    } catch (_) {}

    // 3. Goals -> every 13 hours
    try {
      await _plugin.periodicallyShowWithDuration(
        id: _repeatingIdGoals,
        title: '🎯 Goal Milestone',
        body: 'Check in on your target goals. Stay focused on your mission!',
        repeatDurationInterval: const Duration(hours: 13),
        notificationDetails: _repeatingTabDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'tab:goals',
      );
    } catch (_) {}
  }

  /// Ongoing notification in status/slide-down bar ticking like a clock/timer.
  Future<void> showFocusOngoingNotification({
    required String modeLabel,
    required int remainingSeconds,
    bool isPaused = false,
  }) async {
    if (!_ready) return;

    final mm = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (remainingSeconds % 60).toString().padLeft(2, '0');
    final endTime = DateTime.now().add(Duration(seconds: remainingSeconds));

    final androidDetails = AndroidNotificationDetails(
      'studydesk_focus_timer',
      'Focus Session Active',
      channelDescription: 'Ongoing ticking timer for focus sessions',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: !isPaused,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      usesChronometer: !isPaused,
      chronometerCountDown: !isPaused,
      when: !isPaused ? endTime.millisecondsSinceEpoch : null,
      playSound: false,
      enableVibration: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        id: _focusOngoingId,
        title: isPaused ? '⏱️ $modeLabel (Paused)' : '⏱️ $modeLabel running',
        body: isPaused
            ? 'Paused at $mm:$ss'
            : 'Remaining: $mm:$ss — Keep grinding!',
        notificationDetails: details,
        payload: 'tab:focus',
      );
    } catch (_) {}
  }

  Future<void> cancelFocusNotification() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _focusOngoingId);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
