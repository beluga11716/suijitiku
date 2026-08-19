import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/question.dart';

/// LLM 客户端：调用兼容 OpenAI/Claude 格式的 API
class LlmClient {
  final String apiKey;
  final String baseUrl;
  final String modelName;

  LlmClient({
    required this.apiKey,
    required this.baseUrl,
    required this.modelName,
  });

  /// 默认选题标准（用户唯一可编辑的 Prompt 部分）
  static const defaultCriteria = '''- 涉及核心概念、原理、定义
- 属于常考、易错、重点知识点
- 具有较高的学习价值''';

  /// 把用户编写的选题标准包装成完整 Prompt 模板。
  ///
  /// 分析指令、返回格式等固定部分由本方法生成，用户不可见也不可编辑。
  /// 占位符 {questions_json} 会被替换为题目 JSON 数组。
  static String buildPrompt(String criteria) {
    final c = criteria.trim();
    return '''你是一个题库分析助手。请分析以下题目，判断每道题是否符合以下筛选标准：

标准：
${c.isEmpty ? defaultCriteria : c}

请返回 JSON 格式：
{"selected": [{"id": "题目id", "score": 0.0-1.0, "reason": "一句话理由"}, ...]}

只返回匹配的题目（score > 0），不匹配的不要返回。

题目列表：
{questions_json}''';
  }

  /// 批量分析题目，返回更新后的题目列表
  ///
  /// 每批最多发送 20 道题，避免 token 超限。
  /// [customPrompt] 完整 prompt 模板（用 [buildPrompt] 生成），
  /// 用 {questions_json} 作为题目列表占位符。
  /// [onProgress] 每批次完成回调 (completed, total)。
  /// [isCancelled] 返回 true 时中断分析。
  Future<List<Question>> analyzeQuestions(
    List<Question> questions, {
    String? customPrompt,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    const batchSize = 20;
    final results = <Question>[];
    final totalBatches = (questions.length / batchSize).ceil();

    for (int i = 0; i < questions.length; i += batchSize) {
      if (isCancelled?.call() == true) break;

      final batch = questions.sublist(
          i, (i + batchSize).clamp(0, questions.length));
      final scored = await _analyzeBatch(batch, customPrompt: customPrompt);
      results.addAll(scored);
      onProgress?.call((i ~/ batchSize) + 1, totalBatches);
    }

    return results;
  }

  Future<List<Question>> _analyzeBatch(
    List<Question> batch, {
    String? customPrompt,
  }) async {
    final prompt = _buildPrompt(batch, customPrompt: customPrompt);

    final url = '${_normalizeUrl(baseUrl)}/v1/chat/completions';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': modelName,
          'messages': [
            {
              'role': 'system',
              'content':
                  '你是一个题库分析助手。你需要对给定的题目进行三维评分。只返回 JSON，不要其他内容。'
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content =
            data['choices']?[0]?['message']?['content'] ?? '{}';
        final scores = jsonDecode(content) as Map<String, dynamic>;
        return _applyScores(batch, scores);
      } else {
        throw Exception(
            'API 请求失败: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('LLM 分析失败: $e');
    }
  }

  String _buildPrompt(List<Question> batch, {String? customPrompt}) {
    final questionsJson = batch.map((q) => {
          'id': q.id,
          'type': q.type.label,
          'stem': q.stem,
          'options': q.options,
          'answer': q.answer,
        }).toList();

    final template = customPrompt ?? buildPrompt(defaultCriteria);
    return template.replaceAll('{questions_json}', jsonEncode(questionsJson));
  }

  List<Question> _applyScores(
      List<Question> batch, Map<String, dynamic> scores) {
    // 新格式: {"selected": [{"id": "...", "score": 0.85, "reason": "..."}, ...]}
    final selected = scores['selected'] as List<dynamic>? ?? [];

    // Build lookup: questionId -> {score, reason}
    final scoreMap = <String, Map<String, dynamic>>{};
    for (final item in selected) {
      if (item is Map<String, dynamic>) {
        final id = item['id'] as String?;
        if (id != null) {
          scoreMap[id] = item;
        }
      }
    }

    return batch.map((q) {
      final s = scoreMap[q.id];
      if (s == null) return q; // 未被选中，分数保持 0

      final score = (s['score'] as num?)?.toDouble() ?? 0.0;
      return q.copyWith(
        difficultyScore: score,
        importanceScore: score,
        theoryScore: score,
        featuredScore: score,
      );
    }).toList();
  }

  /// 评估主观题答案（用户答案 vs 参考答案）
  Future<String> evaluateSubjectiveAnswer({
    required String stem,
    required String referenceAnswer,
    required String userAnswer,
  }) async {
    final url = '${_normalizeUrl(baseUrl)}/v1/chat/completions';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': modelName,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个客观公正的阅卷助手。请评估用户答案，给出 0-10 的分数和简短评语。只返回 JSON: {"score": x, "comment": "..."}'
          },
          {
            'role': 'user',
            'content': '题目：$stem\n参考答案：$referenceAnswer\n用户答案：$userAnswer'
          },
        ],
        'temperature': 0.3,
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices']?[0]?['message']?['content'] ?? '{"score":0,"comment":"评分失败"}';
    } else {
      throw Exception('评估失败: ${response.statusCode}');
    }
  }

  String _normalizeUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 从 OpenAI 兼容的 API 获取可用模型列表
  static Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = '$normalized/v1/models';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final models = (data['data'] as List)
          .map((m) => m['id'] as String)
          .toList();
      models.sort();
      return models;
    }
    throw Exception('获取模型列表失败: ${response.statusCode} ${response.body}');
  }
}
