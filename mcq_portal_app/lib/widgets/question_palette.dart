import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/attempt_provider.dart';

/// Question grid for jumping around the paper.
///
/// The three signals are kept separate on purpose: the fill says where the
/// question stands (answered, marked, or neither), the border says which one
/// you are looking at, and the glyph separates a tick from a flag. Nothing
/// depends on colour alone, so the palette stays readable with a colour-vision
/// deficiency.
class QuestionPalette extends StatelessWidget {
  const QuestionPalette({
    super.key,
    required this.states,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<PaletteState> states;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: states.length,
          itemBuilder: (context, index) {
            return _PaletteCell(
              number: index + 1,
              state: states[index],
              isCurrent: index == currentIndex,
              onTap: () => onSelect(index),
            );
          },
        ),
        const SizedBox(height: 20),
        const _Legend(),
      ],
    );
  }
}

class _PaletteCell extends StatelessWidget {
  const _PaletteCell({
    required this.number,
    required this.state,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final PaletteState state;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color foreground;
    IconData? marker;

    switch (state) {
      case PaletteState.answered:
        background = AppTheme.answered;
        foreground = Colors.white;
        marker = Icons.check;
      case PaletteState.markedForReview:
        background = AppTheme.marked;
        foreground = Colors.white;
        marker = Icons.flag;
      case PaletteState.answeredAndMarked:
        background = AppTheme.marked;
        foreground = Colors.white;
        marker = Icons.check;
      case PaletteState.unanswered:
        background = Colors.white;
        foreground = const Color(0xFF475467);
        marker = null;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent ? AppTheme.primary : const Color(0xFFD0D5DD),
              width: isCurrent ? 2.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$number',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (marker != null)
                Icon(marker, size: 12, color: foreground.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: const [
        _LegendEntry(colour: AppTheme.answered, label: 'Answered', icon: Icons.check),
        _LegendEntry(colour: AppTheme.marked, label: 'Marked', icon: Icons.flag),
        _LegendEntry(colour: Colors.white, label: 'Not answered', icon: null),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.colour, required this.label, required this.icon});

  final Color colour;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: icon == null ? null : Icon(icon, size: 11, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF475467))),
      ],
    );
  }
}
