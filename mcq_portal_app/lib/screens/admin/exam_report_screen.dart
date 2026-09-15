import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/attempt.dart';
import '../../providers/exam_provider.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';

/// Per-exam performance: the aggregate first, then every student's row.
class ExamReportScreen extends StatefulWidget {
  const ExamReportScreen({super.key, required this.examId, required this.examTitle});

  final String examId;
  final String examTitle;

  @override
  State<ExamReportScreen> createState() => _ExamReportScreenState();
}

class _ExamReportScreenState extends State<ExamReportScreen> {
  ExamReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final report = await context.read<ExamProvider>().loadReport(widget.examId);
    if (!mounted) return;
    setState(() {
      _report = report;
      _error = report == null ? 'Could not load this report.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: report == null
          ? (_error == null
              ? const LoadingView(message: 'Building the report...')
              : ErrorView(message: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    report.examTitle.isEmpty ? widget.examTitle : report.examTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(summary: report.summary),
                  const SizedBox(height: 16),
                  _RowsSection(rows: report.rows),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final passRate = summary.passPercentage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Attempted',
                    value: '${summary.studentsAttempted}',
                    colour: const Color(0xFF475467),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Passed',
                    value: '${summary.passCount}',
                    colour: AppTheme.accent,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Failed',
                    value: '${summary.failCount}',
                    colour: AppTheme.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Average score',
                    value: _fmt(summary.averageScore),
                    colour: AppTheme.primary,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Average %',
                    value: '${_fmt(summary.averagePercentage)}%',
                    colour: AppTheme.primary,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Pass rate',
                    value: passRate == null ? '—' : '${_fmt(passRate)}%',
                    colour: AppTheme.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Highest',
                    value: _fmt(summary.highestScore),
                    colour: AppTheme.accent,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Lowest',
                    value: _fmt(summary.lowestScore),
                    colour: AppTheme.warning,
                  ),
                ),
                Expanded(child: _Topper(summary: summary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.colour});

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: colour),
        ),
      ],
    );
  }
}

class _Topper extends StatelessWidget {
  const _Topper({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final name = summary.topperName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Topper', style: TextStyle(fontSize: 12.5, color: Color(0xFF667085))),
        const SizedBox(height: 4),
        Text(
          name == null || name.isEmpty ? '—' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (summary.topperScore != null)
          Text(
            '${_fmt(summary.topperScore)} marks',
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
      ],
    );
  }
}

class _RowsSection extends StatelessWidget {
  const _RowsSection({required this.rows});

  final List<AttemptRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: EmptyView(
            icon: Icons.how_to_reg_outlined,
            title: 'No attempts yet',
            message: 'Student results appear here as soon as they submit this exam.',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Students (${rows.length})',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...rows.map((row) => _StudentRow(row: row)),
          ],
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.row});

  final AttemptRow row;

  @override
  Widget build(BuildContext context) {
    final submitted = row.isSubmitted;
    final pass = row.isPass;

    // An attempt still in progress has no score, and showing a failing 0 for it
    // would misreport a student who simply has not finished.
    final colour = !submitted
        ? AppTheme.warning
        : pass
            ? AppTheme.accent
            : AppTheme.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  _initials(row.studentName),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.studentName.isEmpty ? 'Student' : row.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (row.autoSubmitted) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.schedule, size: 13, color: AppTheme.warning),
                        ],
                      ],
                    ),
                    Text(
                      row.studentEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    submitted ? '${_fmt(row.score ?? 0)} / ${_fmt(row.totalMarks ?? 0)}' : 'In progress',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                  Text(
                    submitted
                        ? '${_fmt(row.percentage ?? 0)}%  ·  ${row.grade ?? '-'}'
                        : 'Not submitted',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (submitted) ...[
                  _TinyStat(label: 'Correct', value: row.correct, colour: AppTheme.accent),
                  _TinyStat(label: 'Wrong', value: row.wrong, colour: AppTheme.danger),
                  _TinyStat(label: 'Skipped', value: row.unattempted, colour: const Color(0xFF667085)),
                ],
                if (row.timeTakenSeconds != null)
                  Text(
                    'Took ${_duration(row.timeTakenSeconds!)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return minutes > 0 ? '${minutes}m ${secs}s' : '${secs}s';
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.label, required this.value, required this.colour});

  final String label;
  final int? value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${value ?? 0} $label',
      style: TextStyle(fontSize: 12, color: colour, fontWeight: FontWeight.w600),
    );
  }
}

/// Trims trailing zeros, and renders a missing number as an em dash rather than
/// a misleading zero.
String _fmt(num? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
