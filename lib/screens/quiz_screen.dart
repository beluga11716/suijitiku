import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/quiz_provider.dart';
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
  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();

    if (quiz.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('刷题中')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (quiz.currentSession == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('刷题')),
        body: const Center(child: Text('会话不存在')),
      );
    }

    if (quiz.isExamMode) {
      return _ExamModeView(quiz: quiz, returnTo: widget.returnTo);
    } else {
      return _PerQuestionView(quiz: quiz, returnTo: widget.returnTo);
    }
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
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.quiz.saveAndExit();
              context.go(widget.returnTo ?? '/');
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
            onPressed: () {
              Navigator.pop(dialogContext);
              quiz.saveAndExit();
              context.go(returnTo ?? '/');
            },
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
  }
}
