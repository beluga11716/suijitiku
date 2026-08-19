import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF 解析器
///
/// 使用 syncfusion_flutter_pdf 提取文本：
/// - 支持 FlateDecode 压缩流 + CID 字体（ToUnicode 映射）——旧 BT/ET
///   降级方案对压缩流完全无效，已移除
/// - 按「视觉行」重组（extractTextLines），题号/选项/段落行保持完整，
///   交给 QuestionExtractor 按题号切分
/// - 解析失败抛异常，由导入流程提示用户
class PdfParser {
  /// 从 PDF 字节数组提取纯文本
  static String parseBytes(List<int> bytes) {
    final doc = PdfDocument(inputBytes: Uint8List.fromList(bytes));
    try {
      final lines = PdfTextExtractor(doc).extractTextLines();
      return normalizeFragments(lines.map((l) => l.text).join('\n'));
    } finally {
      doc.dispose();
    }
  }

  /// 修复 PDF 文本碎片化（extractTextLines 把题号/答案/选项标签拆成独立行）：
  /// 1. "1\n．\n内容" → "1．内容"（题号与标点分离）
  /// 2. "（\nBCD\n）。" → "（BCD）。"（答案括号分离）
  /// 3. "A\n．\n内容" → "A．内容"（选项标签分离）
  /// 4. 剔除独立数字行（页眉/页脚页码）
  static String normalizeFragments(String text) {
    var t = text;

    // 1. 题号碎片
    t = t.replaceAllMapped(
      RegExp(r'\n\s*(\d{1,3})\s*\n\s*([．、.])\s*\n'),
      (m) => '\n${m.group(1)}${m.group(2)}',
    );

    // 2. 答案括号碎片："（\nBCD\n）。" / "（ A\n）" / "（\nA）" → "（BCD）。" / "（A）"
    //    统一规则兼容括号与答案在同一行或分行的各种组合
    t = t.replaceAllMapped(
      RegExp(r'[（(]\s*\n?\s*([A-Ea-e]{1,3})\s*\n?\s*[）)]'),
      (m) => '（${m.group(1)!}）',
    );
    t = t.replaceAllMapped(
      RegExp(r'[（(]\s*\n?\s*(对|错|正确|错误|√|×|✓|✗)\s*\n?\s*[）)]'),
      (m) => '（${m.group(1)!}）',
    );

    // 3. 选项标签碎片
    t = t.replaceAllMapped(
      RegExp(r'(?<![0-9A-Za-z])([A-E])\s*\n\s*([．、.])\s*\n'),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // 4. 独立数字行（页码）
    t = t.replaceAll(RegExp(r'^\s*\d{1,3}\s*$', multiLine: true), '');

    return t;
  }
}
