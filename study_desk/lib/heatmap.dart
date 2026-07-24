import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// GitHub-style contribution grid: one column per week, one cell per day,
/// shaded by [AppState.heatLevel]. Scrolls horizontally and opens on the most
/// recent week.
class YearHeatmap extends StatelessWidget {
  final AppState state;

  /// How many weeks back to draw (53 ≈ a full year).
  final int weeks;
  final double cell;
  final double gap;
  final ValueChanged<String>? onTapDay;
  final String? selected;

  const YearHeatmap({
    super.key,
    required this.state,
    this.weeks = 53,
    this.cell = 13,
    this.gap = 3,
    this.onTapDay,
    this.selected,
  });

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Palette runs light warm → full Kinetic Orange as a day gets busier.
  /// A getter (not const) so it re-resolves for light/dark themes.
  static List<Color> get levelColors => [
        C.slate100, // 0 — nothing logged
        C.amber100,
        C.amber200,
        C.amber400,
        C.amber500,
      ];

  /// Monday of the earliest week drawn.
  DateTime get _start {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    return thisMonday.subtract(Duration(days: (weeks - 1) * 7));
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final today = localDateStr();

    // The weekday labels stay pinned outside the scroll view — inside it they
    // scroll off-screen as soon as the grid opens on the current week.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayLabels(cell: cell, gap: gap),
        SizedBox(width: gap * 2),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // opens showing the current week
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MonthLabels(
                    start: start, weeks: weeks, cell: cell, gap: gap),
                SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(weeks, (w) {
                    return Padding(
                      padding: EdgeInsets.only(right: gap),
                      child: Column(
                        children: List.generate(7, (d) {
                          final date = start.add(Duration(days: w * 7 + d));
                          final dateStr = localDateStr(date);
                          final future = dateStr.compareTo(today) > 0;
                          return Padding(
                            padding: EdgeInsets.only(bottom: gap),
                            child: _Cell(
                              size: cell,
                              date: dateStr,
                              level: future ? -1 : state.heatLevel(dateStr),
                              isToday: dateStr == today,
                              isSelected: dateStr == selected,
                              log: future ? null : state.logFor(dateStr),
                              onTap: future || onTapDay == null
                                  ? null
                                  : () => onTapDay!(dateStr),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final double size;
  final String date;
  final int level; // -1 = future
  final bool isToday;
  final bool isSelected;
  final DayLog? log;
  final VoidCallback? onTap;

  const _Cell({
    required this.size,
    required this.date,
    required this.level,
    required this.isToday,
    required this.isSelected,
    required this.log,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (level < 0) {
      return SizedBox(width: size, height: size);
    }
    final l = log ?? DayLog();
    final parts = <String>[
      if (l.habits.isNotEmpty) '${l.habits.length} habit${l.habits.length == 1 ? '' : 's'}',
      if (l.focus > 0) '${l.focus} focus',
      if (l.topics > 0) '${l.topics} topic${l.topics == 1 ? '' : 's'}',
      if (l.goals > 0) '${l.goals} goal${l.goals == 1 ? '' : 's'}',
    ];

    return Tooltip(
      message: '${prettyDate(date)}\n'
          '${parts.isEmpty ? 'Nothing logged' : parts.join(' · ')}',
      textStyle: sans(size: 11, color: Colors.white),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: YearHeatmap.levelColors[level],
            borderRadius: BorderRadius.circular(3),
            border: isSelected
                ? Border.all(color: C.slate900, width: 1.5)
                : isToday
                    ? Border.all(color: C.slate600, width: 1)
                    : null,
          ),
        ),
      ),
    );
  }
}

class _DayLabels extends StatelessWidget {
  final double cell;
  final double gap;
  const _DayLabels({required this.cell, required this.gap});

  @override
  Widget build(BuildContext context) {
    // Only Mon / Wed / Fri are labelled, like GitHub, to avoid a wall of text.
    const labels = ['Mon', '', 'Wed', '', 'Fri', '', ''];
    return Padding(
      // push down past the month-label row
      padding: EdgeInsets.only(top: cell + gap + 2),
      child: Column(
        children: List.generate(7, (i) {
          return Container(
            height: cell + gap,
            alignment: Alignment.centerLeft,
            child: Text(labels[i], style: mono(size: 9, color: C.slate400)),
          );
        }),
      ),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  final DateTime start;
  final int weeks;
  final double cell;
  final double gap;
  const _MonthLabels({
    required this.start,
    required this.weeks,
    required this.cell,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    var lastMonth = -1;
    return SizedBox(
      height: cell,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(weeks, (w) {
          final monday = start.add(Duration(days: w * 7));
          // Label the first week that lands in a new month.
          final show = monday.month != lastMonth;
          if (show) lastMonth = monday.month;
          return SizedBox(
            width: cell + gap,
            child: show
                ? Text(YearHeatmap._monthNames[monday.month - 1],
                    style: mono(size: 9, color: C.slate400),
                    overflow: TextOverflow.visible,
                    softWrap: false)
                : null,
          );
        }),
      ),
    );
  }
}

/// "Less ▢▢▢▢▢ More" key shown under the grid.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: mono(size: 9, color: C.slate400)),
        const SizedBox(width: 5),
        ...YearHeatmap.levelColors.map((c) => Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
        const SizedBox(width: 2),
        Text('More', style: mono(size: 9, color: C.slate400)),
      ],
    );
  }
}
