class QuizAnswer {
  final String id;
  final String sessionId;
  final String? questionId;
  final String userAnswer;
  final bool isCorrect;
  final DateTime answeredAt;

  QuizAnswer({
    required this.id,
    required this.sessionId,
    this.questionId,
    required this.userAnswer,
    required this.isCorrect,
    DateTime? answeredAt,
  }) : answeredAt = answeredAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'question_id': questionId,
        'user_answer': userAnswer,
        'is_correct': isCorrect ? 1 : 0,
        'answered_at': answeredAt.toIso8601String(),
      };

  factory QuizAnswer.fromMap(Map<String, dynamic> map) => QuizAnswer(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        questionId: map['question_id'] as String?,
        userAnswer: map['user_answer'] as String? ?? '',
        isCorrect: (map['is_correct'] as int?) == 1,
        answeredAt:
            DateTime.tryParse(map['answered_at'] as String? ?? '') ??
                DateTime.now(),
      );
}
