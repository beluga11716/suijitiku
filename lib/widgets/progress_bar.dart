import 'package:flutter/material.dart';

/// 答题进度条
class QuizProgressBar extends StatelessWidget {
  final int current;
  final int total;
  final int correctCount;

  const QuizProgressBar({
    super.key,
    required this.current,
    required this.total,
    this.correctCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = current / total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('$current / $total',
              style: theme.textTheme.labelMedium),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          if (correctCount > 0) ...[
            const SizedBox(width: 12),
            Icon(Icons.check_circle,
                size: 16, color: Colors.green.shade600),
            const SizedBox(width: 2),
            Text('$correctCount',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.green.shade600)),
          ],
        ],
      ),
    );
  }
}
