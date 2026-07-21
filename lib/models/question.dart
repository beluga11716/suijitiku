import 'dart:convert';

enum QuestionType {
  singleChoice,
  multiChoice,
  trueFalse,
  fillBlank,
  shortAnswer;

  String get label {
    switch (this) {
      case QuestionType.singleChoice:
        return '单选题';
      case QuestionType.multiChoice:
        return '多选题';
      case QuestionType.trueFalse:
        return '判断题';
      case QuestionType.fillBlank:
        return '填空题';
      case QuestionType.shortAnswer:
        return '简答题';
    }
  }

  String get dbValue {
    switch (this) {
      case QuestionType.singleChoice:
        return 'single_choice';
      case QuestionType.multiChoice:
        return 'multi_choice';
      case QuestionType.trueFalse:
        return 'true_false';
      case QuestionType.fillBlank:
        return 'fill_blank';
      case QuestionType.shortAnswer:
        return 'short_answer';
    }
  }

  /// 是否是客观题（可以自动判分）
  bool get isObjective =>
      this == QuestionType.singleChoice ||
      this == QuestionType.multiChoice ||
      this == QuestionType.trueFalse;

  factory QuestionType.fromDb(String value) {
    switch (value) {
      case 'single_choice':
        return QuestionType.singleChoice;
      case 'multi_choice':
        return QuestionType.multiChoice;
      case 'true_false':
        return QuestionType.trueFalse;
      case 'fill_blank':
        return QuestionType.fillBlank;
      case 'short_answer':
        return QuestionType.shortAnswer;
      default:
        return QuestionType.singleChoice;
    }
  }
}

class Question {
  final String id;
  final String bankId;
  final QuestionType type;
  final String stem;
  final List<String> options;
  final String answer;
  final String? explanation;
  final double difficultyScore;
  final double importanceScore;
  final double theoryScore;
  final double featuredScore;
  final String? chapter;
  final DateTime createdAt;

  Question({
    required this.id,
    required this.bankId,
    required this.type,
    required this.stem,
    this.options = const [],
    required this.answer,
    this.explanation,
    this.difficultyScore = 0.0,
    this.importanceScore = 0.0,
    this.theoryScore = 0.0,
    this.featuredScore = 0.0,
    this.chapter,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'type': type.dbValue,
        'stem': stem,
        'options': jsonEncode(options),
        'answer': answer,
        'explanation': explanation,
        'difficulty_score': difficultyScore,
        'importance_score': importanceScore,
        'theory_score': theoryScore,
        'featured_score': featuredScore,
        'chapter': chapter,
        'created_at': createdAt.toIso8601String(),
      };

  factory Question.fromMap(Map<String, dynamic> map) {
    List<String> opts;
    try {
      opts = (jsonDecode(map['options'] as String? ?? '[]') as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {
      opts = [];
    }

    return Question(
      id: map['id'] as String,
      bankId: map['bank_id'] as String,
      type: QuestionType.fromDb(map['type'] as String? ?? 'single_choice'),
      stem: map['stem'] as String? ?? '',
      options: opts,
      answer: map['answer'] as String? ?? '',
      explanation: map['explanation'] as String?,
      difficultyScore:
          (map['difficulty_score'] as num?)?.toDouble() ?? 0.0,
      importanceScore:
          (map['importance_score'] as num?)?.toDouble() ?? 0.0,
      theoryScore: (map['theory_score'] as num?)?.toDouble() ?? 0.0,
      featuredScore:
          (map['featured_score'] as num?)?.toDouble() ?? 0.0,
      chapter: map['chapter'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Question copyWith({
    double? difficultyScore,
    double? importanceScore,
    double? theoryScore,
    double? featuredScore,
  }) =>
      Question(
        id: id,
        bankId: bankId,
        type: type,
        stem: stem,
        options: options,
        answer: answer,
        explanation: explanation,
        difficultyScore: difficultyScore ?? this.difficultyScore,
        importanceScore: importanceScore ?? this.importanceScore,
        theoryScore: theoryScore ?? this.theoryScore,
        featuredScore: featuredScore ?? this.featuredScore,
        chapter: chapter,
        createdAt: createdAt,
      );

  @override
  String toString() => 'Question(id: $id, type: ${type.label}, stem: ${stem.length > 40 ? '${stem.substring(0, 40)}...' : stem})';
}
