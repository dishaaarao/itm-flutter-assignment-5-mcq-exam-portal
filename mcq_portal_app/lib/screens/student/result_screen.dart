import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/attempt.dart';
import '../../services/app_services.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';

/// The graded outcome of one attempt.
///
/// Takes an [initial] submission when the caller already has one — the exam
/// screen has just been handed the server's grading, so re-fetching it there
/// would only add a spinner. Opened from the history list instead, there is
/// nothing in hand and the result is fetched.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.attemptId, this.initial});

  final String attemptId;
  final AttemptSubmission? initial;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  AttemptSubmission? _submission;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _submission = widget.initial;
    if (_submission == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final submission =
          await context.read<AppServices>().attempts.getResult(widget.attemptId);
      if (!mounted) return;
      setState(() {
        _submission = submission;
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
    final submission = _submission;

    if (submission == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: _loading
            ? const LoadingView(message: 'Loading your result...')
            : ErrorView(
                message: _error ?? 'This result is not available.',
                onRetry: _load,
              ),
      );
    }

    final result = submission.result;

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (submission.autoSubmitted) const _AutoSubmittedNotice(),
          _ScoreCard(submission: submission),
          const SizedBox(height: 16),
          _StatsGrid(result: result),
          const SizedBox(height: 16),
          _BreakdownCard(rows: result.breakdown),
        ],
      ),
    );
  }
}

/// The score ring, the verdict, and the exam it belongs to.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.submission});

  final AttemptSubmission submission;

  @override
  Widget build(BuildContext context) {
    final result = submission.result;
    final verdictColour = result.isPass ? AppTheme.accent : AppTheme.danger;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              submission.examTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
            ),
            if (submission.subject != null && submission.subject!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                submission.subject!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
              ),
            ],
            const SizedBox(height: 22),
            _ScoreRing(result: result, colour: verdictColour),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: verdictColour.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                result.isPass ? 'PASSED' : 'NOT PASSED',
                style: TextStyle(
                  color: verdictColour,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Time taken ${_formatDuration(submission.timeTakenSeconds)} '
              'of ${_formatDuration(submission.durationSeconds)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final safe = seconds.clamp(0, 86400 * 7);
    final minutes = safe ~/ 60;
    final secs = safe % 60;
    return minutes > 0 ? '${minutes}m ${secs}s' : '${secs}s';
  }
}

/// Circular score indicator.
///
/// Drawn from the clamped [AttemptResult.progress] so an attempt that scored
/// below zero — which negative marking allows — still renders.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.result, required this.colour});

  final AttemptResult result;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 168,
            height: 168,
            child: CircularProgressIndicator(
              value: result.progress,
              strokeWidth: 12,
              backgroundColor: const Color(0xFFEAECF0),
              valueColor: AlwaysStoppedAnimation<Color>(colour),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(result.score),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: colour,
                  height: 1.1,
                ),
              ),
              Text(
                'out of ${_fmt(result.totalMarks)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
              ),
              const SizedBox(height: 6),
              Text(
                '${_fmt(result.percentage)}%',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.result});

  final AttemptResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Breakdown', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(
                  label: 'Correct',
                  value: '${result.correct}',
                  colour: AppTheme.accent,
                  icon: Icons.check_circle_outline,
                ),
                _Stat(
                  label: 'Wrong',
                  value: '${result.wrong}',
                  colour: AppTheme.danger,
                  icon: Icons.cancel_outlined,
                ),
                _Stat(
                  label: 'Skipped',
                  value: '${result.unattempted}',
                  colour: const Color(0xFF667085),
                  icon: Icons.remove_circle_outline,
                ),
                _Stat(
                  label: 'Grade',
                  value: result.grade,
                  colour: AppTheme.gradeColor(result.grade),
                  icon: Icons.workspace_premium_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${result.attempted} of ${result.totalQuestions} questions attempted.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.colour,
    required this.icon,
  });

  final String label;
  final String value;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: colour),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colour),
              ),
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-question review, with the correct option and the student's choice marked.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.rows});

  final List<BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'No per-question breakdown is available for this attempt.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
        ),
      );
    }

    return Card(
      child: Theme(
        // ExpansionTile would otherwise inherit the app's divider styling and
        // draw a line under every collapsed row.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
                child: Text(
                  'Question review',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
              ...rows.map((row) => _BreakdownTile(row: row)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({required this.row});

  final BreakdownRow row;

  @override
  Widget build(BuildContext context) {
    final colour = row.isCorrect
        ? AppTheme.accent
        : row.wasAttempted
            ? AppTheme.danger
            : const Color(0xFF667085);

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '${row.questionNo}',
          style: TextStyle(color: colour, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      title: Text(
        row.question,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, height: 1.35),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          row.isCorrect
              ? 'Correct  +${_fmt(row.marksAwarded)}'
              : row.wasAttempted
                  ? 'Wrong  ${_fmt(row.marksAwarded)}'
                  : 'Not attempted  0',
          style: TextStyle(fontSize: 12.5, color: colour, fontWeight: FontWeight.w600),
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      children: [
        // The stored breakdown keeps answer letters, not the option text the
        // student read, so the review states the letters outright rather than
        // rendering option tiles with nothing in them.
        _AnswerLine(
          label: 'Your answer',
          value: row.yourAnswer,
          colour: row.isCorrect ? AppTheme.accent : AppTheme.danger,
        ),
        const SizedBox(height: 8),
        _AnswerLine(label: 'Correct answer', value: row.correctAnswer, colour: AppTheme.accent),
      ],
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({required this.label, required this.value, required this.colour});

  final String label;
  final String? value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final answered = value != null && value!.isNotEmpty;

    return Row(
      children: [
        SizedBox(
          width: 122,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
          ),
        ),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: answered ? colour.withValues(alpha: 0.12) : const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            answered ? value! : '—',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: answered ? colour : const Color(0xFF98A2B3),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the clock ran out rather than the student tapping Submit. Without
/// it, a flagged late submission looks identical to a normal one.
class _AutoSubmittedNotice extends StatelessWidget {
  const _AutoSubmittedNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFEDF89)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.schedule, size: 18, color: AppTheme.warning),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Time ran out, so this paper was submitted automatically. '
                'Any answers you had given were marked.',
                style: TextStyle(fontSize: 13, color: Color(0xFF93370D), height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trims trailing zeros: 40.0 reads as "40", 17.5 keeps its decimal.
String _fmt(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
