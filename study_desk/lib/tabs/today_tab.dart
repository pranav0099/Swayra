import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../theme.dart';

class TodayTab extends StatefulWidget {
  final ValueChanged<String> onJump;
  const TodayTab({super.key, required this.onJump});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  final _title = TextEditingController();
  String? _date; // yyyy-MM-dd

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _date = localDateStr(picked));
  }

  void _add(AppState state) {
    if (_title.text.trim().isEmpty || _date == null) return;
    state.addEvent(_title.text.trim(), _date!);
    setState(() {
      _title.clear();
      _date = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final next = state.nextEvent;
    final sorted = [...state.events]
      ..sort((a, b) => daysUntil(a.date) - daysUntil(b.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // hero countdown
        Panel(
          hero: true,
          padding: const EdgeInsets.all(24),
          child: next == null
              ? Column(
                  children: [
                    Icon(Icons.calendar_month,
                        color: C.slate300, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming exams yet — add one below to start your countdown.',
                      textAlign: TextAlign.center,
                      style: sans(size: 14, color: C.slate500),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT UP',
                        style: mono(
                            size: 12,
                            color: C.blue600,
                            letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(next.title,
                        style: sans(
                            size: 18,
                            weight: FontWeight.w600,
                            color: C.slate700)),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${daysUntil(next.date)}',
                            style: mono(
                                size: 64,
                                weight: FontWeight.w700,
                                color: C.slate900,
                                height: 1)),
                        const SizedBox(width: 10),
                        // Flexible so a four-digit countdown (or a large font
                        // scale) shortens the label instead of overflowing.
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                                daysUntil(next.date) == 1
                                    ? 'day left'
                                    : 'days left',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(size: 18, color: C.slate500)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: C.slate300),
                    const SizedBox(height: 8),
                    Text(prettyDate(next.date),
                        style: mono(size: 12, color: C.slate500)),
                  ],
                ),
        ),
        const SizedBox(height: 22),

        // quick stats
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.local_fire_department,
                tone: C.amber500,
                value: '${state.liveStreak}',
                label: 'Streak',
                sub: state.liveStreak == 1 ? 'day' : 'days',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.schedule,
                tone: C.tertiary,
                value: '${state.sessionsToday}',
                label: 'Focus today',
                sub: 'sessions',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.menu_book,
                tone: C.emerald500,
                value: '${state.overallPct}%',
                label: 'Syllabus',
                sub: '${state.doneTopics}/${state.totalTopics} topics',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // all countdowns
        const Caption('ALL COUNTDOWNS'),
        const SizedBox(height: 8),
        ...sorted.map((ev) => _CountdownRow(
              event: ev,
              onDelete: () => state.removeEvent(ev.id),
            )),
        const SizedBox(height: 12),
        const _QuoteCard(),
        const SizedBox(height: 12),

        // add event
        Panel(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              FieldInput(
                controller: _title,
                hint: 'Exam or event name',
                onSubmitted: () => _add(state),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_date ?? 'Pick date',
                          style: mono(size: 13, color: C.slate700)),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: C.slate200),
                        foregroundColor: C.slate700,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DarkButton(
                    onPressed: () => _add(state),
                    icon: Icons.add,
                    label: 'Add',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dark motto card that closes out the Today tab.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: C.slate900,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Everything is. Everything will be. Crazy. 🔥',
        style: sans(
            size: 19,
            weight: FontWeight.w600,
            color: Colors.white,
            height: 1.35),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String value;
  final String label;
  final String sub;
  const _StatCard({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(height: 4),
          Text(value,
              style: mono(
                  size: 24, weight: FontWeight.w700, color: C.slate800)),
          const SizedBox(height: 2),
          Text(label,
              style: sans(size: 11, color: C.slate400, height: 1.1)),
          Text(sub, style: sans(size: 10, color: C.slate300)),
        ],
      ),
    );
  }
}

class _CountdownRow extends StatelessWidget {
  final StudyEvent event;
  final VoidCallback onDelete;
  const _CountdownRow({required this.event, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final d = daysUntil(event.date);
    final past = d < 0;
    final color = past
        ? C.slate300
        : d <= 7
            ? C.rose500
            : C.slate900;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.slate200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: sans(
                        size: 14,
                        weight: FontWeight.w500,
                        color: C.slate800)),
                const SizedBox(height: 2),
                Text(prettyDate(event.date),
                    style: mono(size: 12, color: C.slate400)),
              ],
            ),
          ),
          Text(past ? 'done' : '${d}d',
              style: mono(
                  size: 14, weight: FontWeight.w700, color: color)),
          const SizedBox(width: 10),
          _DeleteButton(onTap: onDelete),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.delete_outline, size: 16),
      color: C.slate300,
      hoverColor: Colors.transparent,
      splashRadius: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.hovered) ? C.rose500 : C.slate300),
      ),
    );
  }
}
