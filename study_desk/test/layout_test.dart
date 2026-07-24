// Guards against layout overflow on small screens and at large font scales.
//
// A RenderFlex overflow throws in debug builds, which is what a debug APK on a
// real phone surfaces as a full-screen red error box — so these are real
// crashes to users, not cosmetic warnings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:study_desk/main.dart';
import 'package:study_desk/models.dart';
import 'package:study_desk/theme.dart';

const _tabs = ['Today', 'Habits', 'Syllabus', 'Goals', 'Focus'];

/// Pumps the app and steps past the landing screen, so tests start on Today.
Future<void> _pumpApp(WidgetTester tester, {double textScale = 1.0}) async {
  final state = AppState()..seedForTest();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const SwayraApp(),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(320, 720), // small phone
    Size(360, 800), // the common Android size
    Size(412, 915), // large phone
  ]) {
    testWidgets('no overflow on any tab at ${size.width.toInt()}dp',
        (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester);

      for (final tab in _tabs) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '$tab tab overflowed at ${size.width}dp');
      }
    });
  }

  testWidgets('no overflow with accessibility text scaling', (tester) async {
    tester.view.physicalSize = const Size(360, 800) * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, textScale: 1.3);

    for (final tab in _tabs) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '$tab tab overflowed at 1.3x text scale');
    }
  });

  testWidgets('the Focus mode pills build (Material shape/borderRadius clash)',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    // Both pills must exist; the inactive one used to throw during build.
    expect(find.text('Focus 25'), findsOneWidget);
    expect(find.text('Break 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no sign-in or account UI anywhere in the header',
      (tester) async {
    await _pumpApp(tester);

    // The app is offline-only: nothing should offer an account or sync.
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    expect(find.textContaining('Sign in'), findsNothing);
  });

  testWidgets('theme toggle switches between light and dark', (tester) async {
    addTearDown(() => darkMode.value = false); // don't leak into other tests
    await _pumpApp(tester);

    expect(darkMode.value, isFalse);

    // Light → dark. The button (and its tooltip) must flip, proving the body
    // actually rebuilt in the new theme rather than staying light.
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(darkMode.value, isTrue);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    expect(find.byTooltip('Switch to dark mode'), findsNothing);

    // Dark → light again.
    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    expect(darkMode.value, isFalse);
    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
  });

  testWidgets('Habits tab has no groups entry', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();

    expect(find.text('SHOW UP TOGETHER'), findsNothing);
    expect(find.text('Groups'), findsNothing);
    // The rest of the tab is untouched.
    expect(find.text('RITUALS'), findsOneWidget);
    expect(find.text('A YEAR, VISUALIZED'), findsOneWidget);
    expect(find.text('QUIET PINGS'), findsOneWidget);
  });

  testWidgets('Today tab shows the motto and no widget settings',
      (tester) async {
    await _pumpApp(tester);

    expect(find.text('Everything is. Everything will be. Crazy. 🔥'),
        findsOneWidget);
    // Just the quote now — the "TODAY'S FIRE" label was removed.
    expect(find.text('TODAY’S FIRE'), findsNothing);
    expect(find.text('WIDGET SETTINGS'), findsNothing);
    expect(find.text('Pin Widget to Home Screen'), findsNothing);
    expect(find.text('Pin Widget to Wallpaper'), findsNothing);
  });
}
