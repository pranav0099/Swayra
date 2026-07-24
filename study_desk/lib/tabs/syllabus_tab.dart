import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../theme.dart';

class SyllabusTab extends StatefulWidget {
  const SyllabusTab({super.key});

  @override
  State<SyllabusTab> createState() => _SyllabusTabState();
}

class _SyllabusTabState extends State<SyllabusTab> {
  final _newSubject = TextEditingController();
  final Map<String, TextEditingController> _topicDrafts = {};

  TextEditingController _draftFor(String subjectId) =>
      _topicDrafts.putIfAbsent(subjectId, () => TextEditingController());

  @override
  void dispose() {
    _newSubject.dispose();
    for (final c in _topicDrafts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSubject(AppState state) {
    final v = _newSubject.text.trim();
    if (v.isEmpty) return;
    state.addSubject(v);
    _newSubject.clear();
  }

  void _addTopic(AppState state, String subjectId) {
    final c = _draftFor(subjectId);
    final v = c.text.trim();
    if (v.isEmpty) return;
    state.addTopic(subjectId, v);
    c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final sub in state.subjects) ...[
          _SubjectCard(
            subject: sub,
            draft: _draftFor(sub.id),
            onAddTopic: () => _addTopic(state, sub.id),
            onToggle: (tid) => state.toggleTopic(sub.id, tid),
            onDeleteSubject: () => state.removeSubject(sub.id),
          ),
          const SizedBox(height: 14),
        ],
        // add subject
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: C.slate300, width: 1, style: BorderStyle.solid),
          ),
          child: Row(
            children: [
              Expanded(
                child: FieldInput(
                  controller: _newSubject,
                  hint: 'New subject (e.g. Thermodynamics)',
                  onSubmitted: () => _addSubject(state),
                ),
              ),
              const SizedBox(width: 8),
              DarkButton(
                onPressed: () => _addSubject(state),
                icon: Icons.add,
                label: 'Subject',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final Subject subject;
  final TextEditingController draft;
  final VoidCallback onAddTopic;
  final ValueChanged<String> onToggle;
  final VoidCallback onDeleteSubject;
  const _SubjectCard({
    required this.subject,
    required this.draft,
    required this.onAddTopic,
    required this.onToggle,
    required this.onDeleteSubject,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(subject.name,
                    style: sans(size: 16, weight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: onDeleteSubject,
                icon: const Icon(Icons.delete_outline, size: 16),
                color: C.slate300,
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: subject.pct / 100,
                    minHeight: 8,
                    backgroundColor: C.slate100,
                    valueColor: AlwaysStoppedAnimation(C.emerald500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${subject.pct}%',
                  style: mono(size: 12, color: C.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          ...subject.topics.map((t) => _TopicRow(
                topic: t,
                onTap: () => onToggle(t.id),
              )),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FieldInput(
                  controller: draft,
                  hint: 'Add a topic…',
                  onSubmitted: onAddTopic,
                ),
              ),
              IconButton(
                onPressed: onAddTopic,
                icon: const Icon(Icons.add, size: 18),
                color: C.slate500,
                splashRadius: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final Topic topic;
  final VoidCallback onTap;
  const _TopicRow({required this.topic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: topic.done ? C.emerald500 : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: topic.done ? C.emerald500 : C.slate300),
              ),
              child: topic.done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                topic.name,
                style: sans(
                  size: 14,
                  color: topic.done ? C.slate400 : C.slate700,
                  decoration:
                      topic.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
