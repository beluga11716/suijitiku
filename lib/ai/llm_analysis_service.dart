import '../database/dao.dart';
import '../database/database_helper.dart';
import 'llm_client.dart';

/// LLM 分析编排服务（stateless，非 Provider）
///
/// 负责：加载题目 → 调用 LLM → 写回分数 → 标记题库已分析
class LlmAnalysisService {
  final Dao _dao = Dao();

  /// LLM精选 最多取前 N 道题
  static const int maxFeaturedQuestions = 120;

  /// 对题库中所有题目执行 LLM 分析
  ///
  /// [bankId] 题库 ID
  /// [client] 已配置的 LlmClient
  /// [prompt] 用户自定义的 prompt 模板
  /// [onProgress] 每批次完成回调 (completedBatch, totalBatches)
  /// [isCancelled] 返回 true 时中断分析
  ///
  /// 返回被 LLM 选中的题目数（featuredScore > 0，上限 [maxFeaturedQuestions]）
  Future<int> analyzeBank({
    required String bankId,
    required LlmClient client,
    required String prompt,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final questions = await _dao.getBankQuestions(bankId);
    if (questions.isEmpty) return 0;

    // 重置所有题目分数为 0
    final reset = questions.map((q) => q.copyWith(
          difficultyScore: 0,
          importanceScore: 0,
          theoryScore: 0,
          featuredScore: 0,
        )).toList();
    await _dao.updateQuestionsScores(reset);

    // 执行 LLM 分析（全量题目）
    final scored = await client.analyzeQuestions(
      reset,
      customPrompt: prompt,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    // 写回 LLM 分数
    await _dao.updateQuestionsScores(scored);

    // 标记题库已分析
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'question_banks',
      {'llm_analyzed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [bankId],
    );

    // 返回被选中的题目数（上限 120）
    final selected = scored.where((q) => q.featuredScore > 0).length;
    return selected > maxFeaturedQuestions ? maxFeaturedQuestions : selected;
  }
}
