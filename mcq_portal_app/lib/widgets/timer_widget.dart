import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Countdown for the running exam.
///
/// Colour carries the warning: normal, then amber inside five minutes, then red
/// inside the last minute. A student should not have to read a number to know
/// they are running out of time.
class TimerWidget extends StatelessWidget {
  const TimerWidget({
    super.key,
    required this.remaining,
    this.compact = false,
    this.totalSeconds,
  });

  final Duration remaining;
  final bool compact;

  /// When supplied, a thin progress bar shows elapsed time against the whole
  /// duration.
  final int? totalSeconds;

  Color get _colour {
    if (remaining.inSeconds <= 60) return AppTheme.danger;
    if (remaining.inSeconds <= 300) return AppTheme.warning;
    return AppTheme.primary;
  }

  String get _label {
    final seconds = remaining.inSeconds.clamp(0, 86400);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: _colour),
            const SizedBox(width: 6),
            Text(
              _label,
              style: TextStyle(
                color: _colour,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: _colour),
            const SizedBox(width: 8),
            Text(
              'Time remaining',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const Spacer(),
            Text(
              _label,
              style: TextStyle(
                color: _colour,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (totalSeconds != null && totalSeconds! > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (1 - remaining.inSeconds / totalSeconds!).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFEAECF0),
              valueColor: AlwaysStoppedAnimation<Color>(_colour),
            ),
          ),
        ],
      ],
    );
  }
}
