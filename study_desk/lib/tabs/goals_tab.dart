import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../theme.dart';

class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});

  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _add(AppState state) {
    final v = _draft.text.trim();
    if (v.isEmpty) return;
    state.addGoal(v);
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final goals = state.goals;
    final done = goals.where((g) => g.done).length;
    final pct = goals.isEmpty ? 0 : ((done / goals.length) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          hero: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('THIS WEEK',
                        style: mono(
                            size: 12,
                            color: C.blue600,
                            letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text('$done of ${goals.length} goals done',
                        style: sans(size: 14, color: C.slate600)),
                  ],
                ),
              ),
              Text('$pct%',
                  style: mono(
                      size: 34, weight: FontWeight.w700, color: C.slate800)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...goals.map((g) => _GoalRow(
              key: ValueKey(g.id),
              goal: g,
              onToggle: () => state.toggleGoal(g.id),
              onDelete: () => state.removeGoal(g.id),
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.slate300),
          ),
          child: Row(
            children: [
              Expanded(
                child: FieldInput(
                  controller: _draft,
                  hint: 'Add a weekly goal…',
                  onSubmitted: () => _add(state),
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
        ),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  final Goal goal;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _GoalRow({
    super.key,
    required this.goal,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.slate200),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: goal.done ? C.blue600 : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border:
                    Border.all(color: goal.done ? C.blue600 : C.slate300),
              ),
              child: goal.done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              goal.text,
              style: sans(
                size: 14,
                color: goal.done ? C.slate400 : C.slate700,
                decoration:
                    goal.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 15),
            color: C.slate300,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}
