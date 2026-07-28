import 'dart:convert';

/// PDF 解析器
///
/// 使用 syncfusion_flutter_pdf 提取文本。
/// 如果 syncfusion 不可用，提供降级方案。
class PdfParser {
  /// 从 PDF 字节数组提取纯文本
  ///
  /// 当前使用纯文本降级方案（搜索 PDF 流中的文本）。
  /// TODO: 集成 syncfusion_flutter_pdf 获得更准确的解析。
  static String parseBytes(List<int> bytes) {
    try {
      // 降级方案：搜索 PDF 流中的可打印文本
      // PDF 文本通常在 BT...ET 块中，在 Tj/TJ 操作符里
      // PDF 文本提取：先用 utf-8 解码，失败则回退 latin-1（保留原始字节）
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes);
      }

      // 提取 BT...ET 块中的文本
      final btPattern = RegExp(r'BT(.*?)ET', dotAll: true);
      final texts = <String>[];

      for (final match in btPattern.allMatches(content)) {
        final block = match.group(1)!;
        // 搜索 Tj 操作符: (text) Tj
        final tjPattern = RegExp(r'\((.*?)\)\s*Tj');
        for (final tj in tjPattern.allMatches(block)) {
          texts.add(tj.group(1)!);
        }
      }

      if (texts.isNotEmpty) {
        return texts.join('\n');
      }

      // 如果没找到文本块，尝试提取所有可读文本
      final printable = content.replaceAll(
          RegExp(r'[^\x20-\x7E一-鿿　-〿＀-￯\n]'),
          '');
      return printable;
    } catch (e) {
      throw Exception('解析 PDF 失败: $e');
    }
  }
}
