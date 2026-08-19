import 'dart:math';
import 'package:flutter/foundation.dart';
import '../database/dao.dart';
import '../models/question.dart';
import '../models/quiz_session.dart';
import '../models/quiz_answer.dart';
import '../ai/llm_analysis_service.dart';
import 'package:uuid/uuid.dart';

class QuizProvider extends ChangeNotifier {
  final Dao _dao = Dao();
  final _uuid = const Uuid();

  QuizSession? _currentSession;
  QuizSession? get currentSession => _currentSession;

  List<Question> _questions = [];
  List<Question> get questions => _questions;

  // 逐题模式当前索引
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  // 试卷模式：用户答案映射 questionId -> userAnswer
  final Map<String, String> _examAnswers = {};

  // 逐题模式：已答题记录 (索引 -> answer)
  final Map<int, QuizAnswer> _answeredMap = {};

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Question get currentQuestion => _questions[_currentIndex];

  bool get isExamMode => _currentSession?.quizStyle == 'exam';

  bool get isCompleted => _currentSession?.status == 'completed';

  /// 开始一次刷题
  Future<void> startSession({
    required String bankId,
    required String mode, // 'basic' | 'featured'
    required String quizStyle, // 'per_question' | 'exam'
    required int count,
    String name = '',
    List<String>? questionTypes,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // 获取题库题目
      List<Question> allQuestions = await _dao.getBankQuestions(bankId);

      // 题型筛选
      if (questionTypes != null && questionTypes.isNotEmpty) {
        allQuestions = allQuestions
            .where((q) => questionTypes.contains(q.type.dbValue))
            .toList();
      }

      if (allQuestions.isEmpty) {
        _error = '题库中没有符合条件的题目';
        _loading = false;
        notifyListeners();
        return;
      }

      // 按模式抽取题目
      if (mode == 'featured') {
        // LLM 分析模式：只取 LLM 选中的题目（featuredScore > 0），按分降序，最多 120 道
        allQuestions = allQuestions.where((q) => q.featuredScore > 0).toList();
        allQuestions.sort((a, b) => b.featuredScore.compareTo(a.featuredScore));
        if (allQuestions.length > LlmAnalysisService.maxFeaturedQuestions) {
          allQuestions = allQuestions.take(LlmAnalysisService.maxFeaturedQuestions).toList();
        }
      } else {
        allQuestions.shuffle(Random());
      }

      _questions = allQuestions.take(count).toList();
      _currentIndex = 0;
      _examAnswers.clear();
      _answeredMap.clear();

      final questionIds = _questions.map((q) => q.id).toList();

      final session = QuizSession(
        id: _uuid.v4(),
        bankId: bankId,
        mode: mode,
        quizStyle: quizStyle,
        questionCount: _questions.length,
        name: name,
        source: 'bank',
        questionTypes: questionTypes,
        questionIds: questionIds,
      );

      await _dao.insertSession(session);
      _currentSession = session;

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  /// 逐题模式：提交单道题答案
  Future<QuizAnswer> submitAnswer(String userAnswer) async {
    final question = currentQuestion;
    final isCorrect = _checkAnswer(question, userAnswer);

    final answer = QuizAnswer(
      id: _uuid.v4(),
      sessionId: _currentSession!.id,
      questionId: question.id,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );

    await _dao.insertAnswer(answer);
    _answeredMap[_currentIndex] = answer;

    // 更新会话计数
    int correct = 0;
    int wrong = 0;
    for (final a in _answeredMap.values) {
      if (a.isCorrect) {
        correct++;
      } else {
        wrong++;
      }
    }

    _currentSession = _currentSession!.copyWith(
      correctCount: correct,
      wrongCount: wrong,
    );
    await _dao.updateSession(_currentSession!);

    // 错题处理
    if (!isCorrect) {
      await _dao.addWrongQuestion(question.id);
    }

    notifyListeners();
    return answer;
  }

  /// 滑动跳转到指定题（逐题模式），持久化进度
  Future<void> goToQuestion(int index) async {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    _currentIndex = index;
    await _saveProgress();
    notifyListeners();
  }

  /// 持久化当前进度（不触发 UI 更新）
  Future<void> _saveProgress() async {
    if (_currentSession == null) return;
    _currentSession = _currentSession!.copyWith(
      currentIndex: _currentIndex,
    );
    await _dao.updateSession(_currentSession!);
  }

  /// 试卷模式：记录答案
  void recordExamAnswer(String questionId, String userAnswer) {
    _examAnswers[questionId] = userAnswer;
    notifyListeners();
  }

  /// 试卷模式：提交全部答案
  Future<void> submitExam() async {
    _loading = true;
    notifyListeners();

    int correct = 0;
    int wrong = 0;

    for (final question in _questions) {
      final userAnswer = _examAnswers[question.id] ?? '';
      final isCorrect = _checkAnswer(question, userAnswer);

      final answer = QuizAnswer(
        id: _uuid.v4(),
        sessionId: _currentSession!.id,
        questionId: question.id,
        userAnswer: userAnswer,
        isCorrect: isCorrect,
      );

      await _dao.insertAnswer(answer);
      if (isCorrect) {
        correct++;
      } else {
        wrong++;
        await _dao.addWrongQuestion(question.id);
      }
    }

    _currentSession = _currentSession!.copyWith(
      correctCount: correct,
      wrongCount: wrong,
      status: 'completed',
      completedAt: DateTime.now(),
    );
    await _dao.updateSession(_currentSession!);

    _loading = false;
    notifyListeners();
  }

  /// 完成会话
  Future<void> completeSession() async {
    _currentSession = _currentSession!.copyWith(
      status: 'completed',
      completedAt: DateTime.now(),
    );
    await _dao.updateSession(_currentSession!);
    notifyListeners();
  }

  /// 错题本刷题（指定题库）
  Future<void> startWrongBookSessionByBank({
    required String bankId,
    required int count,
    required String quizStyle,
    String name = '',
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final wrongQuestions = await _dao.getWrongQuestionsByBank(bankId);
      if (wrongQuestions.isEmpty) {
        _error = '该题库没有错题';
        _loading = false;
        notifyListeners();
        return;
      }

      wrongQuestions.shuffle(Random());
      _questions = wrongQuestions.take(count).toList();
      _currentIndex = 0;
      _examAnswers.clear();
      _answeredMap.clear();

      final questionIds = _questions.map((q) => q.id).toList();

      final session = QuizSession(
        id: _uuid.v4(),
        bankId: bankId,
        mode: 'basic',
        quizStyle: quizStyle,
        questionCount: _questions.length,
        name: name,
        source: 'wrongbook',
        questionIds: questionIds,
      );

      await _dao.insertSession(session);
      _currentSession = session;

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  /// 错题本刷题（全部题库）
  Future<void> startWrongBookSession({
    required int count,
    required String quizStyle,
    String name = '',
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final wrongQuestions = await _dao.getWrongQuestions();
      if (wrongQuestions.isEmpty) {
        _error = '没有错题';
        _loading = false;
        notifyListeners();
        return;
      }

      wrongQuestions.shuffle(Random());
      _questions = wrongQuestions.take(count).toList();
      _currentIndex = 0;
      _examAnswers.clear();
      _answeredMap.clear();

      final questionIds = _questions.map((q) => q.id).toList();

      final session = QuizSession(
        id: _uuid.v4(),
        bankId: null,
        mode: 'basic',
        quizStyle: quizStyle,
        questionCount: _questions.length,
        name: name,
        source: 'wrongbook',
        questionIds: questionIds,
      );

      await _dao.insertSession(session);
      _currentSession = session;

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  // ==================== 判分逻辑 ====================

  bool _checkAnswer(Question question, String userAnswer) {
    final correct = question.answer.trim().toUpperCase();
    final user = userAnswer.trim().toUpperCase();

    switch (question.type) {
      case QuestionType.singleChoice:
      case QuestionType.trueFalse:
        return correct == user;
      case QuestionType.multiChoice:
        // 多选：排序后比较
        final sortedCorrect = correct.split('').where((c) => c.trim().isNotEmpty).toList()..sort();
        final sortedUser = user.split('').where((c) => c.trim().isNotEmpty).toList()..sort();
        return sortedCorrect.join() == sortedUser.join();
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
        // 主观题：标准化后比较（LLM 模式下应该有更复杂的判断）
        return correct == user;
    }
  }

  /// 获取某道题的作答记录（逐题模式）
  QuizAnswer? getAnswerForIndex(int index) => _answeredMap[index];

  /// 获取某道题的作答记录（试卷模式）
  String getExamAnswer(String questionId) => _examAnswers[questionId] ?? '';

  /// 恢复未完成的测试
  Future<void> resumeSession(String sessionId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _dao.getSession(sessionId);
      if (session == null) {
        _error = '测试不存在';
        _loading = false;
        notifyListeners();
        return;
      }

      List<Question> allQuestions;
      if (session.source == 'wrongbook' && session.bankId != null) {
        allQuestions = await _dao.getWrongQuestionsByBank(session.bankId!);
      } else if (session.source == 'wrongbook') {
        allQuestions = await _dao.getWrongQuestions();
      } else if (session.bankId != null) {
        allQuestions = await _dao.getBankQuestions(session.bankId!);
        // 题型筛选
        if (session.questionTypes != null &&
            session.questionTypes!.isNotEmpty) {
          allQuestions = allQuestions
              .where((q) =>
                  session.questionTypes!.contains(q.type.dbValue))
              .toList();
        }
      } else {
        allQuestions = [];
      }

      // 按 questionIds 重建题目顺序
      if (session.questionIds != null &&
          session.questionIds!.isNotEmpty) {
        final questionMap = <String, Question>{};
        for (final q in allQuestions) {
          questionMap[q.id] = q;
        }
        _questions = [];
        for (final id in session.questionIds!) {
          final q = questionMap[id];
          if (q != null) _questions.add(q);
        }
        // 补充新题（如果题目库有更新）
        for (final id in session.questionIds!) {
          if (!questionMap.containsKey(id)) {
            // 题目已被删除，跳过
          }
        }
      } else {
        // 没有 questionIds（旧数据），按原逻辑
        if (session.mode == 'featured') {
          allQuestions = allQuestions.where((q) => q.featuredScore > 0).toList();
          allQuestions
              .sort((a, b) => b.featuredScore.compareTo(a.featuredScore));
          if (allQuestions.length > LlmAnalysisService.maxFeaturedQuestions) {
            allQuestions = allQuestions.take(LlmAnalysisService.maxFeaturedQuestions).toList();
          }
        } else {
          allQuestions.shuffle(Random());
        }
        _questions = allQuestions.take(session.questionCount).toList();
      }

      _currentIndex = session.currentIndex;
      _examAnswers.clear();
      _answeredMap.clear();

      // 恢复已有的答题记录
      final answers = await _dao.getSessionAnswers(sessionId);
      for (int i = 0; i < answers.length; i++) {
        final a = answers[i];
        final idx = _questions.indexWhere((q) => q.id == a.questionId);
        if (idx >= 0) {
          _answeredMap[idx] = a;
        } else {
          // 该答案对应的题目可能已被删除，将答案保存在第一个未映射位置
        }
      }

      _currentSession = session;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  /// 保存进度并退出
  Future<void> saveAndExit() async {
    if (_currentSession == null) return;
    _currentSession = _currentSession!.copyWith(
      currentIndex: _currentIndex,
      status: 'in_progress',
    );
    await _dao.updateSession(_currentSession!);
    notifyListeners();
  }

  /// 丢弃当前测试
  Future<void> discardAndExit() async {
    if (_currentSession == null) return;
    await _dao.deleteSession(_currentSession!.id);
    reset();
  }

  void reset() {
    _currentSession = null;
    _questions = [];
    _currentIndex = 0;
    _examAnswers.clear();
    _answeredMap.clear();
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
