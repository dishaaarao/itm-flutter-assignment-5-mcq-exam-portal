import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/attempt.dart';
import '../../models/question.dart';
import '../../providers/attempt_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/option_tile.dart';
import '../../widgets/question_palette.dart';
import '../../widgets/timer_widget.dart';
import 'result_screen.dart';

/// The live exam: one question at a time, a clock, and a palette to jump around.
///
/// Everything meaningful here is owned by [AttemptProvider] — this screen only
/// renders it and forwards taps. That matters because the countdown can end
/// while the student is looking at a different widget, and the submission must
/// happen whether or not this screen is on top.
class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key, required this.examId});

  final String examId;

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late final AttemptProvider _attempts;

  /// Set the moment we hand off to the result screen, so the status listener
  /// does not fire a second navigation on the next notify.
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _attempts = context.read<AttemptProvider>();
    _attempts.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attempts.start(widget.examId);
    });
  }

  @override
  void dispose() {
    _attempts.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Reacts to status changes that this screen did not initiate — the timer
  /// running out, or a submission failing to reach the server.
  void _onSessionChanged() {
    if (!mounted || _handedOff) return;

    if (_attempts.status == SessionStatus.submitted && _attempts.submission != null) {
      _openResult(_attempts.submission!.attemptId, preloaded: _attempts.submission);
      return;
    }

    if (_attempts.status == SessionStatus.failed && _attempts.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_attempts.error!),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _attempts.submit(),
          ),
        ),
      );
    }
  }

  void _openResult(String attemptId, {AttemptSubmission? preloaded}) {
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(attemptId: attemptId, initial: preloaded),
      ),
    );
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _attempts.unansweredCount;
    final marked = _attempts.markedForReview.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit your paper?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryLine('Answered', '${_attempts.answeredCount} of ${_attempts.questionCount}'),
            _summaryLine('Not answered', '$unanswered'),
            _summaryLine('Marked for review', '$marked'),
            const SizedBox(height: 12),
            Text(
              unanswered > 0
                  ? 'Unanswered questions score nothing but are not penalised. '
                      'You cannot change your answers after submitting.'
                  : 'You cannot change your answers after submitting.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085), height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _attempts.submit();
  }

  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the exam?'),
        content: const Text(
          'Your answers are kept and the attempt stays open, but the clock keeps '
          'running. You can resume from the exam list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Drop the in-memory session; the server still holds the attempt, so
      // resuming picks up the same deadline and the saved answers.
      _attempts.reset();
      Navigator.of(context).pop();
    }
  }

  void _openPalette() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Question palette',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '${_attempts.answeredCount}/${_attempts.questionCount} answered',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Rebuilds with the provider so a tap here updates the grid
                  // immediately rather than after the sheet is reopened.
                  Consumer<AttemptProvider>(
                    builder: (context, provider, _) => QuestionPalette(
                      states: List.generate(
                        provider.questionCount,
                        provider.paletteStateFor,
                      ),
                      currentIndex: provider.currentIndex,
                      onSelect: (index) {
                        provider.goTo(index);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _confirmSubmit();
                      },
                      child: const Text('Submit paper'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttemptProvider>();
    final status = provider.status;

    if (status == SessionStatus.idle || status == SessionStatus.loading) {
      return const Scaffold(body: LoadingView(message: 'Preparing your paper...'));
    }

    if (status == SessionStatus.failed && provider.session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam')),
        body: ErrorView(
          message: provider.error ?? 'Could not start this exam.',
          onRetry: () => provider.start(widget.examId),
        ),
      );
    }

    final inProgress = status == SessionStatus.active || status == SessionStatus.submitting;
    final locked = provider.timeExpired || provider.isSubmitting;

    return PopScope(
      canPop: !inProgress,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            provider.questionCount == 0
                ? 'Exam'
                : 'Question ${provider.currentIndex + 1} of ${provider.questionCount}',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: TimerWidget(remaining: provider.remaining, compact: true),
              ),
            ),
            IconButton(
              tooltip: 'Question palette',
              onPressed: provider.questionCount == 0 ? null : _openPalette,
              icon: const Icon(Icons.grid_view_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: locked || provider.questionCount == 0 ? null : _confirmSubmit,
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
        body: _buildBody(provider, locked: locked),
      ),
    );
  }

  Widget _buildBody(AttemptProvider provider, {required bool locked}) {
    if (provider.questionCount == 0) {
      return const ErrorView(
        message: 'This exam has no questions. Ask your instructor to re-upload the sheet.',
        icon: Icons.inbox_outlined,
      );
    }

    final question = provider.currentQuestion;
    if (question == null) {
      return const ErrorView(message: 'That question is no longer available.');
    }

    final selected = provider.answerFor(question);
    final marked = provider.markedForReview.contains(question.id);
    final isLast = provider.currentIndex == provider.questionCount - 1;

    return Column(
      children: [
        _StatusStrip(provider: provider),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _QuestionCard(
                question: question,
                selected: selected,
                locked: locked,
                onSelect: (letter) => provider.selectAnswer(question, letter),
              ),
            ],
          ),
        ),
        _BottomBar(
          locked: locked,
          marked: marked,
          isFirst: provider.currentIndex == 0,
          isLast: isLast,
          onPrevious: provider.previous,
          onNext: provider.next,
          onToggleMark: () => provider.toggleMarkForReview(question),
          onSubmit: _confirmSubmit,
        ),
      ],
    );
  }
}

/// Thin bar under the app bar: progress against the clock, and a running count.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.provider});

  final AttemptProvider provider;

  @override
  Widget build(BuildContext context) {
    final total = provider.questionCount;
    final answered = provider.answeredCount;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : answered / total,
              minHeight: 5,
              backgroundColor: const Color(0xFFEAECF0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$answered answered',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
              ),
              const SizedBox(width: 14),
              Text(
                '${provider.unansweredCount} left',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
              ),
              const Spacer(),
              if (provider.markedForReview.isNotEmpty)
                Text(
                  '${provider.markedForReview.length} marked',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.marked,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selected,
    required this.locked,
    required this.onSelect,
  });

  final Question question;
  final String? selected;
  final bool locked;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final imageUrl = question.imageUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Q${question.questionNo}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              question.question,
              style: const TextStyle(fontSize: 16.5, height: 1.45, fontWeight: FontWeight.w500),
            ),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 18),
            ...List.generate(question.options.length, (index) {
              final letter = Question.letterFor(index);
              return OptionTile(
                letter: letter,
                text: question.options[index],
                selected: selected == letter,
                // Locking the taps rather than hiding the tiles keeps the paper
                // readable while the submission is in flight.
                onTap: locked ? null : () => onSelect(letter),
              );
            }),
            if (locked) ...[
              const SizedBox(height: 4),
              const Text(
                'Answers are locked while the paper is submitted.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF667085)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.locked,
    required this.marked,
    required this.isFirst,
    required this.isLast,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleMark,
    required this.onSubmit,
  });

  final bool locked;
  final bool marked;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleMark;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAECF0))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isFirst ? null : onPrevious,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  label: const Text('Previous'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: marked ? 'Remove review mark' : 'Mark for review',
                onPressed: locked ? null : onToggleMark,
                icon: Icon(
                  marked ? Icons.flag : Icons.outlined_flag,
                  color: marked ? AppTheme.marked : const Color(0xFF475467),
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 46),
                  side: BorderSide(
                    color: marked ? AppTheme.marked : const Color(0xFFD0D5DD),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isLast
                    ? FilledButton.icon(
                        onPressed: locked ? null : onSubmit,
                        icon: const Icon(Icons.check_circle_outline, size: 19),
                        label: const Text('Submit'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: locked ? null : onNext,
                        icon: const Icon(Icons.chevron_right, size: 20),
                        label: const Text('Next'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
