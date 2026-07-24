import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// How many habits the home-screen widget has room for.
const int kWidgetHabitSlots = 3;

/// Shape the widget reads: today's due habits plus the next countdown.
///
/// Kept out of [AppState] because the background isolate that handles a widget
/// tap has no AppState — it works straight off the persisted blob.
Map<String, String> buildWidgetPayload(Map<String, dynamic> state) {
  final today = localDateStr();

  final habits = (state['habits'] as List? ?? [])
      .map((e) => Habit.fromJson(Map<String, dynamic>.from(e)))
      .where((h) => h.isDueOn(today))
      .take(kWidgetHabitSlots)
      .toList();

  final logs = (state['dayLogs'] as Map?) ?? {};
  final doneToday = ((logs[today]?['habits'] as List?) ?? [])
      .map((e) => e.toString())
      .toSet();

  final events = (state['events'] as List? ?? [])
      .map((e) => StudyEvent.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => daysUntil(e.date) >= 0)
      .toList()
    ..sort((a, b) => daysUntil(a.date) - daysUntil(b.date));
  final next = events.isEmpty ? null : events.first;

  return {
    'exam_title': next?.title ?? 'No exam set',
    'exam_date': next?.date ?? '',
    'habits_json': jsonEncode(habits
        .map((h) => {
              'id': h.id,
              'name': h.name,
              'emoji': h.emoji,
              'done': doneToday.contains(h.id),
            })
        .toList()),
    'habits_done': '${doneToday.length}',
    'habits_total': '${habits.length}',
  };
}

Future<void> _writeWidgetPayload(Map<String, dynamic> state) async {
  final payload = buildWidgetPayload(state);
  for (final entry in payload.entries) {
    await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
  }
  await HomeWidget.updateWidget(
    name: androidWidget,
    androidName: androidWidget,
    iOSName: iOSWidget,
  );
}

/// Pushes the current [state] blob out to the home-screen widget.
Future<void> pushWidgetPayload(Map<String, dynamic> state) async {
  try {
    await _writeWidgetPayload(state);
  } catch (_) {
    // No widget host (web/desktop/tests) — nothing to update.
  }
}

/// Entry point for a tap on the home-screen widget.
///
/// Runs in a background isolate with no UI and no [AppState], so it edits the
/// saved blob directly and then repaints the widget. The app picks the change
/// up when it next reads storage (see `AppState.reloadFromDisk`).
@pragma('vm:entry-point')
Future<void> onWidgetTapped(Uri? uri) async {
  if (uri == null || uri.host != 'toggle') return;
  final habitId = uri.queryParameters['id'];
  if (habitId == null || habitId.isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return;

    final state = jsonDecode(raw) as Map<String, dynamic>;
    final today = localDateStr();

    final logs = Map<String, dynamic>.from((state['dayLogs'] as Map?) ?? {});
    final day = Map<String, dynamic>.from(
        (logs[today] as Map?) ?? {'habits': [], 'focus': 0, 'topics': 0, 'goals': 0});
    final done = ((day['habits'] as List?) ?? []).map((e) => e.toString()).toList();

    if (done.contains(habitId)) {
      done.remove(habitId);
    } else {
      done.add(habitId);
    }
    day['habits'] = done;

    final isEmpty = done.isEmpty &&
        (day['focus'] ?? 0) == 0 &&
        (day['topics'] ?? 0) == 0 &&
        (day['goals'] ?? 0) == 0;
    if (isEmpty) {
      logs.remove(today);
    } else {
      logs[today] = day;
    }
    state['dayLogs'] = logs;
    // Mark the edit so cloud sync treats this device as the newer side.
    state['updatedAt'] = DateTime.now().toIso8601String();

    await prefs.setString(storageKey, jsonEncode(state));
    await _writeWidgetPayload(state);
  } catch (_) {
    // A failed tap must never crash the widget host.
  }
}
