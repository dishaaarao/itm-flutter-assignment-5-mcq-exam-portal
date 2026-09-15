import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/attempt.dart';
import '../../services/app_services.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';
import 'result_screen.dart';

/// The student's attempt history, newest first.
///
/// Kept stateless in the provider sense: history is only ever read, so it does
/// not belong in a ChangeNotifier shared with the live exam.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => HistoryViewState();
}

/// Public so the dashboard can re-read the list when the Results tab is
/// reopened: an attempt submitted since the last read would otherwise stay
/// missing until the student thought to pull down.
class HistoryViewState extends State<HistoryView> {
  List<AttemptRow> _rows = const <AttemptRow>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await context.read<AppServices>().attempts.history();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const LoadingView(message: 'Loading your results...');
    }

    if (_error != null && _rows.isEmpty) {
      return ErrorView(message: _error!, onRetry: reload);
    }

    // An attempt still in progress has no score to show, so it is left out of
    // the history rather than listed as a row of dashes.
    final graded = _rows.where((row) => row.isSubmitted).toList();

    if (graded.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            EmptyView(
              icon: Icons.bar_chart_outlined,
              title: 'No results yet',
              message: 'Once you submit an exam, its score and breakdown appear here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: graded.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _HistoryCard(
          row: graded[index],
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ResultScreen(attemptId: graded[index].attemptId),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.row, required this.onOpen});

  final AttemptRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pass = row.isPass;
    final colour = pass ? AppTheme.accent : AppTheme.danger;

    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _fmt(row.score ?? 0),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colour,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '/${_fmt(row.totalMarks ?? 0)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.examTitle?.isNotEmpty == true ? row.examTitle! : 'Exam attempt',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row.correct ?? 0} correct · ${row.wrong ?? 0} wrong · '
                      '${row.unattempted ?? 0} skipped',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          label: pass ? 'PASS' : 'FAIL',
                          colour: colour,
                        ),
                        if (row.grade != null) _Pill(label: 'Grade ${row.grade}', colour: AppTheme.primary),
                        _Pill(
                          label: '${_fmt(row.percentage ?? 0)}%',
                          colour: const Color(0xFF475467),
                        ),
                        if (row.autoSubmitted)
                          const _Pill(label: 'Auto-submitted', colour: AppTheme.warning),
                      ],
                    ),
                    if (row.submittedAt != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Submitted ${_humanDate(row.submittedAt!)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF98A2B3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: colour),
      ),
    );
  }
}

/// Trims trailing zeros: 40.0 reads as "40", 17.5 keeps its decimal.
String _fmt(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// ISO timestamp to a short readable form, falling back to the raw string if it
/// cannot be parsed — a wrong date is worse than an ugly one.
String _humanDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour:$minute';
}
