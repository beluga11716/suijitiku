class QuestionBank {
  final String id;
  final String name;
  final String? sourceFile;
  final String? sourceType;
  final int questionCount;
  final DateTime createdAt;

  QuestionBank({
    required this.id,
    required this.name,
    this.sourceFile,
    this.sourceType,
    this.questionCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'source_file': sourceFile,
        'source_type': sourceType,
        'question_count': questionCount,
        'created_at': createdAt.toIso8601String(),
      };

  factory QuestionBank.fromMap(Map<String, dynamic> map) => QuestionBank(
        id: map['id'] as String,
        name: map['name'] as String,
        sourceFile: map['source_file'] as String?,
        sourceType: map['source_type'] as String?,
        questionCount: (map['question_count'] as int?) ?? 0,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  QuestionBank copyWith({
    String? id,
    String? name,
    String? sourceFile,
    String? sourceType,
    int? questionCount,
    DateTime? createdAt,
  }) =>
      QuestionBank(
        id: id ?? this.id,
        name: name ?? this.name,
        sourceFile: sourceFile ?? this.sourceFile,
        sourceType: sourceType ?? this.sourceType,
        questionCount: questionCount ?? this.questionCount,
        createdAt: createdAt ?? this.createdAt,
      );
}
