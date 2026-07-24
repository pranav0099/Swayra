import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../notifications.dart';
import '../theme.dart';

const int kWork = 25 * 60;
const int kBreak = 5 * 60;

class FocusTab extends StatefulWidget {
  const FocusTab({super.key});

  @override
  State<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends State<FocusTab> {
  String mode = 'work'; // 'work' | 'break'
  int secs = kWork;
  bool running = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    Notifications.instance.cancelFocusNotification();
    super.dispose();
  }

  void _setRunning(bool value) async {
    setState(() => running = value);
    _timer?.cancel();
    final label = mode == 'work' ? 'Focus Session' : 'Break Time';
    if (value) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      await Notifications.instance.requestPermission();
      await Notifications.instance.showFocusOngoingNotification(
        modeLabel: label,
        remainingSeconds: secs,
        isPaused: false,
      );
    } else {
      await Notifications.instance.showFocusOngoingNotification(
        modeLabel: label,
        remainingSeconds: secs,
        isPaused: true,
      );
    }
  }

  void _tick() {
    if (secs <= 0) {
      _complete();
      return;
    }
    setState(() => secs--);
  }

  void _complete() {
    _timer?.cancel();
    Notifications.instance.cancelFocusNotification();
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
    final state = context.read<AppState>();
    if (mode == 'work') {
      state.recordFocusSession();
      setState(() {
        mode = 'break';
        secs = kBreak;
        running = false;
      });
    } else {
      setState(() {
        mode = 'work';
        secs = kWork;
        running = false;
      });
    }
  }

  void _switchMode(String m) {
    _timer?.cancel();
    Notifications.instance.cancelFocusNotification();
    setState(() {
      mode = m;
      secs = m == 'work' ? kWork : kBreak;
      running = false;
    });
  }

  void _reset() {
    _timer?.cancel();
    Notifications.instance.cancelFocusNotification();
    setState(() {
      running = false;
      secs = mode == 'work' ? kWork : kBreak;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final total = mode == 'work' ? kWork : kBreak;
    final pct = (secs / total).clamp(0.0, 1.0);
    final shown = math.max(0, secs);
    final mm = (shown ~/ 60).toString().padLeft(2, '0');
    final ss = (shown % 60).toString().padLeft(2, '0');
    final ringColor = mode == 'work' ? C.blue600 : C.emerald500;

    return Column(
      children: [
        // mode toggle — Wrap so the pills stack on a narrow screen or at a
        // large font scale instead of overflowing the row.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _ModePill(
              label: 'Focus 25',
              active: mode == 'work',
              onTap: () => _switchMode('work'),
            ),
            _ModePill(
              label: 'Break 5',
              active: mode == 'break',
              onTap: () => _switchMode('break'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ring + time
        SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: _RingPainter(progress: pct, color: ringColor),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$mm:$ss',
                      style: mono(
                          size: 56,
                          weight: FontWeight.w700,
                          color: C.slate900)),
                  const SizedBox(height: 4),
                  Text(
                    mode == 'work' ? 'STAY FOCUSED' : 'TAKE A BREAK',
                    style: mono(
                        size: 12, color: C.slate400, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // controls — Wrap for the same reason as the mode toggle above.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () => _setRunning(!running),
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
              label: Text(running ? 'Pause' : 'Start'),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.slate900,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                textStyle: sans(size: 14, weight: FontWeight.w600),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.slate600,
                side: BorderSide(color: C.slate200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                textStyle: sans(size: 14, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // mini stats
        Row(
          children: [
            Expanded(child: _MiniStat(label: 'Today', value: state.sessionsToday)),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(label: 'Total', value: state.focus.total)),
            const SizedBox(width: 10),
            Expanded(
                child: _MiniStat(label: 'Minutes', value: state.focus.minutes)),
          ],
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModePill(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    // Material forbids passing `borderRadius` and `shape` together, so the
    // rounded edge and the outline both go through `shape`.
    return Material(
      color: active ? C.slate900 : C.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: active
            ? BorderSide.none
            : BorderSide(color: C.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(label,
              style: sans(
                  size: 14,
                  weight: FontWeight.w500,
                  color: active ? Colors.white : C.slate500)),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text('$value',
              style: mono(
                  size: 24, weight: FontWeight.w700, color: C.slate800)),
          const SizedBox(height: 2),
          Text(label, style: sans(size: 11, color: C.slate400)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 1.0 full -> 0.0 empty
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..color = C.slate200
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
