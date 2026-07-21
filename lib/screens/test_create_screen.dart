import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../models/question.dart';
import '../database/dao.dart';

class TestCreateScreen extends StatefulWidget {
  final String bankId;

  const TestCreateScreen({super.key, required this.bankId});

  @override
  State<TestCreateScreen> createState() => _TestCreateScreenState();
}

class _TestCreateScreenState extends State<TestCreateScreen> {
  final _dao = Dao();
  final _nameController = TextEditingController();
  String _bankName = '';
  int _totalQuestions = 100;
  int _selectedCount = 1;
  String _mode = 'basic'; // 'basic' | 'featured'
  String _quizStyle = 'per_question'; // 'per_question' | 'exam'
  bool _hasSubjective = false;
  Set<QuestionType> _selectedTypes = QuestionType.values.toSet();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBankInfo());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadBankInfo() async {
    final hasLLM = context.read<SettingsProvider>().hasLLM;
    final bank = await _dao.getBank(widget.bankId);
    final questions = await _dao.getBankQuestions(widget.bankId);

    if (mounted) {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _nameController.text = '$dateStr ${bank?.name ?? ''}';

      setState(() {
        _bankName = bank?.name ?? '未知题库';
        _totalQuestions = questions.length;
        _selectedCount = (_totalQuestions / 2).round().clamp(1, 50);
        _hasSubjective = questions.any((q) => !q.type.isObjective);
        if (_hasSubjective && !hasLLM) {
          final objectiveCount =
              questions.where((q) => q.type.isObjective).length;
          _totalQuestions = objectiveCount;
        }
      });
    }
  }

  Future<void> _startQuiz() async {
    final hasLLM = context.read<SettingsProvider>().hasLLM;
    if (!hasLLM && _hasSubjective) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('含主观题需先配置 LLM API，请在设置中配置')));
      return;
    }

    final name = _nameController.text.trim();
    final types = _selectedTypes.length == QuestionType.values.length
        ? null
        : _selectedTypes.map((t) => t.dbValue).toList();

    await context.read<QuizProvider>().startSession(
          bankId: widget.bankId,
          mode: _mode,
          quizStyle: _quizStyle,
          count: _selectedCount,
          name: name,
          questionTypes: types,
        );

    if (!mounted) return;

    final quiz = context.read<QuizProvider>();
    if (quiz.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(quiz.error!)));
      return;
    }

    context.go('/quiz/${quiz.currentSession!.id}?returnTo=/banks/${widget.bankId}/tests');
  }

  @override
  Widget build(BuildContext context) {
    final hasLLM = context.watch<SettingsProvider>().hasLLM;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/banks/${widget.bankId}/tests'),
        ),
        title: const Text('创建测试'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 题库信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.library_books, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_bankName,
                            style: theme.textTheme.titleMedium),
                        Text('共 $_totalQuestions 道客观题'
                            '${_hasSubjective ? '（含主观题，需配 LLM）' : ''}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 测试名称
          Text('测试名称', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: '输入测试名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // 题目数量
          Text('题目数量', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _selectedCount.toDouble(),
                  min: 1,
                  max: _totalQuestions.toDouble().clamp(1, 100),
                  divisions: _totalQuestions.clamp(0, 100),
                  label: '$_selectedCount',
                  onChanged: (v) =>
                      setState(() => _selectedCount = v.round()),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('$_selectedCount 题',
                    style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 抽题模式
          Text('抽题模式', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'basic',
                  label: Text('随机抽取'),
                  icon: Icon(Icons.shuffle)),
              ButtonSegment(
                  value: 'featured',
                  label: Text('AI 精选'),
                  icon: Icon(Icons.auto_awesome)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          if (_mode == 'featured')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '精选模式按题目难度、重要性、理论性综合排序，优先抽取高分题',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 24),

          // 答题方式
          Text('答题方式', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'per_question',
                  label: Text('逐题模式'),
                  icon: Icon(Icons.looks_one)),
              ButtonSegment(
                  value: 'exam',
                  label: Text('试卷模式'),
                  icon: Icon(Icons.assignment)),
            ],
            selected: {_quizStyle},
            onSelectionChanged: (v) =>
                setState(() => _quizStyle = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            _quizStyle == 'per_question'
                ? '每次显示一道题，作答后立即显示对错'
                : '所有题显示在一个页面，最后统一交卷判分',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // 题型筛选
          Text('题型筛选', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: QuestionType.values.map((type) {
              final selected = _selectedTypes.contains(type);
              return FilterChip(
                label: Text(type.label),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedTypes.add(type);
                    } else {
                      // 至少保留一种题型
                      if (_selectedTypes.length > 1) {
                        _selectedTypes.remove(type);
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            '至少选择一种题型',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          // 主观题提示
          if (_hasSubjective && !hasLLM)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color:
                              theme.colorScheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '此题库含主观题，需先在设置中配置 LLM API 后方可刷题',
                          style: TextStyle(
                              color: theme
                                  .colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 32),

          // 开始按钮
          FilledButton.icon(
            onPressed: (_hasSubjective && !hasLLM) ? null : _startQuiz,
            icon: const Icon(Icons.play_arrow),
            label: const Text('创建并开始'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
