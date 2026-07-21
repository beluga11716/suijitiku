import 'package:flutter/material.dart';

/// 选项行组件
class OptionTile extends StatelessWidget {
  final String label; // A, B, C, D...
  final String text;
  final bool isSelected;
  final bool? isCorrect; // null = 未揭示答案
  final Color? backgroundColor;
  final bool multiSelect;
  final VoidCallback? onTap;

  const OptionTile({
    super.key,
    required this.label,
    required this.text,
    this.isSelected = false,
    this.isCorrect,
    this.backgroundColor,
    this.multiSelect = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // 选择指示器
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: multiSelect
                        ? BoxShape.rectangle
                        : BoxShape.circle,
                    borderRadius: multiSelect
                        ? BorderRadius.circular(6)
                        : null,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isSelected
                        ? Icon(
                            multiSelect
                                ? Icons.check
                                : Icons.circle,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          )
                        : Text(label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.outline,
                            )),
                  ),
                ),
                const SizedBox(width: 12),

                // 选项文本
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        height: 1.4),
                  ),
                ),

                // 正确/错误标记
                if (isCorrect != null)
                  Icon(
                    isCorrect!
                        ? Icons.check_circle
                        : (isSelected
                            ? Icons.cancel
                            : null),
                    color: isCorrect! ? Colors.green : Colors.red,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
