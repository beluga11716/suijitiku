import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// .docx 解析器：将 .docx 文件转换为纯文本
///
/// .docx 本质是 ZIP 压缩包，内部 word/document.xml 包含内容。
/// 每段文字在 <w:p> 标签内，文本在 <w:t> 标签内。
class DocxParser {
  /// 从字节数组解析 .docx，返回纯文本
  static String parseBytes(List<int> bytes) {
    try {
      // 确保输入是 Uint8List：archive 3.x 在 Android 上对 List<int> 可能有类型问题
      final input = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final archive = ZipDecoder().decodeBytes(input);
      final documentXml = archive.findFile('word/document.xml');
      if (documentXml == null) {
        throw Exception('无效的 .docx 文件：找不到 word/document.xml');
      }

      // content getter 返回 dynamic (实际为 Uint8List)，用 Uint8List.fromList 确保类型一致
      final contentBytes = Uint8List.fromList(documentXml.content);
      final xmlContent = utf8.decode(contentBytes);

      // 简单正则提取所有 <w:t> 标签内的文本
      // 同时处理 <w:p> 段落边界（插入换行）
      final paragraphs = <String>[];
      final pTagPattern = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);

      for (final match in pTagPattern.allMatches(xmlContent)) {
        final pContent = match.group(0)!;
        final texts = <String>[];
        final tTagPattern = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);

        for (final t in tTagPattern.allMatches(pContent)) {
          final text = t.group(1) ?? '';
          texts.add(text);
        }

        if (texts.isNotEmpty) {
          paragraphs.add(texts.join());
        }
      }

      return paragraphs.join('\n');
    } catch (e) {
      throw Exception('解析 .docx 失败: $e');
    }
  }
}
