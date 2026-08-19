import 'package:flutter/material.dart';
import '../models/question.dart';
import 'option_tile.dart';

/// 通用题目卡片：根据题型自适应渲染
///
/// 逐题模式：用户自由选择 → [onSelectionChanged] 通知父组件 → 父组件点击「确认答案」→ 调用 submitAnswer
/// 试卷模式：用户选择 → [onSelectionChanged] 通知父组件 → 父组件 recordExamAnswer
class QuizCard extends StatefulWidget {
  final Question question;
  final bool showAnswer;
  final String? initialAnswer;
  final String? userAnswer; // 外部控制的答案（试卷模式）
  final void Function(String answer)? onSelectionChanged;
  final void Function(String answer)? onAiGrade; // 主观题 AI 评分回调
  final Widget? typeRowTrailing; // 题型行最右侧的附加操作（逐题模式「确认答案」按钮）

  const QuizCard({
    super.key,
    required this.question,
    this.showAnswer = false,
    this.initialAnswer,
    this.userAnswer,
    this.onSelectionChanged,
    this.onAiGrade,
    this.typeRowTrailing,
  });

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  String? _selectedSingle;
  Set<String> _selectedMulti = {};
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialAnswer != null) {
      if (widget.question.type == QuestionType.multiChoice) {
        _selectedMulti =
            widget.initialAnswer!.split('').toSet();
      } else if (widget.question.type == QuestionType.singleChoice ||
          widget.question.type == QuestionType.trueFalse) {
        _selectedSingle = widget.initialAnswer;
      } else {
        _textController.text = widget.initialAnswer!;
      }
    }
  }

  @override
  void didUpdateWidget(QuizCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 题目切换时，重置选中状态（Element 复用不会走 initState）
    if (widget.question.id != oldWidget.question.id) {
      _resetForNewQuestion();
      return;
    }

    // 同一题目：外部控制答案（试卷模式）
    if (widget.userAnswer != null &&
        widget.userAnswer != oldWidget.userAnswer) {
      if (widget.question.type == QuestionType.multiChoice) {
        _selectedMulti =
            widget.userAnswer!.split('').toSet();
      } else if (widget.question.type ==
              QuestionType.singleChoice ||
          widget.question.type == QuestionType.trueFalse) {
        _selectedSingle = widget.userAnswer;
      } else {
        _textController.text = widget.userAnswer!;
      }
    }
  }

  void _resetForNewQuestion() {
    if (widget.initialAnswer != null) {
      if (widget.question.type == QuestionType.multiChoice) {
        _selectedMulti =
            widget.initialAnswer!.split('').toSet();
      } else if (widget.question.type == QuestionType.singleChoice ||
          widget.question.type == QuestionType.trueFalse) {
        _selectedSingle = widget.initialAnswer;
      } else {
        _textController.text = widget.initialAnswer!;
      }
    } else {
      _selectedSingle = null;
      _selectedMulti = {};
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isReadonly =>
      widget.showAnswer || widget.userAnswer != null;

  void _handleSingleChoice(String value) {
    if (_isReadonly) return;
    setState(() => _selectedSingle = value);
    widget.onSelectionChanged?.call(value);
  }

  void _handleMultiChoice(String value) {
    if (_isReadonly) return;
    setState(() {
      if (_selectedMulti.contains(value)) {
        _selectedMulti.remove(value);
      } else {
        _selectedMulti.add(value);
      }
    });
    final answer = _selectedMulti.toList()..sort();
    widget.onSelectionChanged?.call(answer.join());
  }

  void _handleTextAnswer() {
    if (_isReadonly) return;
    widget.onSelectionChanged?.call(_textController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题型标签 + 行最右侧操作（逐题模式「确认答案」按钮）
        Row(
          children: [
            Chip(
              label: Text(q.type.label,
                  style: const TextStyle(fontSize: 12)),
              materialTapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            if (q.chapter != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Chip(
                  label: Text(q.chapter!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor:
                      theme.colorScheme.secondaryContainer,
                ),
              ),
            ],
            const Spacer(),
            if (widget.typeRowTrailing != null) widget.typeRowTrailing!,
          ],
        ),
        const SizedBox(height: 12),

        // 题干
        Text(q.stem,
            style: theme.textTheme.bodyLarge
                ?.copyWith(height: 1.6)),
        const SizedBox(height: 16),

        // 选项 / 输入框
        if (q.type == QuestionType.singleChoice ||
            q.type == QuestionType.trueFalse)
          ...q.options.asMap().entries.map((entry) {
            final label =
                String.fromCharCode(65 + entry.key); // A, B, C, D
            final isSelected = _selectedSingle == label;
            final isCorrectAnswer = q.answer.toUpperCase() == label;

            // 答案揭示后: 正确→绿色, 用户错选→红色, 其余不变
            final bool? showCorrect = widget.showAnswer
                ? (isCorrectAnswer
                    ? true
                    : (isSelected ? false : null))
                : null;

            return OptionTile(
              label: label,
              text: entry.value,
              isSelected: widget.showAnswer ? false : isSelected,
              isCorrect: showCorrect,
              onTap: () => _handleSingleChoice(label),
            );
          })
        else if (q.type == QuestionType.multiChoice)
          ...q.options.asMap().entries.map((entry) {
            final label =
                String.fromCharCode(65 + entry.key);
            final isSelected = _selectedMulti.contains(label);
            final correctSet =
                q.answer.toUpperCase().split('').toSet();
            final isCorrectAnswer = correctSet.contains(label);

            // 答案揭示后: 正确→绿色, 用户错选→红色, 其余不变
            final bool? showCorrect = widget.showAnswer
                ? (isCorrectAnswer
                    ? true
                    : (isSelected ? false : null))
                : null;

            return OptionTile(
              label: label,
              text: entry.value,
              isSelected: widget.showAnswer ? false : isSelected,
              isCorrect: showCorrect,
              multiSelect: true,
              onTap: () => _handleMultiChoice(label),
            );
          })
        else
          // 填空 / 主观题
          TextField(
            controller: _textController,
            maxLines: q.type == QuestionType.shortAnswer ? 6 : 2,
            decoration: InputDecoration(
              hintText: q.type == QuestionType.fillBlank
                  ? '请输入答案'
                  : '请输入你的回答...',
              border: const OutlineInputBorder(),
              filled: widget.showAnswer && q.type.isObjective,
              fillColor: widget.showAnswer && q.type.isObjective
                  ? (q.answer == _textController.text
                      ? Colors.green.shade50
                      : Colors.red.shade50)
                  : null,
            ),
            readOnly: _isReadonly,
            onChanged: (_) => _handleTextAnswer(),
          ),

        // 解析（显示答案后）
        if (widget.showAnswer) ...[
          const SizedBox(height: 12),
          _AnswerBanner(
            isCorrect: _checkCorrect(q),
            correctAnswer: q.answer,
            userAnswer: q.type.isObjective
                ? null
                : _textController.text.trim(),
            explanation: q.explanation,
            isSubjective: !q.type.isObjective,
            onAiGrade: (widget.showAnswer && widget.onAiGrade != null)
                ? () => widget.onAiGrade!(_textController.text.trim())
                : null,
          ),
        ],
      ],
    );
  }

  bool _checkCorrect(Question q) {
    if (q.type == QuestionType.multiChoice) {
      final sortedCorrect = q.answer
          .toUpperCase()
          .split('')
          .where((c) => c.trim().isNotEmpty)
          .toList()
        ..sort();
      final sortedUser = _selectedMulti.toList()..sort();
      return sortedCorrect.join() == sortedUser.join();
    } else if (q.type == QuestionType.singleChoice ||
        q.type == QuestionType.trueFalse) {
      return _selectedSingle?.toUpperCase() ==
          q.answer.toUpperCase().trim();
    } else {
      return _textController.text.trim() == q.answer.trim();
    }
  }
}

class _AnswerBanner extends StatelessWidget {
  final bool isCorrect;
  final String correctAnswer;
  final String? userAnswer;
  final String? explanation;
  final bool isSubjective;
  final VoidCallback? onAiGrade;

  const _AnswerBanner({
    required this.isCorrect,
    required this.correctAnswer,
    this.userAnswer,
    this.explanation,
    this.isSubjective = false,
    this.onAiGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSubjective
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : (isCorrect ? Colors.green.shade50 : Colors.red.shade50),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主观题：显示用户答案 vs 参考答案
          if (isSubjective && userAnswer != null) ...[
            Text('你的回答：',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(userAnswer!,
                  style: TextStyle(color: theme.colorScheme.onSurface)),
            ),
            const SizedBox(height: 12),
            Text('参考答案：',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(correctAnswer,
                  style: TextStyle(color: Colors.green.shade900)),
            ),
            // AI 评分按钮
            if (onAiGrade != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onAiGrade,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 评分'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ] else ...[
            // 客观题：显示对错
            Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  isCorrect ? '回答正确！' : '回答错误',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCorrect
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
              ],
            ),
            if (!isCorrect) ...[
              const SizedBox(height: 4),
              Text('正确答案：$correctAnswer',
                  style: TextStyle(color: Colors.green.shade800)),
            ],
          ],
          if (explanation != null && explanation!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('解析：$explanation',
                style: TextStyle(
                    color: Colors.grey.shade700, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
