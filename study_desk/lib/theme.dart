import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global light/dark switch. Every colour in [C] resolves against this, and the
/// app (see SwayraApp) rebuilds whenever it flips.
final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);

const String _themeKey = 'swayra:darkMode';

/// Restores the saved theme. Call once before runApp so the first frame is
/// already in the right mode.
Future<void> loadSavedTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    darkMode.value = prefs.getBool(_themeKey) ?? false;
  } catch (_) {}
}

/// Flips light ⇄ dark and remembers the choice.
Future<void> toggleTheme() async {
  darkMode.value = !darkMode.value;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, darkMode.value);
  } catch (_) {}
}

/// "Swayra Kinetic": one vibrant orange accent (#FF5C00) over a light *or* dark
/// neutral ground. Colours are getters (not constants) so the same names return
/// the right value for the current theme — every screen recolours at once.
///
/// Names are kept from the old scheme; treat them semantically, not literally
/// (e.g. `white` is "card surface", light in day / near-black at night).
class C {
  static bool get _d => darkMode.value;
  static Color _p(int light, int dark) => Color(_d ? dark : light);

  static Color get paper => _p(0xFFFFFFFF, 0xFF0F1112); // app background
  static Color get white => _p(0xFFFFFFFF, 0xFF1A1D1E); // card / surface

  // Neutral ramp. In dark mode it inverts: "900" reads light, "50" reads dark.
  static Color get slate900 => _p(0xFF191C1D, 0xFFF1F2F3); // text / dark buttons
  static Color get slate800 => _p(0xFF191C1D, 0xFFEDEEEF); // primary text / numbers
  static Color get slate700 => _p(0xFF33373A, 0xFFC4C6C8);
  static Color get slate600 => _p(0xFF5F5E5E, 0xFFA6A6A6); // secondary text
  static Color get slate500 => _p(0xFF5F5E5E, 0xFFA6A6A6);
  static Color get slate400 => _p(0xFF9A9A9A, 0xFF7C7E7F); // muted
  static Color get slate300 => _p(0xFFC8C6C5, 0xFF54585B);
  static Color get slate200 => _p(0xFFE4BEB1, 0xFF39302B); // warm 1px card border
  static Color get slate100 => _p(0xFFEDEEEF, 0xFF2A2E30); // divider / track
  static Color get slate50 => _p(0xFFF3F4F5, 0xFF23272A);

  // Kinetic Orange — the single vibrant accent, unchanged across themes.
  static Color get blue600 => _p(0xFFFF5C00, 0xFFFF5C00); // accent
  static Color get emerald500 => _p(0xFFFF5C00, 0xFFFF5C00); // progress / checks
  static Color get orange => _p(0xFFFF5C00, 0xFFFF5C00);
  static Color get charcoal => _p(0xFF191C1D, 0xFFF1F2F3);
  static Color get tertiary => _p(0xFF0061A6, 0xFF4FA3E3); // Focus accent (blue)

  // Streak chip = warm orange tints; dark warm browns at night.
  static Color get amber50 => _p(0xFFFFDBCE, 0xFF3A2417); // chip background
  static Color get amber100 => _p(0xFFFFD0BB, 0xFF44291A);
  static Color get amber200 => _p(0xFFFFB59A, 0xFF5A3722); // chip border
  static Color get amber300 => _p(0xFFFFB59A, 0xFF5A3722);
  static Color get amber400 => _p(0xFFFF7A3C, 0xFFFF7A3C);
  static Color get amber500 => _p(0xFFFF5C00, 0xFFFF5C00); // fire icon
  static Color get amber600 => _p(0xFFC2410C, 0xFFD4551A);

  static Color get rose500 => _p(0xFFBA1A1A, 0xFFFF6B6B); // error / urgent
}

// "mono" historically meant the technical/heading face — now Geist (per design).
const String kMono = 'Geist';

// `color` is nullable (not defaulted) because C colours are now getters, and
// default parameter values must be compile-time constants.
TextStyle mono({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? letterSpacing,
  double? height,
}) =>
    TextStyle(
      fontFamily: kMono,
      fontSize: size,
      fontWeight: weight,
      color: color ?? C.slate800,
      letterSpacing: letterSpacing,
      height: height,
    );

TextStyle sans({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  TextDecoration? decoration,
}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      color: color ?? C.slate800,
      height: height,
      decoration: decoration,
    );

/// Plain, flat background surface — no grid (clean backdrop as requested).
class PaperBackground extends StatelessWidget {
  final Widget child;
  const PaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(color: C.paper, child: child);
}

/// A white card. [hero] gives it the bold 2px slate-900 border.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hero;
  final bool dashed;
  final Color? border;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.hero = false,
    this.dashed = false,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = border ?? C.slate200;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: C.white,
        // Flat & minimal: white card, soft 8px radius, 1px warm border, no shadow.
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }
}

/// Small uppercase mono caption like "ALL COUNTDOWNS".
class Caption extends StatelessWidget {
  final String text;
  final Color? color;
  const Caption(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: mono(
            size: 11,
            weight: FontWeight.w700,
            color: color ?? C.slate500,
            letterSpacing: 2),
      );
}

/// A pill button used for primary actions ("Add", "Subject"...).
class DarkButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  const DarkButton(
      {super.key,
      required this.onPressed,
      required this.icon,
      required this.label});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: C.slate900,
        foregroundColor: C.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: sans(size: 14, weight: FontWeight.w600),
      ),
    );
  }
}

/// A bordered text field matching the design.
class FieldInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onSubmitted;
  final bool mono;
  const FieldInput({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSubmitted?.call(),
      style: mono
          ? TextStyle(fontFamily: kMono, fontSize: 14, color: C.slate800)
          : sans(size: 14, color: C.slate800),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: sans(size: 14, color: C.slate400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: C.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: C.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          // Focus is signalled by the border turning primary orange.
          borderSide: BorderSide(color: C.blue600, width: 1.5),
        ),
      ),
    );
  }
}
