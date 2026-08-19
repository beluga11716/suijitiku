import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/question.dart';
import '../models/quiz_answer.dart';
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

/// 逐题模式 — 滑动翻页（PageView），两阶段交互：
/// 自由选择 → 点「确认答案」判分 → 答对 0.8s 后自动滑入下一题，答错停留看解析
class _PerQuestionView extends StatefulWidget {
  final QuizProvider quiz;
  final String? returnTo;

  const _PerQuestionView({required this.quiz, this.returnTo});

  @override
  State<_PerQuestionView> createState() => _PerQuestionViewState();
}

class _PerQuestionViewState extends State<_PerQuestionView> {
  late final PageController _pageController;
  // 各题未确认的选择（页面被 PageView 回收重建后据此恢复）
  final Map<int, String> _pendingAnswers = {};
  Timer? _autoAdvanceTimer;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.quiz.currentIndex);
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;

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

          // 题目 — 左右滑动切换
          Expanded(
            child: ScrollConfiguration(
              // Windows 桌面端默认不允许鼠标拖拽滑动，显式放开
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: PageView.builder(
                controller: _pageController,
                itemCount: quiz.questions.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final question = quiz.questions[index];
                  return _QuestionPage(
                    key: ValueKey(question.id),
                    quiz: quiz,
                    question: question,
                    answered: quiz.getAnswerForIndex(index),
                    pendingAnswer: _pendingAnswers[index],
                    isLast: index == quiz.questions.length - 1,
                    onSelectionChanged: (answer) =>
                        setState(() => _pendingAnswers[index] = answer),
                    onConfirmed: (isCorrect) =>
                        _handleConfirmed(index, isCorrect),
                    onNext: () => _goNext(index),
                    onFinish: _finishQuiz,
                    onAiGrade: (answer) => _gradeWithAi(question, answer),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 滑动翻页：取消自动跳题计时，同步当前题号并持久化进度
  void _onPageChanged(int index) {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    widget.quiz.goToQuestion(index);
  }

  /// 确认答案后：答对 → 展示反馈 0.8s 后自动进入下一题（最后一题直接出结果）；
  /// 答错 → 停留本页看解析，用户滑动切换
  void _handleConfirmed(int index, bool isCorrect) {
    if (!isCorrect) return;
    _autoAdvanceTimer?.cancel();
    final isLast = index >= widget.quiz.questions.length - 1;
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 800), () {
      _autoAdvanceTimer = null;
      if (!mounted) return;
      if (isLast) {
        _finishQuiz();
      } else if (_pageController.hasClients &&
          (_pageController.page?.round() ?? -1) == index) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  /// 答错停留时点「下一题」：手动进入下一题（最后一题直接出结果）
  void _goNext(int index) {
    final isLast = index >= widget.quiz.questions.length - 1;
    if (isLast) {
      _finishQuiz();
    } else if (_pageController.hasClients &&
        (_pageController.page?.round() ?? -1) == index) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 完成会话并跳转结果页
  Future<void> _finishQuiz() async {
    if (_finishing) return;
    _finishing = true;
    _autoAdvanceTimer?.cancel();
    final quiz = widget.quiz;
    await quiz.completeSession();
    if (mounted) {
      context.go('/result/${quiz.currentSession!.id}');
    }
  }

  Future<void> _gradeWithAi(Question question, String userAnswer) async {
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

/// PageView 单页：题目卡片 + 底部操作区（确认答案 / 查看结果 / 答错提示）
class _QuestionPage extends StatelessWidget {
  final QuizProvider quiz;
  final Question question;
  final QuizAnswer? answered;
  final String? pendingAnswer;
  final bool isLast;
  final void Function(String answer) onSelectionChanged;
  final void Function(bool isCorrect) onConfirmed;
  final void Function() onNext;
  final void Function() onFinish;
  final void Function(String answer)? onAiGrade;

  const _QuestionPage({
    super.key,
    required this.quiz,
    required this.question,
    this.answered,
    this.pendingAnswer,
    required this.isLast,
    required this.onSelectionChanged,
    required this.onConfirmed,
    required this.onNext,
    required this.onFinish,
    this.onAiGrade,
  });

  @override
  Widget build(BuildContext context) {
    final answered = this.answered;
    final confirmed = answered != null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: QuizCard(
              question: question,
              showAnswer: confirmed,
              initialAnswer: answered?.userAnswer ?? pendingAnswer,
              onSelectionChanged: confirmed ? null : onSelectionChanged,
              onAiGrade: confirmed ? onAiGrade : null,
              typeRowTrailing: _buildTypeRowTrailing(confirmed, answered),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildBottom(answered),
          ),
        ),
      ],
    );
  }

  /// 题型行右槽位：未确认 → 「确认答案 ✓」；答错已确认 → 「下一题」
  /// （答对由自动跳题接管，最后一题底部已有「查看结果」按钮）
  Widget? _buildTypeRowTrailing(bool confirmed, QuizAnswer? answered) {
    if (!confirmed) return _buildConfirmButton();
    if (answered!.isCorrect || isLast) return null;
    return _buildNextButton();
  }

  /// 「确认答案 ✓」按钮 — 放在题型标签行最右侧，方便点按
  Widget _buildConfirmButton() {
    final hasAnswer = pendingAnswer != null && pendingAnswer!.isNotEmpty;
    return FilledButton(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: hasAnswer
          ? () async {
              final result = await quiz.submitAnswer(pendingAnswer!);
              onConfirmed(result.isCorrect);
            }
          : null,
      child: const Text('确认答案 ✓'),
    );
  }

  /// 「下一题」按钮 — 答错确认后出现在题型行最右侧，点击手动跳题
  Widget _buildNextButton() {
    return FilledButton(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onNext,
      child: const Text('下一题 →'),
    );
  }

  Widget _buildBottom(QuizAnswer? answered) {
    final buttonStyle = FilledButton.styleFrom(
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (answered == null) {
      // 未作答：确认按钮已移到题型行最右侧，底部留空
      return const SizedBox.shrink();
    }

    if (isLast) {
      // 最后一题已作答：查看结果
      return SizedBox(
        height: 52,
        child: FilledButton(
          style: buttonStyle,
          onPressed: onFinish,
          child: const Text('查看结果 📊'),
        ),
      );
    }

    if (!answered.isCorrect) {
      // 答错停留：题型行有「下一题」按钮，也可滑动切换
      return Center(
        child: Text(
          '答错了 · 点「下一题」或左右滑动',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }

    // 答对：自动跳题中，无需底部操作
    return const SizedBox.shrink();
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
