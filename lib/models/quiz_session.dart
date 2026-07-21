class QuizSession {
  final String id;
  final String? bankId;
  final String mode; // 'basic' | 'featured'
  final String quizStyle; // 'per_question' | 'exam'
  final int questionCount;
  final int correctCount;
  final int wrongCount;
  final String status; // 'in_progress' | 'completed'
  final DateTime startedAt;
  final DateTime? completedAt;
  final String name; // 测试名称
  final int currentIndex; // 逐题模式恢复位置
  final String source; // 'bank' | 'wrongbook'
  final List<String>? questionTypes; // 题型筛选 (dbValue 列表)
  final List<String>? questionIds; // 题目 ID 列表（恢复顺序用）

  QuizSession({
    required this.id,
    this.bankId,
    required this.mode,
    required this.quizStyle,
    required this.questionCount,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.status = 'in_progress',
    DateTime? startedAt,
    this.completedAt,
    this.name = '',
    this.currentIndex = 0,
    this.source = 'bank',
    this.questionTypes,
    this.questionIds,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'mode': mode,
        'quiz_style': quizStyle,
        'question_count': questionCount,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'status': status,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'name': name,
        'current_index': currentIndex,
        'source': source,
        'question_types':
            questionTypes != null ? _listToJson(questionTypes!) : null,
        'question_ids':
            questionIds != null ? _listToJson(questionIds!) : null,
      };

  factory QuizSession.fromMap(Map<String, dynamic> map) => QuizSession(
        id: map['id'] as String,
        bankId: map['bank_id'] as String?,
        mode: map['mode'] as String? ?? 'basic',
        quizStyle: map['quiz_style'] as String? ?? 'per_question',
        questionCount: (map['question_count'] as int?) ?? 0,
        correctCount: (map['correct_count'] as int?) ?? 0,
        wrongCount: (map['wrong_count'] as int?) ?? 0,
        status: map['status'] as String? ?? 'in_progress',
        startedAt:
            DateTime.tryParse(map['started_at'] as String? ?? '') ??
                DateTime.now(),
        completedAt:
            DateTime.tryParse(map['completed_at'] as String? ?? ''),
        name: map['name'] as String? ?? '',
        currentIndex: (map['current_index'] as int?) ?? 0,
        source: map['source'] as String? ?? 'bank',
        questionTypes: _jsonToList(map['question_types'] as String?),
        questionIds: _jsonToList(map['question_ids'] as String?),
      );

  QuizSession copyWith({
    String? name,
    int? currentIndex,
    String? source,
    List<String>? questionTypes,
    List<String>? questionIds,
    int? correctCount,
    int? wrongCount,
    String? status,
    DateTime? completedAt,
  }) =>
      QuizSession(
        id: id,
        bankId: bankId,
        mode: mode,
        quizStyle: quizStyle,
        questionCount: questionCount,
        correctCount: correctCount ?? this.correctCount,
        wrongCount: wrongCount ?? this.wrongCount,
        status: status ?? this.status,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        name: name ?? this.name,
        currentIndex: currentIndex ?? this.currentIndex,
        source: source ?? this.source,
        questionTypes: questionTypes ?? this.questionTypes,
        questionIds: questionIds ?? this.questionIds,
      );

  bool get isCompleted => status == 'completed';
  int get answeredCount => correctCount + wrongCount;
  int get remainingCount => questionCount - answeredCount;
  double get accuracy =>
      answeredCount > 0 ? correctCount / answeredCount : 0.0;

  static String _listToJson(List<String> list) =>
      '["${list.join('","')}"]';

  static List<String>? _jsonToList(String? json) {
    if (json == null || json.isEmpty || json == 'null') return null;
    try {
      return (json
              .substring(1, json.length - 1)
              .split(',')
              .map((s) => s.trim().replaceAll('"', ''))
              .where((s) => s.isNotEmpty))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
