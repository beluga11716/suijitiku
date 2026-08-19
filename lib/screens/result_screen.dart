import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../database/dao.dart';
import '../models/question.dart';
import '../models/quiz_session.dart';
import '../models/quiz_answer.dart';

class ResultScreen extends StatefulWidget {
  final String sessionId;

  const ResultScreen({super.key, required this.sessionId});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _dao = Dao();
  QuizSession? _session;
  List<QuizAnswer> _answers = [];
  Map<String, Question> _questionMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadResult());
  }

  Future<void> _loadResult() async {
    final session = await _dao.getSession(widget.sessionId);
    final answers = await _dao.getSessionAnswers(widget.sessionId);

    final questionMap = <String, Question>{};
    for (final a in answers) {
      if (a.questionId != null) {
        final q = await _dao.getQuestionById(a.questionId!);
        if (q != null) questionMap[a.questionId!] = q;
      }
    }

    if (mounted) {
      setState(() {
        _session = session;
        _answers = answers;
        _questionMap = questionMap;
        _loading = false;
      });
    }
  }

  /// 返回目标——与顶栏返回按钮一致：
  /// 错题测试 → 错题测试列表（已完成 tab）；题库测试 → 刷题列表（已完成 tab）
  String get _backPath => _session?.source == 'wrongbook'
      ? '/wrongbook?sub=tests&tab=1'
      : '/tests?tab=1';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = Scaffold(
        appBar: AppBar(title: const Text('结果')),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (_session == null) {
      body = Scaffold(
        appBar: AppBar(title: const Text('结果')),
        body: const Center(child: Text('结果不存在')),
      );
    } else {
      body = _buildResult(theme);
    }

    // 与刷题页同一套返回键防御：BackButtonListener 系统级拦截 + PopScope 兜底，
    // 行为 = 顶栏返回按钮（回到对应列表页，保留已完成 tab）。
    // 没有这套拦截时，Android 13+ 上系统级返回会直接销毁 Activity（app 退出）。
    return BackButtonListener(
      onBackButtonPressed: () async {
        context.go(_backPath);
        return true;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.go(_backPath);
        },
        child: body,
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    final accuracy = _session!.answeredCount > 0
        ? (_session!.correctCount / _session!.answeredCount * 100)
            .toStringAsFixed(1)
        : '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('刷题结果'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(_backPath),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 总览卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    '${_session!.correctCount} / ${_session!.answeredCount}',
                    style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _session!.correctCount ==
                                _session!.answeredCount
                            ? Colors.green
                            : theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text('正确率 $accuracy%',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MiniStat(
                          label: '正确',
                          value: '${_session!.correctCount}',
                          color: Colors.green),
                      const SizedBox(width: 24),
                      _MiniStat(
                          label: '错误',
                          value: '${_session!.wrongCount}',
                          color: Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 逐题回顾
          Text('题目回顾',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          ..._answers.asMap().entries.map((entry) {
            final index = entry.key;
            final answer = entry.value;
            final question = _questionMap[answer.questionId];

            return Card(
              color: answer.isCorrect
                  ? null
                  : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          answer.isCorrect
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: answer.isCorrect
                              ? Colors.green
                              : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '第 ${index + 1} 题 ${question?.type.label ?? ""}',
                            style:
                                theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                    if (question != null) ...[
                      const SizedBox(height: 8),
                      Text(question.stem,
                          style: theme.textTheme.bodyMedium),
                      if (question.options.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ...question.options.map((opt) => Text(
                              opt,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme
                                      .onSurfaceVariant),
                            )),
                      ],
                      const SizedBox(height: 8),
                      Text('正确答案：${question.answer}',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600)),
                      if (answer.userAnswer.isNotEmpty &&
                          !answer.isCorrect)
                        Text(
                            '你的答案：${answer.userAnswer}',
                            style: TextStyle(
                                color: Colors.red.shade700)),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
