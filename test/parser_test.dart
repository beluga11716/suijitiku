// 解析器回归测试：PDF 碎片归一化 + 跨行题干/漏编号题提取
//
// 用例来源：原理课后练习题.pdf 的真实碎片特征（题目内容为合成文本，
// 不含用户题库数据——用户导入文件不入库也不入测试）。
import 'package:flutter_test/flutter_test.dart';

import 'package:randomselector/parser/pdf_parser.dart';
import 'package:randomselector/parser/question_extractor.dart';

void main() {
  group('PdfParser.normalizeFragments', () {
    test('题号碎片：1\\n．\\n题干 → 1．题干', () {
      final t = PdfParser.normalizeFragments('一、单选题\n1\n．\n马克思主义\n2．第二题');
      expect(t, contains('1．马克思主义'));
      expect(t, contains('2．第二题'));
    });

    test('答案括号碎片：字母分行 → （BCD）', () {
      final t = PdfParser.normalizeFragments(
          '题干内容（\nBCD\n）。\nA．甲 B．乙 C．丙 D．丁');
      expect(t, contains('（BCD）。'));
    });

    test('答案括号碎片：同行括号 + 跨行闭合 → （A）', () {
      final t = PdfParser.normalizeFragments('题干（ A\n）\nA．对 B．错');
      expect(t, contains('（A）'));
    });

    test('中文答案括号碎片 → （错）', () {
      final t = PdfParser.normalizeFragments('题干（\n错\n）\nA．对 B．错');
      expect(t, contains('（错）'));
    });

    test('选项标签碎片：A\\n．\\n内容 → A．内容', () {
      final t = PdfParser.normalizeFragments(
          '题干（B）。\nA\n．\n马克思主义政治学 B\n．\n马克思主义政治经济学');
      expect(t, contains('A．马克思主义政治学'));
      expect(t, contains('B．马克思主义政治经济学'));
    });

    test('独立页码行剔除', () {
      final t = PdfParser.normalizeFragments('题干一\n32\n题干二\n7\n．\n题干三');
      expect(t, isNot(contains('\n32\n')));
      expect(t, contains('7．题干三'));
    });
  });

  group('QuestionExtractor 跨行题干', () {
    test('续行含答案括号时不应切分（防误切）', () {
      const text = '二、单选题\n'
          '9．马克思主义在指导中国革命、建设、改革的过程中，形成了一系列'
          '马克思主义中国化理论成果，鲜明地\n'
          '体现了马克思主义（D） 的品格。\n'
          'A．科学性 B．革命性 C．实践性 D．人民性';
      final qs = QuestionExtractor.extract(text);
      expect(qs.length, 1);
      expect(qs.first.answer, 'D');
      expect(qs.first.stem, contains('鲜明地'));
      expect(qs.first.options.length, 4);
      // 答案不泄露：题干中的答案括号替换为空格
      expect(qs.first.stem, isNot(contains('（D）')));
    });

    test('无答案续行合并进题干（判断题跨行）', () {
      const text = '一、判断题\n'
          '6．底线思维，就是“凡事从坏处准备”，牢牢把握\n'
          '主动权。（ A ）\n'
          'A．对 B．错';
      final qs = QuestionExtractor.extract(text);
      expect(qs.length, 1);
      expect(qs.first.answer, 'A');
      expect(qs.first.stem, contains('主动权'));
      expect(qs.first.type.name, 'trueFalse');
    });

    test('漏编号题仍然切分（上一行是完整问题）', () {
      const text = '一、判断题\n'
          '1．题干一。（对）\n'
          '题干二。（错）\n'
          '2．题干三。（对）';
      final qs = QuestionExtractor.extract(text);
      expect(qs.length, 3);
      // 对/错 标准化为 A/B（无选项时补默认 ["正确", "错误"]）
      expect(qs[0].answer, 'A');
      expect(qs[1].answer, 'B');
      expect(qs[2].answer, 'A');
      expect(qs[0].options, ['正确', '错误']);
    });

    test('漏编号选择题仍然切分（上一行是选项行）', () {
      const text = '二、单选题\n'
          '1．题干一。（A）。\n'
          'A．甲 B．乙 C．丙 D．丁\n'
          '题干二（B）。\n'
          'A．甲 B．乙 C．丙 D．丁';
      final qs = QuestionExtractor.extract(text);
      expect(qs.length, 2);
      expect(qs[0].answer, 'A');
      expect(qs[1].answer, 'B');
    });

    test('残题 + 无题号续行 → 合并还原（切分失误兜底）', () {
      const text = '二、单选题\n'
          '9．题干第一行结束。\n'
          '体现了马克思主义（D） 的品格。\n'
          'A．科学性 B．革命性 C．实践性 D．人民性';
      final qs = QuestionExtractor.extract(text);
      expect(qs.length, 1);
      expect(qs.first.answer, 'D');
      expect(qs.first.stem, contains('题干第一行结束'));
      expect(qs.first.stem, contains('品格'));
    });

    test('碎片化题号+选项标签全链路（模拟 PDF 输出）', () {
      const raw = '三、 多项选择题\n'
          '1\n．\n马克思主义理论体系的主要组成部分是（\nBCD\n）。\n'
          'A\n．\n马克思主义政治学 B\n．\n马克思主义政治经济学 '
          'C\n．\n科学社会主义 D\n．\n马克思主义哲学';
      final t = PdfParser.normalizeFragments(raw);
      final qs = QuestionExtractor.extract(t);
      expect(qs.length, 1);
      expect(qs.first.type.name, 'multiChoice');
      expect(qs.first.answer, 'BCD');
      expect(qs.first.options.length, 4);
    });
  });
}
