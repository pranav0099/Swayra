import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'landing_screen.dart';
import 'models.dart';
import 'theme.dart';
import 'widget_bridge.dart';
import 'tabs/today_tab.dart';
import 'tabs/habits_tab.dart';
import 'tabs/syllabus_tab.dart';
import 'tabs/goals_tab.dart';
import 'tabs/focus_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved theme before the first frame so there's no light flash.
  await loadSavedTheme();
  try {
    await HomeWidget.setAppGroupId(appGroupId);
    // Lets a tap on the home-screen widget tick a habit off without opening
    // the app — handled in a background isolate by onWidgetTapped.
    await HomeWidget.registerInteractivityCallback(onWidgetTapped);
  } catch (_) {
    // Widget bridge isn't available on web/desktop — fine, the app still runs.
  }
  final state = AppState();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const SwayraApp(),
    ),
  );
  // Load data after first frame.
  state.init();
}

class SwayraApp extends StatelessWidget {
  const SwayraApp({super.key});
  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app whenever the light/dark switch flips, so every
    // C.* colour re-resolves.
    return ValueListenableBuilder<bool>(
      valueListenable: darkMode,
      builder: (context, isDark, _) {
        final brightness = isDark ? Brightness.dark : Brightness.light;
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Inter',
            brightness: brightness,
            scaffoldBackgroundColor: C.paper,
            colorScheme: ColorScheme.fromSeed(
              seedColor: C.blue600,
              primary: C.blue600,
              brightness: brightness,
            ),
          ),
          home: const _Root(),
        );
      },
    );
  }
}

/// Landing screen first, then the app. The landing doubles as the loading
/// screen, so the wait for stored data is never a bare spinner.
///
/// The body is keyed by the current theme: because much of the tree is `const`,
/// a plain rebuild wouldn't re-resolve the C.* colours inside those widgets, so
/// flipping the key forces the whole body to rebuild in the new theme. (The
/// trade-off is that toggling returns you to the Today tab — [_landingDone]
/// lives above the key so the landing screen isn't shown again.)
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _landingDone = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkMode,
      builder: (context, isDark, _) {
        if (!_landingDone) {
          return LandingScreen(
            onContinue: () => setState(() => _landingDone = true),
          );
        }
        return KeyedSubtree(
          key: ValueKey<bool>(isDark),
          child: const _AppBody(),
        );
      },
    );
  }
}

class _AppBody extends StatelessWidget {
  const _AppBody();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Data almost always finishes loading while the landing is on screen.
    if (!state.ready) {
      return Scaffold(
        backgroundColor: C.paper,
        body: Center(child: CircularProgressIndicator(color: C.slate900)),
      );
    }
    return const HomeShell();
  }
}

class _TabDef {
  final String id;
  final String label;
  final IconData icon;
  const _TabDef(this.id, this.label, this.icon);
}

const _tabs = [
  _TabDef('today', 'Today', Icons.calendar_month),
  _TabDef('habits', 'Habits', Icons.self_improvement),
  _TabDef('syllabus', 'Syllabus', Icons.menu_book),
  _TabDef('goals', 'Goals', Icons.track_changes),
  _TabDef('focus', 'Focus', Icons.schedule),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  String tab = 'today';

  void _goTo(String id) => setState(() => tab = id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A widget tap may have edited storage while we were backgrounded.
      context.read<AppState>().reloadFromDisk();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      bottomNavigationBar: _BottomNav(current: tab, onTap: _goTo),
      body: PaperBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      _Header(
                        streak: state.liveStreak,
                        onToggleWidget: isDesktopShell
                            ? () => state.toggleDesktopWidget()
                            : null,
                      ),
                      const SizedBox(height: 22),
                      _tabBody(state),
                    ],
                  ),
                ),
              ),
              if (state.justEarned != null)
                _AchievementToast(achievement: state.justEarned!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBody(AppState state) {
    switch (tab) {
      case 'habits':
        return const HabitsTab();
      case 'syllabus':
        return const SyllabusTab();
      case 'goals':
        return const GoalsTab();
      case 'focus':
        return const FocusTab();
      case 'today':
      default:
        return TodayTab(onJump: _goTo);
    }
  }
}

class _Header extends StatelessWidget {
  final int streak;
  final VoidCallback? onToggleWidget;
  const _Header({
    required this.streak,
    this.onToggleWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: C.slate200, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.self_improvement, color: C.blue600, size: 26),
          const SizedBox(width: 10),
          // Expanded (rather than a fixed Column + Spacer) so the wordmark
          // gives way on narrow screens and at large font scales instead of
          // overflowing the row.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(kAppName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                        size: 18,
                        weight: FontWeight.w700,
                        color: C.slate900,
                        letterSpacing: 0.5,
                        height: 1)),
                const SizedBox(height: 2),
                Text(kTaglineShort,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(size: 11, color: C.slate500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Streak chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: C.amber50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: C.amber200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department,
                    size: 16,
                    color: streak > 0 ? C.amber500 : C.slate300),
                const SizedBox(width: 6),
                Text('$streak',
                    style: mono(
                        size: 14,
                        weight: FontWeight.w700,
                        color: C.slate800)),
                const SizedBox(width: 4),
                Text(streak == 1 ? 'day' : 'days',
                    style: sans(size: 11, color: C.slate500)),
              ],
            ),
          ),
          // Light / dark toggle
          const SizedBox(width: 8),
          Tooltip(
            message: darkMode.value ? 'Switch to light mode' : 'Switch to dark mode',
            child: Material(
              color: C.slate100,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => toggleTheme(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    darkMode.value ? Icons.light_mode : Icons.dark_mode,
                    size: 18,
                    color: darkMode.value ? C.amber400 : C.slate600,
                  ),
                ),
              ),
            ),
          ),
          // Desktop widget toggle button (only shown inside Electron)
          if (onToggleWidget != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Toggle desktop countdown widget',
              child: Material(
                color: C.slate100,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onToggleWidget,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.widgets_outlined,
                        size: 18, color: C.slate600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom navigation bar (Stitch "Minimalist Orange White Desk"): white bar with
/// a thin top border; the active tab is an orange pill with white icon + label.
class _BottomNav extends StatelessWidget {
  final String current;
  final ValueChanged<String> onTap;
  const _BottomNav({required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.white,
        border: Border(top: BorderSide(color: C.slate200, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          // Five tabs no longer fit at a fixed width on a narrow phone, so each
          // pill takes an equal share of the bar instead.
          child: Row(
            children: _tabs.map((t) {
              final active = current == t.id;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onTap(t.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? C.blue600 : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon,
                            size: 22,
                            color: active ? Colors.white : C.slate500),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(t.label,
                              maxLines: 1,
                              style: mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color:
                                      active ? Colors.white : C.slate500,
                                  letterSpacing: 0.3)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _AchievementToast extends StatelessWidget {
  final Achievement achievement;
  const _AchievementToast({required this.achievement});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: C.slate900,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: C.amber400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.emoji_events,
                    size: 18, color: C.slate900),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ACHIEVEMENT UNLOCKED',
                      style: mono(
                          size: 11,
                          color: C.amber300,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text(achievement.title,
                      style: sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: Colors.white)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
