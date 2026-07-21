import '../models/question.dart';

/// 本地规则引擎：对题目进行三个维度的自动评分
///
/// 评分维度：
/// - difficulty_score: 难度 0~1
/// - importance_score: 重要性 0~1
/// - theory_score: 理论性 0~1
/// - featured_score: 综合精选分 = difficulty*0.4 + importance*0.35 + theory*0.25
class RuleEngine {
  // ==================== 难度关键词 ====================
  static const _difficultyKeywords = [
    '最难', '核心', '关键', '根本', '本质', '复杂',
    '区别', '错误', '不正确', '不属于', '除了',
    '辩证', '对立', '统一', '矛盾',
  ];

  // ==================== 重要性关键词 ====================
  static const _importanceKeywords = [
    '必须掌握', '常考', '重点', '核心', '根本',
    '基本', '基础', '重要', '标志', '实质',
    '首要', '第一次', '首次', '最',
  ];

  // ==================== 理论性关键词 ====================
  static const _theoryKeywords = [
    '概念', '原理', '定义', '理论', '本质',
    '规律', '哲学', '主义', '学说', '观点',
    '唯物', '唯心', '辩证', '范畴',
    '方法论', '世界观', '认识论',
  ];

  /// 对题目列表进行评分，返回更新后的题目列表
  static List<Question> score(List<Question> questions) {
    return questions.map((q) {
      final difficulty = _scoreDimension(q, _difficultyKeywords);
      final importance = _scoreDimension(q, _importanceKeywords);
      final theory = _scoreDimension(q, _theoryKeywords);

      // 额外调整：题干长度越长，难度分越高
      final lengthBonus = (q.stem.length / 200).clamp(0.0, 0.3);
      // 选项越多，难度分越高
      final optionBonus = (q.options.length > 4 ? 0.1 : 0.0);

      final adjustedDifficulty = (difficulty + lengthBonus + optionBonus).clamp(0.0, 1.0);
      final featured = (adjustedDifficulty * 0.4 + importance * 0.35 + theory * 0.25).clamp(0.0, 1.0);

      return q.copyWith(
        difficultyScore: adjustedDifficulty,
        importanceScore: importance.clamp(0.0, 1.0),
        theoryScore: theory.clamp(0.0, 1.0),
        featuredScore: featured,
      );
    }).toList();
  }

  /// 对单个维度评分
  static double _scoreDimension(Question question, List<String> keywords) {
    final text = '${question.stem} ${question.options.join(' ')} ${question.explanation ?? ''}';
    int hits = 0;

    for (final kw in keywords) {
      if (text.contains(kw)) {
        hits++;
      }
    }

    // 归一化到 0~1，最多命中 5 个关键词就算满分
    return (hits / 5.0).clamp(0.0, 1.0);
  }
}
