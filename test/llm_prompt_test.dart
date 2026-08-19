// LLM Prompt 包装模板测试：用户只编辑选题标准，固定部分由 buildPrompt 生成
import 'package:flutter_test/flutter_test.dart';

import 'package:randomselector/ai/llm_client.dart';

void main() {
  group('LlmClient.buildPrompt', () {
    test('用户标准嵌入固定模板', () {
      final p = LlmClient.buildPrompt('选出最简单的题目');
      expect(p, contains('选出最简单的题目'));
      expect(p, contains('你是一个题库分析助手'));
      expect(p, contains('请返回 JSON 格式'));
      expect(p, contains('{questions_json}'));
    });

    test('空标准回退默认标准', () {
      final p = LlmClient.buildPrompt('  ');
      expect(p, contains(LlmClient.defaultCriteria));
      expect(p, contains('{questions_json}'));
    });

    test('默认标准包装可用', () {
      final p = LlmClient.buildPrompt(LlmClient.defaultCriteria);
      expect(p, contains('涉及核心概念'));
      expect(p, contains('{questions_json}'));
    });
  });
}
