// Basic smoke tests for Swayra.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:study_desk/models.dart';
import 'package:study_desk/main.dart';
import 'package:study_desk/widget_bridge.dart';

void main() {
  testWidgets('landing screen shows the brand, then opens the app',
      (tester) async {
    final state = AppState()..seedForTest();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SwayraApp(),
      ),
    );
    await tester.pump();

    // Landing first.
    expect(find.text('SWAYRA'), findsOneWidget);
    expect(find.text('Build Your Best Self, One Ritual at a Time.'),
        findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Today'), findsNothing); // app not shown yet

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Then the app itself — no login gate anywhere.
    expect(find.text('SWAYRA'), findsOneWidget); // now the header wordmark
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('NEXT UP'), findsWidgets); // seeded countdown
  });

  testWidgets('landing auto-advances on its own', (tester) async {
    final state = AppState()..seedForTest();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SwayraApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Get started'), findsOneWidget);

    // Wait past the auto-advance timer without touching anything.
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
  });

  test('daysUntil counts whole days correctly', () {
    final tomorrow =
        localDateStr(DateTime.now().add(const Duration(days: 1)));
    expect(daysUntil(tomorrow), 1);
    expect(daysUntil(localDateStr()), 0);
  });

  test('streak increments on a study day', () {
    final s = AppState()..seedForTest();
    s.registerStudyDay();
    expect(s.liveStreak, 1);
  });

  test('seeded state has the demo exam and goals', () {
    final s = AppState()..seedForTest();
    expect(s.events.length, 1);
    expect(s.goals.length, 3);
    expect(s.nextEvent, isNotNull);
  });

  // ---------- habits ----------
  group('habits', () {
    test('toggling writes to the day log and back out again', () {
      final s = AppState()..seedForTest();
      final id = s.habits.first.id;
      final today = localDateStr();

      expect(s.habitDoneOn(id), isFalse);
      s.toggleHabit(id);
      expect(s.habitDoneOn(id), isTrue);
      expect(s.logFor(today).habits, contains(id));

      s.toggleHabit(id);
      expect(s.habitDoneOn(id), isFalse);
      // An emptied day is dropped so the heatmap stays sparse.
      expect(s.dayLogs.containsKey(today), isFalse);
    });

    test('only habits scheduled for the day are due', () {
      final s = AppState()..seedForTest();
      final sundayOnly = s.habits.firstWhere((h) => !h.isDaily);
      expect(sundayOnly.days, {DateTime.sunday});

      // Walk forward to the next Sunday and to a day that is not Sunday.
      var sunday = DateTime.now();
      while (sunday.weekday != DateTime.sunday) {
        sunday = sunday.add(const Duration(days: 1));
      }
      final monday = sunday.add(const Duration(days: 1));

      expect(sundayOnly.isDueOn(localDateStr(sunday)), isTrue);
      expect(sundayOnly.isDueOn(localDateStr(monday)), isFalse);
      expect(s.habitsDueOn(localDateStr(monday)).contains(sundayOnly), isFalse);
    });

    test('streak counts back over consecutive days', () {
      final s = AppState()..seedForTest();
      final id = s.habits.first.id; // a daily habit
      s.habits.first.createdAt = localDateStr(
          DateTime.now().subtract(const Duration(days: 30)));

      for (var i = 0; i < 4; i++) {
        final day = localDateStr(DateTime.now().subtract(Duration(days: i)));
        s.toggleHabit(id, day);
      }
      expect(s.habitStreak(id), 4);

      // Punch a hole three days back — the streak stops there.
      s.toggleHabit(id, localDateStr(
          DateTime.now().subtract(const Duration(days: 2))));
      expect(s.habitStreak(id), 2);
    });

    test('an unticked today does not break the streak', () {
      final s = AppState()..seedForTest();
      final id = s.habits.first.id;
      s.habits.first.createdAt =
          localDateStr(DateTime.now().subtract(const Duration(days: 30)));

      // Yesterday and the day before only — today is still open.
      s.toggleHabit(id,
          localDateStr(DateTime.now().subtract(const Duration(days: 1))));
      s.toggleHabit(id,
          localDateStr(DateTime.now().subtract(const Duration(days: 2))));
      expect(s.habitDoneOn(id), isFalse);
      expect(s.habitStreak(id), 2);
    });

    test('removing a habit purges it from history', () {
      final s = AppState()..seedForTest();
      final id = s.habits.first.id;
      s.toggleHabit(id);
      expect(s.dayLogs, isNotEmpty);

      s.removeHabit(id);
      expect(s.habits.any((h) => h.id == id), isFalse);
      expect(s.dayLogs.values.any((l) => l.habits.contains(id)), isFalse);
    });
  });

  // ---------- heatmap ----------
  group('day log + heatmap', () {
    test('study activity outside habits still fills the day', () {
      final s = AppState()..seedForTest();
      final today = localDateStr();

      s.recordFocusSession();
      expect(s.logFor(today).focus, 1);

      s.toggleTopic(s.subjects.first.id, s.subjects.first.topics[1].id);
      expect(s.logFor(today).topics, 1);

      s.toggleGoal(s.goals.first.id);
      expect(s.logFor(today).goals, 1);

      expect(s.logFor(today).activity, 3);
      expect(s.activeDays, 1);
    });

    test('un-ticking a topic does not decrement the log', () {
      // The log records that work happened, not the current checkbox state.
      final s = AppState()..seedForTest();
      final subject = s.subjects.first;
      s.toggleTopic(subject.id, subject.topics[1].id); // tick
      s.toggleTopic(subject.id, subject.topics[1].id); // untick
      expect(s.logFor(localDateStr()).topics, 1);
    });

    test('heat levels scale between 1 and 4 against the busiest day', () {
      final s = AppState()..seedForTest();
      final today = localDateStr();
      final quiet =
          localDateStr(DateTime.now().subtract(const Duration(days: 5)));

      expect(s.heatLevel(today), 0); // nothing logged yet

      s.toggleHabit(s.habits[0].id, quiet); // 1 unit on the quiet day
      for (var i = 0; i < 8; i++) {
        s.recordFocusSession(); // 8 units today
      }

      expect(s.peakActivity, 8);
      expect(s.heatLevel(today), 4);
      expect(s.heatLevel(quiet), inInclusiveRange(1, 2));
      expect(s.heatLevel('2020-01-01'), 0);
    });
  });

  // ---------- persistence shape ----------
  test('state map round-trips habits and day logs', () {
    final s = AppState()..seedForTest();
    s.toggleHabit(s.habits.first.id);
    s.recordFocusSession();

    final blob = s.toStateMap();
    expect(blob['habits'], isNotEmpty);
    expect(blob['dayLogs'], isNotEmpty);
    expect(blob['updatedAt'], isNotNull);

    final restored = AppState()..applyStateMapForTest(blob);
    expect(restored.habits.length, s.habits.length);
    expect(restored.habits.first.name, s.habits.first.name);
    expect(restored.habitDoneOn(s.habits.first.id), isTrue);
    expect(restored.logFor(localDateStr()).focus, 1);
  });

  // ---------- home-screen widget payload ----------
  group('widget payload', () {
    test('carries today\'s due habits with their done state', () {
      final s = AppState()..seedForTest();
      final daily = s.habits.first;
      s.toggleHabit(daily.id);

      final payload = buildWidgetPayload(s.toStateMap());
      final habits = jsonDecode(payload['habits_json']!) as List;

      // The Sunday-only ritual is filtered out unless today is Sunday.
      final expected = DateTime.now().weekday == DateTime.sunday ? 3 : 2;
      expect(habits.length, expected);
      expect(payload['habits_total'], '$expected');

      final first = habits.firstWhere((h) => h['id'] == daily.id);
      expect(first['name'], daily.name);
      expect(first['done'], isTrue);
    });

    test('never exceeds the widget slot count', () {
      final s = AppState()..seedForTest();
      for (var i = 0; i < 10; i++) {
        s.addHabit('Habit $i');
      }
      final habits =
          jsonDecode(buildWidgetPayload(s.toStateMap())['habits_json']!) as List;
      expect(habits.length, kWidgetHabitSlots);
    });

    test('exposes the nearest upcoming countdown', () {
      final s = AppState()..seedForTest();
      s.addEvent('Quiz', localDateStr(DateTime.now().add(const Duration(days: 3))));
      final payload = buildWidgetPayload(s.toStateMap());
      expect(payload['exam_title'], 'Quiz'); // nearer than the seeded exam
    });
  });

  testWidgets('habits tab shows rituals and the year heatmap', (tester) async {
    final state = AppState()..seedForTest();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SwayraApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Get started')); // past the landing
    await tester.pumpAndSettle();

    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();

    expect(find.text('RITUALS'), findsOneWidget);
    expect(find.text('A YEAR, VISUALIZED'), findsOneWidget);
    expect(find.text('QUIET PINGS'), findsOneWidget);
    expect(find.text('Read 30 minutes'), findsOneWidget);
    expect(find.text('0 of 2 rituals done'), findsOneWidget);
  });

  // Reproduces the reported bug: completing a habit then deleting it must not
  // leave a ticked box behind on the row that takes its place.
  testWidgets('deleting a completed habit leaves no ticked box behind',
      (tester) async {
    final state = AppState()..seedForTest();
    // Pre-mark achievements as earned so no toast timer fires during the test.
    state.earned.addAll(achievements.map((a) => a.id));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const SwayraApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();

    // The fix: every ritual row is keyed by its habit id, so a removed row's
    // ticked state can't be reused by the row that takes its place.
    for (final h in state.habits) {
      expect(find.byKey(ValueKey<String>(h.id)), findsOneWidget);
    }

    // Complete the first ritual by SLIDING the row fully to the right (rituals
    // are completed by sliding, not tapping). The list sits below the heatmap,
    // so bring it on-screen first.
    final firstId = state.habits.first.id;
    await tester.ensureVisible(find.text('Read 30 minutes'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Read 30 minutes'), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(state.habitDoneOn(firstId), isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget); // exactly one completed

    // Delete that completed habit.
    state.removeHabit(firstId);
    await tester.pumpAndSettle();

    // The row is gone, none of the remaining rows are done today, and — the
    // crux of the bug — no ticked box is rendered anywhere.
    expect(find.text('Read 30 minutes'), findsNothing);
    final anyDone = state.habitsDueOn().any((h) => state.habitDoneOn(h.id));
    expect(anyDone, isFalse);
    expect(find.byIcon(Icons.check), findsNothing);
  });
}
