import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/exam.dart';
import '../../providers/exam_provider.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';
import 'exam_report_screen.dart';

/// Every exam the admin has created, with the way into each one's report.
class ManageExamsScreen extends StatefulWidget {
  const ManageExamsScreen({super.key});

  @override
  State<ManageExamsScreen> createState() => _ManageExamsScreenState();
}

class _ManageExamsScreenState extends State<ManageExamsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExamProvider>().loadAdminExams();
    });
  }

  Future<void> _confirmDelete(Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this exam?'),
        content: Text(
          '"${exam.title}" and its ${exam.questionCount} questions will be removed, '
          'along with every student attempt on it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final message = await context.read<ExamProvider>().deleteExam(exam.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'Exam deleted.'),
        backgroundColor: message == null ? null : AppTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExamProvider>();

    if (provider.loading && provider.adminExams.isEmpty) {
      return const LoadingView(message: 'Loading exams...');
    }

    if (provider.hasError && provider.adminExams.isEmpty) {
      return ErrorView(
        message: provider.error!,
        onRetry: () => context.read<ExamProvider>().loadAdminExams(),
      );
    }

    if (provider.adminExams.isEmpty) {
      return const EmptyView(
        icon: Icons.library_books_outlined,
        title: 'No exams yet',
        message: 'Use the Create tab to upload an Excel sheet and publish your first exam.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ExamProvider>().loadAdminExams(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.adminExams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final exam = provider.adminExams[index];
          return _AdminExamCard(
            exam: exam,
            onReport: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExamReportScreen(examId: exam.id, examTitle: exam.title),
              ),
            ),
            onDelete: () => _confirmDelete(exam),
          );
        },
      ),
    );
  }
}

class _AdminExamCard extends StatelessWidget {
  const _AdminExamCard({
    required this.exam,
    required this.onReport,
    required this.onDelete,
  });

  final Exam exam;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete exam',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 21),
                ),
              ],
            ),
            Text(
              exam.subject,
              style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(icon: Icons.list_alt_outlined, label: '${exam.questionCount} questions'),
                _Chip(icon: Icons.timer_outlined, label: '${exam.duration} min'),
                _Chip(icon: Icons.emoji_events_outlined, label: '${_fmt(exam.totalMarks)} marks'),
                _Chip(icon: Icons.flag_outlined, label: 'Pass ${_fmt(exam.passingMarks)}'),
                if (exam.hasNegativeMarking)
                  _Chip(
                    icon: Icons.remove_circle_outline,
                    label: '-${_fmt(exam.negativeMarking)} per wrong',
                    colour: AppTheme.danger,
                  ),
              ],
            ),
            if (exam.startDate != null || exam.endDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.event_outlined, size: 15, color: Color(0xFF98A2B3)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _window(exam),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF98A2B3)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.bar_chart_outlined, size: 18),
                label: const Text('View report'),
                style: FilledButton.styleFrom(minimumSize: const Size(150, 44)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _window(Exam exam) {
    final start = _shortDate(exam.startDate);
    final end = _shortDate(exam.endDate);
    if (start != null && end != null) return 'Open $start – $end';
    if (start != null) return 'Opens $start';
    if (end != null) return 'Closes $end';
    return 'Always available';
  }

  static String? _shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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

/// Trims trailing zeros: 40.0 reads as "40", 17.5 keeps its decimal.
String _fmt(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
