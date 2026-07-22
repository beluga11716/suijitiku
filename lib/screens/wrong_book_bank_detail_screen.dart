import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/wrong_book_provider.dart';
import '../providers/quiz_provider.dart';
import '../database/dao.dart';
import '../models/question.dart';
import '../widgets/quiz_card.dart';

class WrongBookBankDetailScreen extends StatefulWidget {
  final String bankId;

  const WrongBookBankDetailScreen({super.key, required this.bankId});

  @override
  State<WrongBookBankDetailScreen> createState() =>
      _WrongBookBankDetailScreenState();
}

class _WrongBookBankDetailScreenState
    extends State<WrongBookBankDetailScreen> {
  final _dao = Dao();
  String _bankName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<WrongBookProvider>();
    final bank = await _dao.getBank(widget.bankId);
    await provider.loadWrongQuestionsByBank(widget.bankId);
    if (mounted) {
      setState(() {
        _bankName = bank?.name ?? '未知题库';
        _loading = false;
      });
    }
  }

  void _openQuestionDetail(Question question) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => QuestionDetailPage(question: question),
      ),
    );
  }

  Future<void> _startWrongQuiz() async {
    final provider = context.read<WrongBookProvider>();
    final count = provider.count;
    if (count == 0) return;

    final result = await showDialog<Map>(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _CreateWrongBookDialog(totalCount: count, bankName: _bankName),
    );

    if (result == null || !mounted) return;

    await context.read<QuizProvider>().startWrongBookSessionByBank(
          bankId: widget.bankId,
          count: result['count'] as int,
          quizStyle: result['style'] as String,
          name: result['name'] as String,
        );

    if (!mounted) return;
    final quiz = context.read<QuizProvider>();
    if (quiz.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(quiz.error!)));
      return;
    }
    context.go('/quiz/${quiz.currentSession!.id}?returnTo=/wrongbook/${widget.bankId}');
  }

  Future<void> _clearBankWrongQuestions() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空错题'),
        content: Text('确定要清空"$_bankName"的所有错题记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WrongBookProvider>().clearByBank(widget.bankId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WrongBookProvider>();
    final wrongQuestions = provider.wrongQuestions;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/wrongbook'),
        ),
        title: Text(_bankName),
        actions: [
          if (wrongQuestions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearBankWrongQuestions,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wrongQuestions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('该题库没有错题',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                      const SizedBox(height: 8),
                      const Text('继续保持'),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 统计
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text('${provider.count}',
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red)),
                                    const Text('错题数'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 72,
                              child: FilledButton.icon(
                                onPressed: _startWrongQuiz,
                                icon: const Icon(Icons.replay),
                                label: const Text('刷错题'),
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 错题列表
                    Expanded(
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: wrongQuestions.length,
                        itemBuilder: (_, i) {
                          final q = wrongQuestions[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.error,
                                foregroundColor:
                                    theme.colorScheme.onError,
                                child: Text('${i + 1}'),
                              ),
                              title: Text(q.stem,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${q.type.label} · 答案：${q.answer}'),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: () => _openQuestionDetail(q),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ==================== 错题详情页 ====================

class QuestionDetailPage extends StatefulWidget {
  final Question question;
  const QuestionDetailPage({super.key, required this.question});

  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  final _dao = Dao();
  String? _userAnswer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final answer = await _dao.getLastWrongAnswer(widget.question.id);
    if (mounted) {
      setState(() {
        _userAnswer = answer;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('题目详情'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuizCard(
                question: widget.question,
                showAnswer: true,
                initialAnswer: _userAnswer,
              ),
            ),
    );
  }
}

// ==================== 创建错题测试 Dialog ====================

class _CreateWrongBookDialog extends StatefulWidget {
  final int totalCount;
  final String bankName;
  const _CreateWrongBookDialog(
      {required this.totalCount, required this.bankName});

  @override
  State<_CreateWrongBookDialog> createState() =>
      _CreateWrongBookDialogState();
}

class _CreateWrongBookDialogState extends State<_CreateWrongBookDialog> {
  late final TextEditingController _nameCtrl;
  String _quizStyle = 'per_question';
  late int _selectedCount;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    final now = DateTime.now();
    _nameCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${widget.bankName} 错题复习';
    _selectedCount =
        (widget.totalCount / 2).round().clamp(1, widget.totalCount);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建错题测试'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '测试名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('答题方式'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'per_question',
                  label: Text('逐题'),
                  icon: Icon(Icons.looks_one)),
              ButtonSegment(
                  value: 'exam',
                  label: Text('试卷'),
                  icon: Icon(Icons.assignment)),
            ],
            selected: {_quizStyle},
            onSelectionChanged: (v) =>
                setState(() => _quizStyle = v.first),
          ),
          const SizedBox(height: 12),
          Text('题目数量: $_selectedCount 题'),
          Slider(
            value: _selectedCount.toDouble(),
            min: 1,
            max: widget.totalCount.toDouble(),
            divisions: widget.totalCount > 1 ? widget.totalCount - 1 : null,
            label: '$_selectedCount',
            onChanged: (v) =>
                setState(() => _selectedCount = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': _nameCtrl.text.trim(),
              'style': _quizStyle,
              'count': _selectedCount,
            });
          },
          child: const Text('开始'),
        ),
      ],
    );
  }
}
