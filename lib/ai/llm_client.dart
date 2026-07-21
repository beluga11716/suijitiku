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

  /// 批量分析题目，返回三维评分
  ///
  /// 每批最多发送 20 道题，避免 token 超限。
  Future<List<Question>> analyzeQuestions(List<Question> questions) async {
    const batchSize = 20;
    final results = <Question>[];

    for (int i = 0; i < questions.length; i += batchSize) {
      final batch = questions.sublist(
          i, (i + batchSize).clamp(0, questions.length));
      final scored = await _analyzeBatch(batch);
      results.addAll(scored);
    }

    return results;
  }

  Future<List<Question>> _analyzeBatch(List<Question> batch) async {
    final prompt = _buildPrompt(batch);

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

  String _buildPrompt(List<Question> batch) {
    final questionsJson = batch.map((q) => {
          'id': q.id,
          'type': q.type.label,
          'stem': q.stem,
          'options': q.options,
          'answer': q.answer,
        }).toList();

    return '''
请对以下每道题目进行三维评分（0.0 到 1.0）：

1. difficulty_score（难度）：题目难度，考虑题干复杂程度、选项迷惑性
2. importance_score（重要性）：是否为常考/重点/核心知识点
3. theory_score（理论性）：是否涉及概念、原理、定义等理论知识

评分标准：
- 0.0~0.3: 低
- 0.3~0.6: 中
- 0.6~1.0: 高

返回格式：{"scores": {"题目id": {"difficulty": x, "importance": x, "theory": x}, ...}}

题目列表：
${jsonEncode(questionsJson)}
''';
  }

  List<Question> _applyScores(
      List<Question> batch, Map<String, dynamic> scores) {
    final scoreMap = scores['scores'] as Map<String, dynamic>? ?? {};

    return batch.map((q) {
      final s = scoreMap[q.id] as Map<String, dynamic>?;
      if (s == null) return q;

      final difficulty =
          (s['difficulty'] as num?)?.toDouble() ?? q.difficultyScore;
      final importance =
          (s['importance'] as num?)?.toDouble() ?? q.importanceScore;
      final theory =
          (s['theory'] as num?)?.toDouble() ?? q.theoryScore;
      final featured =
          (difficulty * 0.4 + importance * 0.35 + theory * 0.25)
              .clamp(0.0, 1.0);

      return q.copyWith(
        difficultyScore: difficulty,
        importanceScore: importance,
        theoryScore: theory,
        featuredScore: featured,
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
}
