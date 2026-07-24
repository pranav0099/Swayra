import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../heatmap.dart';
import '../models.dart';
import '../theme.dart';

class HabitsTab extends StatefulWidget {
  const HabitsTab({super.key});

  @override
  State<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends State<HabitsTab> {
  /// Day picked in the heatmap; null = today.
  String? _selected;

  String get _viewDate => _selected ?? localDateStr();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final due = state.habitsDueOn(_viewDate);
    final done = due.where((h) => state.habitDoneOn(h.id, _viewDate)).length;
    final pct = due.isEmpty ? 0 : ((done / due.length) * 100).round();
    final isToday = _viewDate == localDateStr();
    final bestStreak = state.habits.fold<int>(0, (m, h) {
      final s = state.habitStreak(h.id);
      return s > m ? s : m;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // hero — today's rituals
        Panel(
          hero: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isToday ? 'TODAY' : 'ON THIS DAY',
                        style:
                            mono(size: 12, color: C.blue600, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(
                      due.isEmpty
                          ? 'No rituals due'
                          : '$done of ${due.length} ritual${due.length == 1 ? '' : 's'} done',
                      style: sans(size: 14, color: C.slate600),
                    ),
                    if (!isToday) ...[
                      const SizedBox(height: 2),
                      Text(prettyDate(_viewDate),
                          style: mono(size: 11, color: C.slate400)),
                    ],
                  ],
                ),
              ),
              Text('$pct%',
                  style: mono(
                      size: 34, weight: FontWeight.w700, color: C.slate800)),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // streak + consistency stats
        Row(
          children: [
            Expanded(
              child: _Mini(
                icon: Icons.local_fire_department,
                tone: C.amber500,
                value: '$bestStreak',
                label: 'Best live streak',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Mini(
                icon: Icons.event_available,
                tone: C.emerald500,
                value: '${state.activeDays}',
                label: 'Days shown up',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // year heatmap — moved up into the top slot (was below the list)
        const Caption('A YEAR, VISUALIZED'),
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YearHeatmap(
                state: state,
                selected: _selected,
                onTapDay: (d) => setState(
                    () => _selected = d == _selected ? null : d),
              ),
              const SizedBox(height: 10),
              const HeatmapLegend(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap any square to review that day. Focus sessions, topics and goals '
          'all count towards the shade.',
          style: sans(size: 11, color: C.slate400, height: 1.4),
        ),
        const SizedBox(height: 24),

        // habit list — now below the heatmap
        Row(
          children: [
            const Caption('RITUALS'),
            const Spacer(),
            if (!isToday)
              TextButton.icon(
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.today, size: 14),
                label: Text('Back to today', style: mono(size: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: C.blue600,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.habits.isEmpty)
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Column(
              children: [
                Icon(Icons.self_improvement, color: C.slate300, size: 32),
                const SizedBox(height: 8),
                Text('One habit at a time.',
                    style: sans(
                        size: 14,
                        weight: FontWeight.w600,
                        color: C.slate700)),
                const SizedBox(height: 4),
                Text('Add a ritual below and show up daily.',
                    textAlign: TextAlign.center,
                    style: sans(size: 13, color: C.slate500)),
              ],
            ),
          )
        else
          ...state.habits.map((h) => _HabitRow(
                // Keyed by habit id so removing a row doesn't carry its ticked
                // state onto the row that slides up into its place.
                key: ValueKey(h.id),
                habit: h,
                date: _viewDate,
                done: state.habitDoneOn(h.id, _viewDate),
                due: h.isDueOn(_viewDate),
                streak: state.habitStreak(h.id),
                onToggle: () => state.toggleHabit(h.id, _viewDate),
                onEdit: () => _openHabitSheet(context, state, habit: h),
              )),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _openHabitSheet(context, state),
          icon: const Icon(Icons.add, size: 16),
          label: Text('New ritual', style: sans(size: 14, weight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.slate700,
            side: BorderSide(color: C.slate200),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 22),

        // reminders master switch — now at the bottom
        const Caption('QUIET PINGS'),
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            children: [
              Icon(
                  state.remindersEnabled
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: state.remindersEnabled ? C.blue600 : C.slate400),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reminders',
                        style: sans(
                            size: 13,
                            weight: FontWeight.w500,
                            color: C.slate700)),
                    Text(
                      state.remindersEnabled
                          ? 'Habit nudges + exam alerts are on'
                          : 'Off — turn on to be reminded',
                      style: sans(size: 11, color: C.slate400),
                    ),
                  ],
                ),
              ),
              Switch(
                value: state.remindersEnabled,
                activeThumbColor: C.blue600,
                activeTrackColor: const Color(0x4DFF5C00),
                onChanged: (v) => state.setRemindersEnabled(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openHabitSheet(BuildContext context, AppState state,
      {Habit? habit}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HabitSheet(state: state, habit: habit),
    );
  }
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String value;
  final String label;
  const _Mini({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          // These cards sit two-to-a-row, so the label has to be allowed to
          // shrink rather than push the card past its half of the screen.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(
                        size: 22, weight: FontWeight.w700, color: C.slate800)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(size: 10, color: C.slate400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A ritual you complete by *sliding* the row to fill it, not by tapping.
/// Slide a due row past ~85% to mark it done; slide a done row back under half
/// to undo. The trailing "…" stays a normal tap for editing.
class _HabitRow extends StatefulWidget {
  final Habit habit;
  final String date;
  final bool done;
  final bool due;
  final int streak;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _HabitRow({
    super.key,
    required this.habit,
    required this.date,
    required this.done,
    required this.due,
    required this.streak,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  State<_HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends State<_HabitRow> {
  // Fill progress 0..1. Tracks `done` except while a drag is in progress.
  late double _p = widget.done ? 1 : 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(_HabitRow old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.done != widget.done) {
      _p = widget.done ? 1 : 0;
    }
  }

  void _onDragEnd() {
    setState(() {
      _dragging = false;
      if (!widget.done && _p >= 0.85) {
        widget.onToggle(); // slid far enough → complete
        _p = 1;
      } else if (widget.done && _p <= 0.5) {
        widget.onToggle(); // slid back → undo
        _p = 0;
      } else {
        _p = widget.done ? 1 : 0; // didn't reach threshold → snap back
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final done = widget.done;
    final due = widget.due;

    return Opacity(
      opacity: due ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) {
                  final width = cons.maxWidth;
                  return GestureDetector(
                    onHorizontalDragStart:
                        due ? (_) => setState(() => _dragging = true) : null,
                    onHorizontalDragUpdate: due
                        ? (d) => setState(() =>
                            _p = (_p + d.delta.dx / width).clamp(0.0, 1.0))
                        : null,
                    onHorizontalDragEnd: due ? (_) => _onDragEnd() : null,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: done ? C.amber200 : C.slate200),
                      ),
                      child: Stack(
                        children: [
                          // Orange fill that grows from the left as you slide.
                          // Positioned.fill so it matches the row's own height
                          // (which flexes with the text scale).
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _p,
                              child: Container(
                                color: C.blue600.withValues(
                                    alpha: _dragging ? 0.20 : 0.14),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: done ? C.blue600 : C.slate50,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: done ? C.blue600 : C.slate300,
                                        width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: done
                                      ? const Icon(Icons.check,
                                          size: 18, color: Colors.white)
                                      : Text(habit.emoji,
                                          style:
                                              const TextStyle(fontSize: 15)),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        habit.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: sans(
                                          size: 14,
                                          weight: FontWeight.w500,
                                          color:
                                              done ? C.slate500 : C.slate800,
                                          decoration: done
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        !due
                                            ? '${habit.scheduleLabel} · not due'
                                            : done
                                                ? 'Done · slide back to undo'
                                                : 'Slide to complete',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: mono(
                                            size: 10, color: C.slate400),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.streak > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: C.amber50,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                            Icons.local_fire_department,
                                            size: 13,
                                            color: C.amber500),
                                        const SizedBox(width: 3),
                                        Text('${widget.streak}',
                                            style: mono(
                                                size: 12,
                                                weight: FontWeight.w700,
                                                color: C.slate800)),
                                      ],
                                    ),
                                  ),
                                ],
                                if (due && !done) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                      Icons.keyboard_double_arrow_right,
                                      size: 18,
                                      color: C.slate300),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.more_horiz, size: 17),
              color: C.slate300,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create / edit sheet. Doubles as the delete entry point when [habit] is set.
class _HabitSheet extends StatefulWidget {
  final AppState state;
  final Habit? habit;
  const _HabitSheet({required this.state, this.habit});

  @override
  State<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<_HabitSheet> {
  static const _emojis = [
    '✓', '📖', '🧠', '📝', '💪', '🏃', '💧', '🧘', '🌅', '🎧', '💻', '🌙'
  ];

  late final TextEditingController _name =
      TextEditingController(text: widget.habit?.name ?? '');
  late String _emoji = widget.habit?.emoji ?? '✓';
  late final Set<int> _days = {...(widget.habit?.days ?? {1, 2, 3, 4, 5, 6, 7})};
  late int? _reminder = widget.habit?.reminderMinutes;

  bool get _isEdit => widget.habit != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickReminder() async {
    final initial = _reminder ?? 20 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked != null) {
      setState(() => _reminder = picked.hour * 60 + picked.minute);
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _days.isEmpty) return;
    if (_isEdit) {
      widget.state.updateHabit(
        widget.habit!.id,
        name: name,
        emoji: _emoji,
        days: _days,
        reminderMinutes: _reminder,
        clearReminder: _reminder == null,
      );
    } else {
      widget.state.addHabit(name,
          emoji: _emoji, days: _days, reminderMinutes: _reminder);
    }
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.state.removeHabit(widget.habit!.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: C.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: C.slate200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_isEdit ? 'Edit ritual' : 'New ritual',
                  style: mono(
                      size: 17, weight: FontWeight.w700, color: C.slate900)),
              const SizedBox(height: 14),

              FieldInput(
                controller: _name,
                hint: 'e.g. Read 30 minutes',
                onSubmitted: _save,
              ),
              const SizedBox(height: 16),

              const Caption('ICON'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emojis.map((e) {
                  final active = e == _emoji;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: active ? C.amber50 : C.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: active ? C.blue600 : C.slate200,
                            width: active ? 1.5 : 1),
                      ),
                      alignment: Alignment.center,
                      child:
                          Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              const Caption('REPEATS ON'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final day = i + 1; // DateTime.monday == 1
                  final active = _days.contains(day);
                  return GestureDetector(
                    onTap: () => setState(() {
                      active ? _days.remove(day) : _days.add(day);
                    }),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: active ? C.slate900 : C.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: active ? C.slate900 : C.slate200),
                      ),
                      alignment: Alignment.center,
                      child: Text(dayNames[i],
                          style: mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: active ? Colors.white : C.slate500)),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),

              const Caption('REMINDER'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickReminder,
                      icon: const Icon(Icons.notifications_none, size: 16),
                      label: Text(
                        _reminder == null
                            ? 'No reminder'
                            : 'Every day at '
                                '${(_reminder! ~/ 60).toString().padLeft(2, '0')}:'
                                '${(_reminder! % 60).toString().padLeft(2, '0')}',
                        style: mono(size: 13, color: C.slate700),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: C.slate200),
                        foregroundColor: C.slate700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  if (_reminder != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => _reminder = null),
                      icon: const Icon(Icons.close, size: 18),
                      color: C.slate400,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),

              Row(
                children: [
                  if (_isEdit) ...[
                    OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: C.rose500,
                        side: BorderSide(color: C.slate200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: sans(size: 14, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.slate900,
                        foregroundColor: C.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: sans(size: 14, weight: FontWeight.w600),
                      ),
                      child: Text(_isEdit ? 'Save' : 'Create ritual'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
