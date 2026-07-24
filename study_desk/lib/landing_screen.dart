import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Brand name shown across the app.
const String kAppName = 'Swayra';

/// The line under the wordmark on the landing screen.
const String kTagline = 'Build Your Best Self, One Ritual at a Time.';

/// Shorter variant, used where space is tight.
const String kTaglineShort = 'Daily Rituals for a Better You';

/// The first thing you see on launch: wordmark, tagline, and a way in.
///
/// Auto-advances after a moment so it never blocks you, and a tap anywhere
/// skips straight through.
class LandingScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const LandingScreen({super.key, required this.onContinue});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  Timer? _auto;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _auto = Timer(const Duration(milliseconds: 2600), _continue);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Guarded so the timer and a tap can't both fire it.
  void _continue() {
    if (_left) return;
    _left = true;
    _auto?.cancel();
    widget.onContinue();
  }

  /// Fade + rise, staggered by [order] so the lines arrive one after another.
  Widget _rise(int order, Widget child) {
    final start = (order * 0.12).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, inner) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - anim.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _continue,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    _rise(
                      0,
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: C.blue600,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.self_improvement,
                            size: 42, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 26),

                    _rise(
                      1,
                      Text(
                        kAppName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: mono(
                            size: 42,
                            weight: FontWeight.w700,
                            color: C.slate900,
                            letterSpacing: 2,
                            height: 1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _rise(
                      1,
                      Text(
                        'by FTA',
                        textAlign: TextAlign.center,
                        style: mono(
                            size: 11,
                            weight: FontWeight.w500,
                            color: C.slate400,
                            letterSpacing: 4),
                      ),
                    ),
                    const SizedBox(height: 18),

                    _rise(
                      2,
                      Container(
                        width: 34,
                        height: 3,
                        decoration: BoxDecoration(
                          color: C.blue600,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    _rise(
                      3,
                      Text(
                        kTagline,
                        textAlign: TextAlign.center,
                        style: sans(
                            size: 15, color: C.slate500, height: 1.5),
                      ),
                    ),

                    const Spacer(flex: 4),

                    _rise(
                      4,
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _continue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: C.slate900,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding:
                                const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                            textStyle:
                                sans(size: 15, weight: FontWeight.w600),
                          ),
                          child: const Text('Get started'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _rise(
                      5,
                      Text('EXAM · FOCUS · STREAK',
                          style: mono(
                              size: 10,
                              color: C.slate300,
                              letterSpacing: 3)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
