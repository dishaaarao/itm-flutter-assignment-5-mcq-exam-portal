import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/question.dart';

/// One option of one question, rendered as a tappable row.
///
/// Used in two modes: selectable while an exam is running, and read-only on the
/// result screen where the correct answer and the student's answer are marked
/// up instead.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.letter,
    required this.text,
    this.selected = false,
    this.onTap,
    this.isCorrectAnswer = false,
    this.isChosenAnswer = false,
    this.reviewMode = false,
  });

  final String letter;
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final bool isCorrectAnswer;
  final bool isChosenAnswer;
  final bool reviewMode;

  @override
  Widget build(BuildContext context) {
    Color borderColor = const Color(0xFFD0D5DD);
    Color background = Colors.white;
    Color badgeColor = const Color(0xFFF2F4F7);
    Color badgeTextColor = const Color(0xFF475467);
    IconData? trailingIcon;
    Color? trailingColor;

    if (reviewMode) {
      if (isCorrectAnswer) {
        borderColor = AppTheme.accent;
        background = const Color(0xFFECFDF3);
        badgeColor = AppTheme.accent;
        badgeTextColor = Colors.white;
        trailingIcon = Icons.check_circle;
        trailingColor = AppTheme.accent;
      } else if (isChosenAnswer) {
        borderColor = AppTheme.danger;
        background = const Color(0xFFFEF3F2);
        badgeColor = AppTheme.danger;
        badgeTextColor = Colors.white;
        trailingIcon = Icons.cancel;
        trailingColor = AppTheme.danger;
      }
    } else if (selected) {
      borderColor = AppTheme.primary;
      background = const Color(0xFFEEF3FF);
      badgeColor = AppTheme.primary;
      badgeTextColor = Colors.white;
      trailingIcon = Icons.check_circle;
      trailingColor = AppTheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: selected || isCorrectAnswer || isChosenAnswer ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: badgeTextColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      text.isEmpty ? '—' : text,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                    ),
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(trailingIcon, size: 20, color: trailingColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience: renders a question's full option list in review mode, working
/// out which option was correct and which the student chose.
class ReviewOptions extends StatelessWidget {
  const ReviewOptions({
    super.key,
    required this.question,
    required this.correctAnswer,
    required this.yourAnswer,
  });

  final Question question;
  final String? correctAnswer;
  final String? yourAnswer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(question.options.length, (index) {
        final letter = Question.letterFor(index);
        return OptionTile(
          letter: letter,
          text: question.options[index],
          reviewMode: true,
          isCorrectAnswer: letter == correctAnswer,
          isChosenAnswer: letter == yourAnswer && letter != correctAnswer,
        );
      }),
    );
  }
}
