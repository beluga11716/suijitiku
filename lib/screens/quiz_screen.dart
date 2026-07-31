import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../ai/llm_client.dart';
import '../widgets/quiz_card.dart';
import '../widgets/progress_bar.dart';

class QuizScreen extends StatefulWidget {
  final String sessionId;
  final String? returnTo;

  const QuizScreen({super.key, required this.sessionId, this.returnTo});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  void _showExitDialog(BuildContext context) {
    final quiz = context.read<QuizProvider>();
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出刷题'),
        content: const Text('退出后可在测试列表中继续刷题'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await quiz.saveAndExit();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.go(widget.returnTo ?? '/');
                }
              });
            },
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();

    Widget body;
    if (quiz.loading) {
      body = Scaffold(
        appBar: AppBar(title: const Text('刷题中')),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (quiz.currentSession == null) {
      body = Scaffold(
        appBar: AppBar(title: const Text('刷题')),
        body: const Center(child: Text('会话不存在')),
      );
    } else if (quiz.isExamMode) {
      body = _ExamModeView(quiz: quiz, returnTo: widget.returnTo);
    } else {
      body = _PerQuestionView(quiz: quiz, returnTo: widget.returnTo);
    }

    // BackButtonListener 在系统级拦截返回键（Android 返回键/手势），
    // 在通知到达 go_router ShellRoute Navigator 之前就消费掉。
    // PopScope 作为次级防御：拦截任何漏网的 Navigator.pop 调用。
    return BackButtonListener(
      onBackButtonPressed: () async {
        _showExitDialog(context);
        return true;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _showExitDialog(context);
        },
        child: body,
      ),
    );
  }
}

/// 逐题模式 — 两阶段交互：自由选择 → 点「确认答案」判分 → 「下一题」
class _PerQuestionView extends StatefulWidget {
  final QuizProvider quiz;
  final String? returnTo;

  const _PerQuestionView({required this.quiz, this.returnTo});

  @override
  State<_PerQuestionView> createState() => _PerQuestionViewState();
}

class _PerQuestionViewState extends State<_PerQuestionView> {
  String? _pendingAnswer;
  int _lastIndex = -1;

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final question = quiz.currentQuestion;
    final existingAnswer = quiz.getAnswerForIndex(quiz.currentIndex);
    final confirmed = existingAnswer != null;

    // 切题时重置待确认答案
    if (quiz.currentIndex != _lastIndex) {
      _lastIndex = quiz.currentIndex;
      _pendingAnswer = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            '第 ${quiz.currentIndex + 1} / ${quiz.questions.length} 题'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showExitDialog(context),
        ),
      ),
      body: Column(
        children: [
          // 进度条
          QuizProgressBar(
            current: quiz.currentIndex + 1,
            total: quiz.questions.length,
            correctCount: quiz.currentSession?.correctCount ?? 0,
          ),

          // 题目
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuizCard(
                question: question,
                showAnswer: confirmed,
                initialAnswer: existingAnswer?.userAnswer,
                userAnswer: null,
                onSelectionChanged: confirmed
                    ? null
                    : (answer) => setState(() => _pendingAnswer = answer),
                onAiGrade: confirmed ? (answer) => _gradeWithAi(question, answer) : null,
              ),
            ),
          ),

          // 底部操作栏 — 大按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (quiz.currentIndex > 0)
                    OutlinedButton(
                      onPressed: () => quiz.previousQuestion(),
                      child: const Text('上一题'),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: confirmed ? _nextButton(quiz, context) : _confirmButton(quiz),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「确认答案!」按钮 — 选完答案后点此判分
  Widget _confirmButton(QuizProvider quiz) {
    final hasAnswer = _pendingAnswer != null && _pendingAnswer!.isNotEmpty;
    return FilledButton(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: hasAnswer
          ? () async {
              await quiz.submitAnswer(_pendingAnswer!);
              setState(() {});
            }
          : null,
      child: const Text('确认答案 ✓'),
    );
  }

  /// 「下一题」/「查看结果」按钮 — 判分后出现
  Widget _nextButton(QuizProvider quiz, BuildContext context) {
    final isLast = quiz.isLastQuestion;
    return FilledButton(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        if (isLast) {
          await quiz.completeSession();
          if (context.mounted) {
            context.go('/result/${quiz.currentSession!.id}');
          }
        } else {
          quiz.nextQuestion();
        }
      },
      child: Text(isLast ? '查看结果 📊' : '下一题 →'),
    );
  }

  Future<void> _gradeWithAi(question, String userAnswer) async {
    final settings = context.read<SettingsProvider>();
    if (!settings.hasLLM) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在 AI 配置中设置 API')),
      );
      return;
    }

    BuildContext? loadingCtx;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        loadingCtx = dialogContext;
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      final client = LlmClient(
        apiKey: settings.apiKey!,
        baseUrl: settings.baseUrl!,
        modelName: settings.modelName ?? 'gpt-4o',
      );
      final result = await client.evaluateSubjectiveAnswer(
        stem: question.stem,
        referenceAnswer: question.answer,
        userAnswer: userAnswer,
      );

      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }
      if (!mounted) return;

      await showDialog(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('AI 评分'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('题目：${question.stem}', maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text('你的答案：$userAnswer', style: TextStyle(color: Colors.orange.shade800)),
                const SizedBox(height: 8),
                Text('参考答案：${question.answer}', style: TextStyle(color: Colors.green.shade800)),
                const Divider(),
                Text(result, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 评分失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出刷题'),
        content: const Text('退出后可在测试列表中继续刷题'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await widget.quiz.saveAndExit();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.go(widget.returnTo ?? '/');
                }
              });
            },
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
  }
}

/// 试卷模式
class _ExamModeView extends StatelessWidget {
  final QuizProvider quiz;
  final String? returnTo;

  const _ExamModeView({required this.quiz, this.returnTo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('试卷模式'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showExitDialog(context),
        ),
        actions: [
          TextButton(
            onPressed: () => _submitExam(context),
            child: const Text('交卷'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: quiz.questions.length,
        itemBuilder: (context, index) {
          final question = quiz.questions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('第 ${index + 1} 题',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                QuizCard(
                  question: question,
                  showAnswer: false,
                  initialAnswer:
                      quiz.getExamAnswer(question.id),
                  onSelectionChanged: (answer) =>
                      quiz.recordExamAnswer(question.id, answer),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _submitExam(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认交卷'),
        content: const Text('交卷后无法修改答案，确定提交吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续作答'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('交卷'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await quiz.submitExam();
      if (context.mounted) {
        context.go('/result/${quiz.currentSession!.id}');
      }
    }
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出刷题'),
        content: const Text('退出后可在测试列表中继续刷题'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await quiz.saveAndExit();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.go(returnTo ?? '/');
                }
              });
            },
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
  }
}
