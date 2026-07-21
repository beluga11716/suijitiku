import 'package:flutter/material.dart';
import '../parser/question_extractor.dart';

class ImportResult {
  final String bankName;
  final List<ParsedQuestion> questions;

  ImportResult({required this.bankName, required this.questions});
}

/// 导入预览对话框
class ImportDialog extends StatefulWidget {
  final String fileName;
  final List<ParsedQuestion> questions;
  final String rawText;

  const ImportDialog({
    super.key,
    required this.fileName,
    required this.questions,
    required this.rawText,
  });

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.fileName.replaceAll(RegExp(r'\..+$'), ''));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 按题型统计
    final typeCount = <String, int>{};
    for (final q in widget.questions) {
      typeCount[q.type.label] = (typeCount[q.type.label] ?? 0) + 1;
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('导入预览',
                  style: theme.textTheme.titleLarge),
            ),

            // 题库名称
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '题库名称',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 解析统计
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatChip(
                      label: '总计',
                      value: '${widget.questions.length} 题'),
                  const SizedBox(width: 8),
                  ...typeCount.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _StatChip(
                            label: e.key, value: '${e.value} 题'),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 题目预览
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.questions.length.clamp(0, 20),
                itemBuilder: (_, i) {
                  final q = widget.questions[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                        radius: 14,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 12))),
                    title: Text(q.stem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${q.type.label} · 答案：${q.answer}',
                        style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),

            if (widget.questions.length > 20)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    '...还有 ${widget.questions.length - 20} 道题未显示',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),

            // 操作按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(
                          context,
                          ImportResult(
                              bankName: _nameController.text.trim(),
                              questions: widget.questions));
                    },
                    child: Text(
                        '导入 ${widget.questions.length} 道题'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $value',
          style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSecondaryContainer)),
    );
  }
}
