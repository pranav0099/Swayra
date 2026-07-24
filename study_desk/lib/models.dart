import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';
import 'widget_bridge.dart';

// ---------- shared ids (must match the native widget side) ----------
const String appGroupId = 'group.com.fta.studydesk'; // iOS App Group
const String androidWidget = 'StudyWidgetProvider'; // Android receiver class
const String iOSWidget = 'StudyWidget'; // iOS widget "kind"

/// SharedPreferences key holding the whole app state. Also read directly by the
/// widget background isolate, so it must stay public.
const String storageKey = 'studydesk:v1';

// ---------- helpers ----------
final _rng = Random();
String uid() =>
    _rng.nextInt(1 << 31).toRadixString(36) +
    _rng.nextInt(1 << 16).toRadixString(36);

String localDateStr([DateTime? date]) {
  final d = date ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Whole days from local midnight-today to local midnight of [dateStr].
int daysUntil(String dateStr) {
  final now = DateTime.now();
  final start = DateTime.utc(now.year, now.month, now.day);
  final p = dateStr.split('-').map(int.parse).toList();
  final target = DateTime.utc(p[0], p[1], p[2]);
  return target.difference(start).inDays;
}

String _seedDate(int n) => localDateStr(DateTime.now().add(Duration(days: n)));

String prettyDate(String dateStr) {
  final p = dateStr.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${wk[d.weekday - 1]} ${mo[d.month - 1]} ${d.day} ${d.year}';
}

/// True when the app is running inside the Electron desktop shell.
bool get isDesktopShell =>
    kIsWeb &&
    (Uri.base.origin.contains('127.0.0.1') ||
        Uri.base.origin.contains('localhost')) &&
    Uri.base.origin.contains('47821');

// ---------- data classes ----------
class Topic {
  String id;
  String name;
  bool done;
  Topic({required this.id, required this.name, this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'done': done};
  factory Topic.fromJson(Map<String, dynamic> j) =>
      Topic(id: j['id'], name: j['name'], done: j['done'] ?? false);
}

class Subject {
  String id;
  String name;
  List<Topic> topics;
  Subject({required this.id, required this.name, required this.topics});

  int get doneCount => topics.where((t) => t.done).length;
  int get pct =>
      topics.isEmpty ? 0 : ((doneCount / topics.length) * 100).round();

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'topics': topics.map((t) => t.toJson()).toList()};
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'],
        name: j['name'],
        topics: (j['topics'] as List? ?? [])
            .map((e) => Topic.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class StudyEvent {
  String id;
  String title;
  String date; // yyyy-MM-dd
  StudyEvent({required this.id, required this.title, required this.date});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date};
  factory StudyEvent.fromJson(Map<String, dynamic> j) =>
      StudyEvent(id: j['id'], title: j['title'], date: j['date']);
}

class Goal {
  String id;
  String text;
  bool done;
  Goal({required this.id, required this.text, this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
  factory Goal.fromJson(Map<String, dynamic> j) =>
      Goal(id: j['id'], text: j['text'], done: j['done'] ?? false);
}

class FocusStats {
  int sessionsToday;
  String dateOfSessions;
  int total;
  int minutes;
  FocusStats({
    required this.sessionsToday,
    required this.dateOfSessions,
    required this.total,
    required this.minutes,
  });

  Map<String, dynamic> toJson() => {
        'sessionsToday': sessionsToday,
        'dateOfSessions': dateOfSessions,
        'total': total,
        'minutes': minutes,
      };
  factory FocusStats.fromJson(Map<String, dynamic> j) => FocusStats(
        sessionsToday: j['sessionsToday'] ?? 0,
        dateOfSessions: j['dateOfSessions'] ?? localDateStr(),
        total: j['total'] ?? 0,
        minutes: j['minutes'] ?? 0,
      );
}

class Streak {
  int count;
  String? lastStudyDate;
  int best;
  Streak({this.count = 0, this.lastStudyDate, this.best = 0});

  Map<String, dynamic> toJson() =>
      {'count': count, 'lastStudyDate': lastStudyDate, 'best': best};
  factory Streak.fromJson(Map<String, dynamic> j) => Streak(
        count: j['count'] ?? 0,
        lastStudyDate: j['lastStudyDate'],
        best: j['best'] ?? 0,
      );
}

/// A repeating daily ritual. Unlike [Goal] (a one-off checkbox) a habit is never
/// "finished" — it is ticked once per scheduled day and its history lives in
/// [AppState.dayLogs].
class Habit {
  String id;
  String name;
  String emoji;
  /// Weekdays the habit is due on, `DateTime.monday`(1)…`DateTime.sunday`(7).
  Set<int> days;
  /// Daily reminder as minutes past local midnight, or null for no reminder.
  int? reminderMinutes;
  String createdAt; // yyyy-MM-dd

  Habit({
    required this.id,
    required this.name,
    this.emoji = '✓',
    Set<int>? days,
    this.reminderMinutes,
    String? createdAt,
  })  : days = days ?? {1, 2, 3, 4, 5, 6, 7},
        createdAt = createdAt ?? localDateStr();

  bool get isDaily => days.length == 7;

  bool isDueOn(String dateStr) {
    final p = dateStr.split('-').map(int.parse).toList();
    return days.contains(DateTime(p[0], p[1], p[2]).weekday);
  }

  String get scheduleLabel {
    if (isDaily) return 'Every day';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = days.toList()..sort();
    return sorted.map((d) => names[d - 1]).join(' · ');
  }

  String? get reminderLabel {
    final m = reminderMinutes;
    if (m == null) return null;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'days': days.toList(),
        'reminderMinutes': reminderMinutes,
        'createdAt': createdAt,
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'],
        name: j['name'],
        emoji: j['emoji'] ?? '✓',
        days: ((j['days'] as List?) ?? const [1, 2, 3, 4, 5, 6, 7])
            .map((e) => e as int)
            .toSet(),
        reminderMinutes: j['reminderMinutes'],
        createdAt: j['createdAt'] ?? localDateStr(),
      );
}

/// Everything that happened on one calendar day. This is the record the app was
/// missing: streaks and the heatmap are both derived from it rather than stored.
class DayLog {
  Set<String> habits; // habit ids ticked that day
  int focus; // focus sessions finished
  int topics; // syllabus topics ticked
  int goals; // goals completed

  DayLog({Set<String>? habits, this.focus = 0, this.topics = 0, this.goals = 0})
      : habits = habits ?? {};

  bool get isEmpty => habits.isEmpty && focus == 0 && topics == 0 && goals == 0;

  /// Raw amount of work recorded, used to shade the heatmap.
  int get activity => habits.length + focus + topics + goals;

  Map<String, dynamic> toJson() => {
        'habits': habits.toList(),
        'focus': focus,
        'topics': topics,
        'goals': goals,
      };

  factory DayLog.fromJson(Map<String, dynamic> j) => DayLog(
        habits: ((j['habits'] as List?) ?? []).map((e) => e as String).toSet(),
        focus: j['focus'] ?? 0,
        topics: j['topics'] ?? 0,
        goals: j['goals'] ?? 0,
      );
}

// ---------- achievements ----------
class Achievement {
  final String id;
  final IconData icon;
  final String title;
  final String desc;
  final bool Function(AppState s) check;
  const Achievement(this.id, this.icon, this.title, this.desc, this.check);
}

final List<Achievement> achievements = [
  Achievement('planner', Icons.calendar_month, 'First Countdown',
      'Add an exam or event', (s) => s.events.isNotEmpty),
  Achievement('first-focus', Icons.schedule, 'Locked In',
      'Finish 1 focus session', (s) => s.focus.total >= 1),
  Achievement('focus-5', Icons.schedule, 'Deep Work',
      '5 sessions in one day', (s) => s.focus.sessionsToday >= 5),
  Achievement('focus-25', Icons.emoji_events, 'Marathon',
      '25 focus sessions total', (s) => s.focus.total >= 25),
  Achievement('streak-3', Icons.local_fire_department, 'Warming Up',
      '3-day study streak', (s) => s.streak.best >= 3),
  Achievement('streak-7', Icons.local_fire_department, 'On Fire',
      '7-day study streak', (s) => s.streak.best >= 7),
  Achievement('streak-30', Icons.local_fire_department, 'Unstoppable',
      '30-day study streak', (s) => s.streak.best >= 30),
  Achievement(
      'topic-master',
      Icons.menu_book,
      'Topic Master',
      'Finish a full subject',
      (s) => s.subjects
          .any((sub) => sub.topics.isNotEmpty && sub.topics.every((t) => t.done))),
  Achievement('goal-getter', Icons.track_changes, 'Goal Getter',
      'Complete 10 goals', (s) => s.goalsCompleted >= 10),
  Achievement('ritual-start', Icons.self_improvement, 'Ritual Begun',
      'Create your first habit', (s) => s.habits.isNotEmpty),
  Achievement(
      'ritual-week',
      Icons.auto_awesome,
      'Show Up Daily',
      'Keep a habit alive 7 days',
      (s) => s.habits.any((h) => s.habitStreak(h.id) >= 7)),
  Achievement('perfect-day', Icons.done_all, 'Perfect Day',
      'Tick every habit due today', (s) => s.isPerfectDay),
];

// ---------- app state (offline-only, no sign-in) ----------
/// Offline-only app state: everything lives on this device, in
/// SharedPreferences, and is never sent anywhere.
class AppState extends ChangeNotifier {
  AppState();

  List<StudyEvent> events = [];
  List<Subject> subjects = [];
  List<Goal> goals = [];
  List<Habit> habits = [];
  /// yyyy-MM-dd → what happened that day. The source of truth for the heatmap
  /// and for every streak.
  Map<String, DayLog> dayLogs = {};
  FocusStats focus = FocusStats(
      sessionsToday: 0, dateOfSessions: localDateStr(), total: 0, minutes: 0);
  Streak streak = Streak();
  int goalsCompleted = 0;
  Set<String> earned = {};
  bool pinToWallpaperEnabled = false;
  bool remindersEnabled = false;

  bool hydrated = false;
  bool ready = false; // first load resolved → UI can leave the splash
  Achievement? justEarned;
  Timer? _toastTimer;

  /// When this device last changed anything. Lets [reloadFromDisk] tell whether
  /// a background isolate (a home-screen widget tap) has written something
  /// newer than what is held in memory.
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _widgetPollTimer;

  // ----- bootstrap -----
  Future<void> init() async {
    await _loadLocal();
    hydrated = true;
    _checkAchievements(announce: false);
    ready = true;
    notifyListeners();
    await Notifications.instance.init();
    await _syncReminders();
    await _pushWidget();
    _startWidgetActionPolling();
    if (isDesktopShell) {
      try {
        await http.post(Uri.parse(
            '${Uri.base.origin}/api/widget/pin-wallpaper?enabled=$pinToWallpaperEnabled'));
      } catch (_) {}
    }
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      pinToWallpaperEnabled = prefs.getBool('widget_wallpaper_pin') ?? false;
      remindersEnabled = prefs.getBool('reminders_enabled') ?? false;
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        _applyStateMap(jsonDecode(raw) as Map<String, dynamic>);
        return;
      }
      _seed();
    } catch (_) {
      _seed();
    }
    // No saved data yet: persist the seed immediately so the desktop widget
    // has something to show before the first edit.
    await _persistLocal();
  }

  /// Replaces in-memory data from a state map.
  void _applyStateMap(Map<String, dynamic> d) {
    events = (d['events'] as List? ?? [])
        .map((e) => StudyEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    subjects = (d['subjects'] as List? ?? [])
        .map((e) => Subject.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    goals = (d['goals'] as List? ?? [])
        .map((e) => Goal.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    focus = d['focus'] != null
        ? FocusStats.fromJson(Map<String, dynamic>.from(d['focus']))
        : FocusStats(
            sessionsToday: 0, dateOfSessions: localDateStr(), total: 0, minutes: 0);
    streak = d['streak'] != null
        ? Streak.fromJson(Map<String, dynamic>.from(d['streak']))
        : Streak();
    habits = (d['habits'] as List? ?? [])
        .map((e) => Habit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    dayLogs = ((d['dayLogs'] as Map?) ?? {}).map((k, v) =>
        MapEntry(k as String, DayLog.fromJson(Map<String, dynamic>.from(v))));
    goalsCompleted = d['goalsCompleted'] ?? 0;
    earned = ((d['earned'] as List?) ?? []).map((e) => e as String).toSet();
    updatedAt = DateTime.tryParse(d['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Restores from a state blob without touching storage. For tests.
  void applyStateMapForTest(Map<String, dynamic> d) {
    _applyStateMap(d);
    hydrated = true;
    ready = true;
    notifyListeners();
  }

  /// Seeds in-memory demo data without touching storage. For tests/previews.
  void seedForTest() {
    _seed();
    hydrated = true;
    ready = true;
    notifyListeners();
  }

  void _seed() {
    events = [
      StudyEvent(id: uid(), title: 'End-Semester Exam', date: _seedDate(45)),
    ];
    subjects = [
      Subject(id: uid(), name: 'Engineering Mathematics', topics: [
        Topic(id: uid(), name: 'Differential Equations', done: true),
        Topic(id: uid(), name: 'Laplace Transform'),
        Topic(id: uid(), name: 'Probability'),
      ]),
      Subject(id: uid(), name: 'Data Structures', topics: [
        Topic(id: uid(), name: 'Arrays', done: true),
        Topic(id: uid(), name: 'Linked Lists', done: true),
        Topic(id: uid(), name: 'Trees'),
        Topic(id: uid(), name: 'Graphs'),
      ]),
    ];
    goals = [
      Goal(id: uid(), text: 'Finish DSA trees chapter'),
      Goal(id: uid(), text: 'Solve 20 practice problems'),
      Goal(id: uid(), text: 'Revise Maths Unit 3'),
    ];
    habits = [
      Habit(id: uid(), name: 'Read 30 minutes', emoji: '📖'),
      Habit(id: uid(), name: 'Revise yesterday’s notes', emoji: '🧠'),
      Habit(
          id: uid(),
          name: 'Weekly mock test',
          emoji: '📝',
          days: {DateTime.sunday}),
    ];
  }

  Map<String, dynamic> _toJson() => {
        'events': events.map((e) => e.toJson()).toList(),
        'subjects': subjects.map((e) => e.toJson()).toList(),
        'goals': goals.map((e) => e.toJson()).toList(),
        'habits': habits.map((e) => e.toJson()).toList(),
        'dayLogs': dayLogs.map((k, v) => MapEntry(k, v.toJson())),
        'focus': focus.toJson(),
        'streak': streak.toJson(),
        'goalsCompleted': goalsCompleted,
        'earned': earned.toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// The full state blob, exposed for the sync layer.
  Map<String, dynamic> toStateMap() => _toJson();

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_toJson()));
    } catch (_) {}
  }

  /// Call after any mutation: saves locally, re-checks achievements, refreshes
  /// UI + widget.
  void _commit({bool pushWidget = false, bool syncReminders = false}) {
    updatedAt = DateTime.now();
    _checkAchievements();
    notifyListeners();
    _persistLocal();
    if (pushWidget) _pushWidget();
    if (syncReminders) _syncReminders();
  }

  // ----- reminders -----
  /// Re-pushes every scheduled reminder. Called after any habit or event edit;
  /// silently does nothing while reminders are switched off.
  Future<void> _syncReminders() async {
    if (!remindersEnabled) return;
    await Notifications.instance.syncHabitReminders(habits);
    await Notifications.instance.syncEventReminders(events);
    await Notifications.instance.syncTabRepeatingNotifications();
  }

  /// Flips the master reminder switch. Turning it *on* prompts the OS for
  /// permission first and stays off if the user declines.
  Future<void> setRemindersEnabled(bool value) async {
    if (value) {
      final granted = await Notifications.instance.requestPermission();
      if (!granted) {
        remindersEnabled = false;
        notifyListeners();
        return;
      }
    }
    remindersEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reminders_enabled', value);
    } catch (_) {}
    if (value) {
      await _syncReminders();
    } else {
      await Notifications.instance.cancelAll();
    }
  }

  // ----- desktop widget actions -----
  /// The Electron widget is a separate window and cannot reach into this
  /// isolate, so it queues taps in the shell and we drain them here.
  void _startWidgetActionPolling() {
    if (!isDesktopShell) return;
    _widgetPollTimer?.cancel();
    _widgetPollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _drainWidgetActions());
  }

  Future<void> _drainWidgetActions() async {
    try {
      final res = await http
          .get(Uri.parse('${Uri.base.origin}/api/widget/actions'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final actions =
          (jsonDecode(res.body) as Map<String, dynamic>)['actions'] as List?;
      for (final action in actions ?? const []) {
        final a = Map<String, dynamic>.from(action as Map);
        final id = a['id'];
        if (a['type'] == 'toggleHabit' && id is String && habitById(id) != null) {
          toggleHabit(id, a['date'] as String?);
        }
      }
    } catch (_) {
      // Shell not reachable (plain browser, or app closing) — nothing to do.
    }
  }

  // ----- desktop widget toggle -----
  /// Tells the Electron shell to show/hide the small countdown widget.
  /// Only works when running inside the desktop app.
  Future<void> toggleDesktopWidget() async {
    if (!isDesktopShell) return;
    try {
      await http.post(Uri.parse('${Uri.base.origin}/api/widget/toggle'));
    } catch (_) {}
  }

  Future<void> toggleWallpaperPin() async {
    pinToWallpaperEnabled = !pinToWallpaperEnabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('widget_wallpaper_pin', pinToWallpaperEnabled);
    } catch (_) {}

    if (isDesktopShell) {
      try {
        await http.post(Uri.parse(
            '${Uri.base.origin}/api/widget/pin-wallpaper?enabled=$pinToWallpaperEnabled'));
      } catch (_) {}
    }
  }

  Future<void> pinMobileWidget() async {
    try {
      await HomeWidget.requestPinWidget(
        name: androidWidget,
        androidName: androidWidget,
      );
    } catch (_) {}
  }

  // ----- derived -----
  int get liveStreak {
    if (streak.lastStudyDate == null) return 0;
    final today = localDateStr();
    final yest = localDateStr(DateTime.now().subtract(const Duration(days: 1)));
    if (streak.lastStudyDate == today || streak.lastStudyDate == yest) {
      return streak.count;
    }
    return 0;
  }

  StudyEvent? get nextEvent {
    final upcoming = events.where((e) => daysUntil(e.date) >= 0).toList()
      ..sort((a, b) => daysUntil(a.date) - daysUntil(b.date));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  int get totalTopics =>
      subjects.fold(0, (acc, s) => acc + s.topics.length);
  int get doneTopics =>
      subjects.fold(0, (acc, s) => acc + s.doneCount);
  int get overallPct =>
      totalTopics == 0 ? 0 : ((doneTopics / totalTopics) * 100).round();

  int get sessionsToday =>
      focus.dateOfSessions == localDateStr() ? focus.sessionsToday : 0;

  // ----- streak -----
  void registerStudyDay() {
    final today = localDateStr();
    if (streak.lastStudyDate == today) return;
    final yest = localDateStr(DateTime.now().subtract(const Duration(days: 1)));
    final count = streak.lastStudyDate == yest ? streak.count + 1 : 1;
    streak = Streak(
      count: count,
      lastStudyDate: today,
      best: max(streak.best, count),
    );
  }

  // ----- day log -----
  /// Mutates (creating if needed) the log for [dateStr], dropping it again if
  /// the edit left the day empty so the heatmap stays sparse.
  void _editDay(String dateStr, void Function(DayLog log) change) {
    final log = dayLogs[dateStr] ?? DayLog();
    change(log);
    if (log.isEmpty) {
      dayLogs.remove(dateStr);
    } else {
      dayLogs[dateStr] = log;
    }
  }

  DayLog logFor(String dateStr) => dayLogs[dateStr] ?? DayLog();

  /// Busiest day on record — the scale the heatmap shades against.
  int get peakActivity =>
      dayLogs.values.fold(0, (m, l) => max(m, l.activity));

  /// 0 (nothing) … 4 (a peak day) for [dateStr].
  int heatLevel(String dateStr) {
    final a = logFor(dateStr).activity;
    if (a == 0) return 0;
    final peak = max(peakActivity, 1);
    return (1 + ((a / peak) * 3).round()).clamp(1, 4);
  }

  /// Every day with any activity, used for the "days shown up" counter.
  int get activeDays => dayLogs.length;

  // ----- habits -----
  Habit? habitById(String id) {
    for (final h in habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  List<Habit> habitsDueOn([String? dateStr]) {
    final date = dateStr ?? localDateStr();
    return habits.where((h) => h.isDueOn(date)).toList();
  }

  bool habitDoneOn(String habitId, [String? dateStr]) =>
      logFor(dateStr ?? localDateStr()).habits.contains(habitId);

  int get habitsDoneToday {
    final due = habitsDueOn().map((h) => h.id).toSet();
    return logFor(localDateStr()).habits.where(due.contains).length;
  }

  bool get isPerfectDay {
    final due = habitsDueOn();
    return due.isNotEmpty && due.every((h) => habitDoneOn(h.id));
  }

  /// Consecutive *scheduled* days completed, counting back from today. Today
  /// not being ticked yet doesn't break the streak — only a missed earlier day
  /// does, which matches how Ritualz reads.
  int habitStreak(String habitId) {
    final habit = habitById(habitId);
    if (habit == null) return 0;
    var streak = 0;
    var cursor = DateTime.now();
    for (var i = 0; i < 366 * 3; i++) {
      final date = localDateStr(cursor);
      if (date.compareTo(habit.createdAt) < 0) break;
      if (habit.isDueOn(date)) {
        if (logFor(date).habits.contains(habitId)) {
          streak++;
        } else if (i > 0 || streak > 0) {
          break; // a missed scheduled day ends it
        } else {
          // today is still open — look further back without counting it
        }
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int habitBest(String habitId) {
    final habit = habitById(habitId);
    if (habit == null) return 0;
    final dates = dayLogs.entries
        .where((e) => e.value.habits.contains(habitId))
        .map((e) => e.key)
        .toList()
      ..sort();
    var best = 0, run = 0;
    String? prev;
    for (final d in dates) {
      if (prev == null || _isNextScheduled(habit, prev, d)) {
        run++;
      } else {
        run = 1;
      }
      best = max(best, run);
      prev = d;
    }
    return best;
  }

  /// True when [next] is the very next day [habit] was due after [prev].
  bool _isNextScheduled(Habit habit, String prev, String next) {
    final p = prev.split('-').map(int.parse).toList();
    var cursor = DateTime(p[0], p[1], p[2]).add(const Duration(days: 1));
    for (var i = 0; i < 8; i++) {
      final d = localDateStr(cursor);
      if (habit.isDueOn(d)) return d == next;
      cursor = cursor.add(const Duration(days: 1));
    }
    return false;
  }

  void addHabit(String name,
      {String emoji = '✓', Set<int>? days, int? reminderMinutes}) {
    habits = [
      ...habits,
      Habit(
        id: uid(),
        name: name,
        emoji: emoji,
        days: days,
        reminderMinutes: reminderMinutes,
      )
    ];
    _commit(pushWidget: true, syncReminders: true);
  }

  void removeHabit(String id) {
    habits = habits.where((h) => h.id != id).toList();
    for (final log in dayLogs.values) {
      log.habits.remove(id);
    }
    dayLogs.removeWhere((_, l) => l.isEmpty);
    _commit(pushWidget: true, syncReminders: true);
  }

  void updateHabit(String id,
      {String? name, String? emoji, Set<int>? days, int? reminderMinutes,
      bool clearReminder = false}) {
    for (final h in habits) {
      if (h.id != id) continue;
      if (name != null) h.name = name;
      if (emoji != null) h.emoji = emoji;
      if (days != null) h.days = days;
      if (clearReminder) {
        h.reminderMinutes = null;
      } else if (reminderMinutes != null) {
        h.reminderMinutes = reminderMinutes;
      }
    }
    _commit(pushWidget: true, syncReminders: true);
  }

  /// Ticks / un-ticks [habitId] on [dateStr] (defaults to today).
  void toggleHabit(String habitId, [String? dateStr]) {
    final date = dateStr ?? localDateStr();
    final wasDone = logFor(date).habits.contains(habitId);
    _editDay(date, (l) {
      if (wasDone) {
        l.habits.remove(habitId);
      } else {
        l.habits.add(habitId);
      }
    });
    if (!wasDone && date == localDateStr()) registerStudyDay();
    _commit(pushWidget: true);
  }

  // ----- events -----
  void addEvent(String title, String date) {
    events = [...events, StudyEvent(id: uid(), title: title, date: date)];
    _commit(pushWidget: true, syncReminders: true);
  }

  void removeEvent(String id) {
    events = events.where((e) => e.id != id).toList();
    _commit(pushWidget: true, syncReminders: true);
  }

  // ----- subjects / topics -----
  void addSubject(String name) {
    subjects = [...subjects, Subject(id: uid(), name: name, topics: [])];
    _commit();
  }

  void removeSubject(String id) {
    subjects = subjects.where((s) => s.id != id).toList();
    _commit();
  }

  void addTopic(String subjectId, String name) {
    subjects = subjects
        .map((s) => s.id == subjectId
            ? Subject(
                id: s.id,
                name: s.name,
                topics: [...s.topics, Topic(id: uid(), name: name)])
            : s)
        .toList();
    _commit();
  }

  void toggleTopic(String subjectId, String topicId) {
    var ticked = false;
    for (final s in subjects) {
      if (s.id == subjectId) {
        for (final t in s.topics) {
          if (t.id == topicId) {
            t.done = !t.done;
            ticked = t.done;
          }
        }
      }
    }
    if (ticked) {
      _editDay(localDateStr(), (l) => l.topics += 1);
      registerStudyDay();
    }
    _commit();
  }

  // ----- goals -----
  void addGoal(String text) {
    goals = [...goals, Goal(id: uid(), text: text)];
    _commit();
  }

  void removeGoal(String id) {
    goals = goals.where((g) => g.id != id).toList();
    _commit();
  }

  void toggleGoal(String id) {
    for (final g in goals) {
      if (g.id == id) {
        if (!g.done) {
          goalsCompleted += 1;
          _editDay(localDateStr(), (l) => l.goals += 1);
          registerStudyDay();
        }
        g.done = !g.done;
      }
    }
    _commit();
  }

  // ----- focus -----
  void recordFocusSession() {
    final today = localDateStr();
    final st = focus.dateOfSessions == today ? focus.sessionsToday : 0;
    focus = FocusStats(
      sessionsToday: st + 1,
      dateOfSessions: today,
      total: focus.total + 1,
      minutes: focus.minutes + 25,
    );
    _editDay(today, (l) => l.focus += 1);
    registerStudyDay();
    _commit();
  }

  // ----- achievements -----
  void _checkAchievements({bool announce = true}) {
    final newly = achievements
        .where((a) => !earned.contains(a.id) && a.check(this))
        .map((a) => a.id)
        .toList();
    if (newly.isEmpty) return;
    earned.addAll(newly);
    if (announce) {
      justEarned = achievements.firstWhere((a) => a.id == newly.first);
      _toastTimer?.cancel();
      _toastTimer = Timer(const Duration(milliseconds: 3500), () {
        justEarned = null;
        notifyListeners();
      });
    }
  }

  // ----- home-screen widget bridge -----
  Future<void> _pushWidget() => pushWidgetPayload(_toJson());

  /// Re-reads the saved blob and adopts it if it is newer than what is in
  /// memory. Called when the app comes back to the foreground, so a habit
  /// ticked from the home-screen widget (which edits storage from a background
  /// isolate) is not clobbered by this instance's stale copy.
  Future<void> reloadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      final diskAt = DateTime.tryParse(d['updatedAt']?.toString() ?? '');
      if (diskAt == null || !diskAt.isAfter(updatedAt)) return;
      _applyStateMap(d);
      _checkAchievements(announce: false);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _widgetPollTimer?.cancel();
    super.dispose();
  }
}
