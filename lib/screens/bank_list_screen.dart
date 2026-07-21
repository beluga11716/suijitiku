import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/bank_provider.dart';
import '../parser/docx_parser.dart';
import '../parser/pdf_parser.dart';
import '../parser/question_extractor.dart';
import '../ai/rule_engine.dart';
import '../widgets/import_dialog.dart';

class BankListScreen extends StatefulWidget {
  const BankListScreen({super.key});

  @override
  State<BankListScreen> createState() => _BankListScreenState();
}

class _BankListScreenState extends State<BankListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankProvider>().loadBanks();
    });
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx', 'pdf', 'doc', 'txt'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    if (!mounted) return;

    _showImportPreview(file.name, file.path!);
  }

  Future<void> _showImportPreview(
      String fileName, String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final ext = fileName.split('.').last.toLowerCase();

      String text;
      if (ext == 'docx') {
        text = DocxParser.parseBytes(bytes);
      } else if (ext == 'pdf') {
        text = PdfParser.parseBytes(bytes);
      } else if (ext == 'txt') {
        text = String.fromCharCodes(bytes);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持的文件格式')));
        return;
      }

      final questions = QuestionExtractor.extract(text);

      if (!mounted) return;

      final result = await showDialog<ImportResult>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => ImportDialog(
              fileName: fileName, questions: questions, rawText: text));

      if (result == null || !mounted) return;

      final bankName = result.bankName.isEmpty ? fileName : result.bankName;

      // 将 ParsedQuestion 转为 Question（临时 ID，导入时 BankProvider 会重新分配）
      final now = DateTime.now().millisecondsSinceEpoch;
      final tempQuestions = result.questions
          .asMap()
          .entries
          .map((e) => e.value.toQuestion(
                id: '${now}_${e.key}',
                bankId: 'temp',
              ))
          .toList();

      // 运行规则引擎评分
      final scoredQuestions = RuleEngine.score(tempQuestions);

      await context.read<BankProvider>().importBank(
            name: bankName,
            sourceFile: fileName,
            sourceType: ext,
            questions: scoredQuestions,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导入成功：${result.questions.length} 道题')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteBank(String id, String name) async {
    final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定要删除题库"$name"吗？\n题库中的题目也会被删除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('删除')),
              ],
            ));

    if (confirmed == true && mounted) {
      await context.read<BankProvider>().deleteBank(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankProvider>();
    final banks = provider.banks;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('题库管理'),
      ),
      body: banks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_books_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('还没有题库',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  const Text('点击右下角按钮导入 Word 或 PDF 文档'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _importFile,
                    icon: const Icon(Icons.add),
                    label: const Text('导入题库'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => provider.loadBanks(),
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: banks.length,
                itemBuilder: (_, i) {
                  final bank = banks[i];
                  return Card(
                    child: ListTile(
                      title: Text(bank.name),
                      subtitle: Text(
                          '${bank.questionCount} 道题 · ${bank.sourceFile ?? ""}'),
                      trailing: PopupMenuButton(
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'delete', child: Text('删除')),
                        ],
                        onSelected: (v) {
                          if (v == 'delete') {
                            _deleteBank(bank.id, bank.name);
                          }
                        },
                      ),
                      onTap: () =>
                          context.go('/banks/${bank.id}/tests'),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: banks.isNotEmpty
          ? FloatingActionButton(
              onPressed: _importFile,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
