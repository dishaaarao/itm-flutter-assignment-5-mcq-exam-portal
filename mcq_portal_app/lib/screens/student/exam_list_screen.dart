import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/exam.dart';
import '../../providers/exam_provider.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';
import 'exam_screen.dart';
import 'result_screen.dart';

/// The student's list of exams they can currently sit.
class ExamListView extends StatelessWidget {
  const ExamListView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExamProvider>();

    if (provider.loading && provider.studentExams.isEmpty) {
      return const LoadingView(message: 'Loading your exams...');
    }

    if (provider.hasError && provider.studentExams.isEmpty) {
      return ErrorView(
        message: provider.error!,
        onRetry: () => context.read<ExamProvider>().loadStudentExams(),
      );
    }

    if (provider.studentExams.isEmpty) {
      return const EmptyView(
        icon: Icons.assignment_outlined,
        title: 'No exams available',
        message:
            'Published exams appear here. If you expected one, check that it is '
            'published and inside its date window.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ExamProvider>().loadStudentExams(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.studentExams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _ExamCard(exam: provider.studentExams[index]),
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final Exam exam;

  Future<void> _open(BuildContext context) async {
    final brief = exam.myAttempt;

    // A submitted attempt goes straight to its stored result.
    if (brief != null && brief.isSubmitted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(attemptId: brief.id)),
      );
      return;
    }

    final proceeding = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _StartExamDialog(exam: exam, resuming: brief != null),
    );

    if (proceeding != true || !context.mounted) return;

    // Awaited so that coming back from a finished exam reloads the list. Without
    // this the card still offers "Start" for an exam already submitted.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExamScreen(examId: exam.id)),
    );

    if (!context.mounted) return;
    await context.read<ExamProvider>().loadStudentExams();
  }

  @override
  Widget build(BuildContext context) {
    final brief = exam.myAttempt;
    final inProgress = brief?.isInProgress ?? false;
    final submitted = brief?.isSubmitted ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exam.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (submitted && brief != null)
                  _StatusPill(
                    label: brief.isPass ? 'PASSED' : 'FAILED',
                    colour: brief.isPass ? AppTheme.accent : AppTheme.danger,
                  )
                else if (inProgress)
                  const _StatusPill(label: 'IN PROGRESS', colour: AppTheme.warning),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              exam.subject,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 13.5),
            ),
            if (exam.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                exam.description,
                style: const TextStyle(color: Color(0xFF475467), height: 1.4, fontSize: 13.5),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(icon: Icons.list_alt_outlined, label: '${exam.questionCount} questions'),
                _MetaChip(icon: Icons.timer_outlined, label: '${exam.duration} min'),
                _MetaChip(icon: Icons.emoji_events_outlined, label: '${_fmt(exam.totalMarks)} marks'),
                _MetaChip(icon: Icons.flag_outlined, label: 'Pass ${_fmt(exam.passingMarks)}'),
                if (exam.hasNegativeMarking)
                  _MetaChip(
                    icon: Icons.remove_circle_outline,
                    label: '-${_fmt(exam.negativeMarking)} per wrong',
                    colour: AppTheme.danger,
                  ),
              ],
            ),
            if (submitted && brief != null) ...[
              const SizedBox(height: 14),
              // A submitted exam still shows the score here, so the student
              // does not have to open the result to remember how they did.
              Row(
                children: [
                  Text(
                    'Scored ${_fmt(brief.score ?? 0)} (${_fmt(brief.percentage ?? 0)}%)',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _open(context),
                icon: Icon(
                  submitted
                      ? Icons.visibility_outlined
                      : inProgress
                          ? Icons.play_circle_outline
                          : Icons.play_arrow_rounded,
                  size: 19,
                ),
                label: Text(
                  submitted
                      ? 'View result'
                      : inProgress
                          ? 'Resume'
                          : 'Start',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(140, 44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trims trailing zeros: 40.0 reads as "40", 17.5 keeps its decimal.
  static String _fmt(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: colour, fontWeight: FontWeight.w700, fontSize: 11.5),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.colour = const Color(0xFF475467),
  });

  final IconData icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12.5, color: colour)),
        ],
      ),
    );
  }
}

/// Restates the exam rules at the moment they matter — the student is about to
/// start a clock they cannot pause.
class _StartExamDialog extends StatelessWidget {
  const _StartExamDialog({required this.exam, required this.resuming});

  final Exam exam;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(resuming ? 'Resume this exam?' : 'Start this exam?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          _rule(Icons.timer_outlined, '${exam.duration} minutes, timed by the server'),
          _rule(Icons.list_alt_outlined, '${exam.questionCount} questions'),
          _rule(Icons.flag_outlined, 'Pass mark: ${_ExamCard._fmt(exam.passingMarks)} of ${_ExamCard._fmt(exam.totalMarks)}'),
          if (exam.hasNegativeMarking)
            _rule(
              Icons.remove_circle_outline,
              '${_ExamCard._fmt(exam.negativeMarking)} marks deducted per wrong answer',
              colour: AppTheme.danger,
            ),
          const SizedBox(height: 12),
          Text(
            resuming
                ? 'Your existing timer continues from where it left off. Closing the app does not pause it.'
                : 'The timer starts as soon as you continue and cannot be paused.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085), height: 1.45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(resuming ? 'Resume' : 'Start now'),
        ),
      ],
    );
  }

  Widget _rule(IconData icon, String text, {Color colour = const Color(0xFF475467)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: colour))),
        ],
      ),
    );
  }
}
