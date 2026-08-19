import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/bank_provider.dart';
import '../providers/current_bank_provider.dart';
import '../providers/settings_provider.dart';
import '../database/dao.dart';
import '../parser/docx_parser.dart';
import '../parser/pdf_parser.dart';
import '../parser/question_extractor.dart';
import '../ai/llm_client.dart';
import '../widgets/import_dialog.dart';
import '../widgets/llm_analysis_progress_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dao = Dao();
  int _totalQuestions = 0;
  int _totalBanks = 0;
  int _totalQuizzes = 0;
  double _accuracy = 0.0;
  int _wrongCount = 0;
  // 错题提醒当前统计的题库（切换题库后重载错题数）
  String? _wrongCountBankId;
  // dispose 中不能再通过 context 查 ancestor，须在 didChangeDependencies 缓存引用
  CurrentBankProvider? _currentBankProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<CurrentBankProvider>();
    if (!identical(provider, _currentBankProvider)) {
      _currentBankProvider?.removeListener(_onCurrentBankChanged);
      _currentBankProvider = provider;
      provider.addListener(_onCurrentBankChanged);
    }
  }

  @override
  void dispose() {
    _currentBankProvider?.removeListener(_onCurrentBankChanged);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final bankProv = context.read<BankProvider>();
    final currentProv = context.read<CurrentBankProvider>();
    final totalQuestions = await _dao.getTotalQuestionCount();
    final totalBanks = await _dao.getTotalBankCount();
    final totalQuizzes = await _dao.getTotalQuizCount();
    final accuracy = await _dao.getOverallAccuracy();
    await bankProv.loadBanks();
    await currentProv.init();
    await _refreshWrongCount();

    if (mounted) {
      setState(() {
        _totalQuestions = totalQuestions;
        _totalBanks = totalBanks;
        _totalQuizzes = totalQuizzes;
        _accuracy = accuracy;
      });
    }
  }

  /// 重载当前题库的错题数（切换题库期间完成的旧结果会被丢弃）
  Future<void> _refreshWrongCount() async {
    final bankId = context.read<CurrentBankProvider>().currentBankId;
    final count = await _loadWrongCount(bankId);
    if (!mounted ||
        bankId != context.read<CurrentBankProvider>().currentBankId) {
      return;
    }
    setState(() {
      _wrongCountBankId = bankId;
      _wrongCount = count;
    });
  }

  /// 当前题库的错题数（未选中题库 → 0）
  Future<int> _loadWrongCount(String? bankId) async {
    if (bankId == null) return 0;
    final wrong = await _dao.getWrongQuestionsByBank(bankId);
    return wrong.length;
  }

  /// 切换题库后，错题提醒同步改为统计新题库的错题
  void _onCurrentBankChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<CurrentBankProvider>().currentBankId ==
          _wrongCountBankId) {
        return;
      }
      _refreshWrongCount();
    });
  }

  // ==================== 导入逻辑 ====================

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

  Future<void> _showImportPreview(String fileName, String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final ext = fileName.split('.').last.toLowerCase();

      String text;
      if (ext == 'docx') {
        text = DocxParser.parseBytes(bytes);
      } else if (ext == 'pdf') {
        text = PdfParser.parseBytes(bytes);
      } else if (ext == 'txt') {
        text = utf8.decode(bytes);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('不支持的文件格式')));
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

      final now = DateTime.now().millisecondsSinceEpoch;
      final tempQuestions = result.questions
          .asMap()
          .entries
          .map((e) => e.value.toQuestion(
                id: '${now}_${e.key}',
                bankId: 'temp',
              ))
          .toList();

      await context.read<BankProvider>().importBank(
            name: bankName,
            sourceFile: fileName,
            sourceType: ext,
            questions: tempQuestions,
          );

      if (!mounted) return;

      // 如果这是第一个题库，自动选中
      final currentProv = context.read<CurrentBankProvider>();
      if (!currentProv.hasBank) {
        final banks = context.read<BankProvider>().banks;
        if (banks.isNotEmpty) {
          currentProv.selectBank(banks.first.id);
        }
      }

      // 导入成功提示 + LLM 分析快捷入口
      final settings = context.read<SettingsProvider>();
      final hasLLM = settings.hasLLM;
      final autoAnalyze = settings.autoLlmAnalyze;
      final banks = context.read<BankProvider>().banks;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入成功：${result.questions.length} 道题'),
          action: (hasLLM && banks.isNotEmpty && !autoAnalyze)
              ? SnackBarAction(
                  label: 'LLM 分析',
                  onPressed: () {
                    _startLlmAnalysis(banks.first.id, banks.first.name);
                  },
                )
              : null,
        ),
      );

      // 自动 LLM 分析（如果设置开启且 LLM 已配置）
      if (autoAnalyze && hasLLM && banks.isNotEmpty) {
        _startLlmAnalysis(banks.first.id, banks.first.name);
      }

      // 刷新统计
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ==================== 题库管理 ====================

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
      final currentProv = context.read<CurrentBankProvider>();
      final wasCurrent = currentProv.currentBankId == id;
      await context.read<BankProvider>().deleteBank(id);
      if (wasCurrent && mounted) {
        final banks = context.read<BankProvider>().banks;
        if (banks.isNotEmpty) {
          currentProv.selectBank(banks.first.id);
        }
      }
      await _loadStats();
    }
  }

  Future<void> _startLlmAnalysis(String bankId, String bankName) async {
    final settings = context.read<SettingsProvider>();
    if (!settings.hasLLM) {
      final go = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('LLM 未配置'),
          content: const Text('请先在 AI 配置中设置 Base URL、API Key 和 Model Name。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('去配置'),
            ),
          ],
        ),
      );
      if (go == true && mounted) context.go('/settings');
      return;
    }

    // 确认 dialog
    final questions = await _dao.getBankQuestions(bankId);
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('LLM 分析'),
        content: Text('将对"$bankName"中的 ${questions.length} 道题进行 AI 分析。\n\n'
            'LLM 将根据你在 AI 配置中设定的 Prompt 筛选题目。\n'
            '分析完成后，创建测试时可选"LLM精选"模式。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('开始分析'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final client = LlmClient(
      apiKey: settings.apiKey!,
      baseUrl: settings.baseUrl!,
      modelName: settings.modelName ?? 'gpt-4o',
    );

    await showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => LlmAnalysisProgressDialog(
        bankId: bankId,
        bankName: bankName,
        client: client,
        prompt: settings.aiPrompt,
      ),
    );

    if (mounted) {
      await _loadStats();
    }
  }

  Future<void> _renameBank(String id, String currentName) async {
    final newName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _RenameBankDialog(currentName: currentName),
    );
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final bank = await _dao.getBank(id);
      if (bank != null && mounted) {
        await _dao.updateBank(bank.copyWith(name: newName));
        await context.read<BankProvider>().loadBanks();
      }
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final banks = context.watch<BankProvider>().banks;
    final currentBankId = context.watch<CurrentBankProvider>().currentBankId;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('题库抽题器'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 题库切换器 + 导入按钮
            _buildBankSwitcher(banks, currentBankId, theme),
            const SizedBox(height: 16),

            // 统计卡片
            _StatsGrid(
              totalBanks: _totalBanks,
              totalQuestions: _totalQuestions,
              totalQuizzes: _totalQuizzes,
              accuracy: _accuracy,
            ),
            const SizedBox(height: 24),

            // 错题提醒
            if (_wrongCount > 0 &&
                context.watch<SettingsProvider>().showWrongTitle)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.warning_amber,
                      color: theme.colorScheme.onErrorContainer),
                  title: Text('$_wrongCount 道错题待复习',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600)),
                  trailing: FilledButton(
                    onPressed: () => context.go('/wrongbook'),
                    style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.onErrorContainer,
                        foregroundColor: theme.colorScheme.errorContainer),
                    child: const Text('去复习'),
                  ),
                ),
              ),
            if (_wrongCount > 0) const SizedBox(height: 24),

            // 题库统计卡片区
            if (banks.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text('还没有题库，点击上方 + 导入一份吧',
                          style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 14)),
                    ],
                  ),
                ),
              )
            else
              ...banks.map((bank) {
                final isCurrent = bank.id == currentBankId;
                return _buildBankCard(bank, isCurrent, theme);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildBankSwitcher(
      List<dynamic> banks, String? currentBankId, ThemeData theme) {
    final hasBanks = banks.isNotEmpty;

    // 防御：currentBankId 不在 bank 列表中时，回退到第一个
    final bankIds = banks.map((b) => b.id as String).toList();
    final effectiveId = (currentBankId != null && bankIds.contains(currentBankId))
        ? currentBankId
        : (hasBanks ? bankIds.first : null);
    if (effectiveId != currentBankId && effectiveId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<CurrentBankProvider>().selectBank(effectiveId);
      });
    }

    return Row(
      children: [
        // 题库切换下拉
        Expanded(
          child: hasBanks
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: effectiveId,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: banks.map<DropdownMenuItem<String>>((bank) {
                      return DropdownMenuItem<String>(
                        value: bank.id,
                        child: Text(bank.name as String,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        context.read<CurrentBankProvider>().selectBank(v);
                      }
                    },
                  ),
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    child: Text('请先导入题库',
                        style: TextStyle(
                            color: theme.colorScheme.outline, fontSize: 14)),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        // 导入按钮
        IconButton.filled(
          onPressed: _importFile,
          icon: const Icon(Icons.add),
          tooltip: '导入题库',
        ),
      ],
    );
  }

  Widget _buildBankCard(dynamic bank, bool isCurrent, ThemeData theme) {
    final bankName = bank.name as String;
    final questionCount = bank.questionCount as int;
    final sourceFile = bank.sourceFile as String? ?? '';
    final dateStr = _formatDate(bank.createdAt);

    return Card(
      color: isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: ListTile(
        leading: isCurrent
            ? Icon(Icons.check_circle,
                color: theme.colorScheme.primary, size: 28)
            : Icon(Icons.library_books_outlined,
                color: theme.colorScheme.outline, size: 28),
        title: Text(bankName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$questionCount 道题 · $dateStr${sourceFile.isNotEmpty ? ' · $sourceFile' : ''}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') _renameBank(bank.id, bankName);
            if (v == 'llm_analyze') _startLlmAnalysis(bank.id, bankName);
            if (v == 'delete') _deleteBank(bank.id, bankName);
          },
          itemBuilder: (_) {
            final settings = context.read<SettingsProvider>();
            return [
              const PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('重命名'),
                ]),
              ),
              if (settings.hasLLM)
                const PopupMenuItem(
                  value: 'llm_analyze',
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text('LLM 分析'),
                  ]),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('删除', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ];
          },
        ),
        onTap: () {
          context.read<CurrentBankProvider>().selectBank(bank.id);
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ==================== 重命名对话框（独立 StatefulWidget） ====================

class _RenameBankDialog extends StatefulWidget {
  final String currentName;
  const _RenameBankDialog({required this.currentName});

  @override
  State<_RenameBankDialog> createState() => _RenameBankDialogState();
}

class _RenameBankDialogState extends State<_RenameBankDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop([String? value]) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.pop(context, value));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名题库'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '题库名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => _pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _pop(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final int totalBanks;
  final int totalQuestions;
  final int totalQuizzes;
  final double accuracy;

  const _StatsGrid({
    required this.totalBanks,
    required this.totalQuestions,
    required this.totalQuizzes,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: '题库', value: '$totalBanks')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: '题目', value: '$totalQuestions')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: '已刷', value: '$totalQuizzes 次')),
        const SizedBox(width: 8),
        Expanded(
            child: _StatCard(
                label: '正确率',
                value: '${(accuracy * 100).toStringAsFixed(0)}%')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
