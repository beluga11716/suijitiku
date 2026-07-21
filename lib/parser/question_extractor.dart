import '../models/question.dart';

/// 将纯文本解析为结构化题目列表
///
/// 支持的格式（按优先级尝试）：
/// 1. 按章节分割（"第X章" 或 "导论"）
/// 2. 按题型分割（"一、判断题" / "二、单选题" / "三、多选题"）
/// 3. 按题号提取每道题
/// 4. 识别内嵌答案：题干末尾 "(A)" 或 "(BCD)"
/// 5. 识别选项：A．/ B．/ A. / B.
/// 6. 题型推断
class QuestionExtractor {
  /// 从纯文本中提取题目列表
  static List<ParsedQuestion> extract(String text) {
    final questions = <ParsedQuestion>[];

    // 去掉 BOM 和其他不可见字符
    final cleaned = text
        .replaceAll('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();

    // Step 1: 按章节分割
    final chapterPattern =
        RegExp(r'(第[一二三四五六七八九十\d]+章[^\n]*|导\s*论)');
    final chapters = _splitByPattern(cleaned, chapterPattern);

    for (final chapterPair in chapters) {
      final chapterName =
          chapterPair.key.isEmpty ? null : chapterPair.key.trim();
      final chapterText = chapterPair.value;

      // Step 2: 按题型分割
      final typePattern = RegExp(r'([一二三四五]、\s*(判断|单选|多选|填空|简答)[题]?)');
      final typeBlocks = _splitByPattern(chapterText, typePattern);

      QuestionType? currentType;

      for (final typePair in typeBlocks) {
        if (typePair.key.isNotEmpty) {
          currentType = _parseTypeHeader(typePair.key);
        }
        if (currentType == null) continue;

        // Step 3: 按题号提取每道题
        final questionsInBlock =
            _extractQuestions(typePair.value, currentType, chapterName);
        questions.addAll(questionsInBlock);
      }

      // 如果题型分割失败，尝试直接提取题目
      if (typeBlocks.length <= 1 && chapters.length == 1) {
        // 整个文本作为一个块处理
        final directQuestions = _extractQuestions(
            cleaned, QuestionType.singleChoice, null);
        if (directQuestions.length > 3) {
          return directQuestions;
        }
      }
    }

    return questions;
  }

  /// 按正则模式分割文本，返回 (匹配文本, 内容) 对列表
  static List<MapEntry<String, String>> _splitByPattern(
      String text, RegExp pattern) {
    final result = <MapEntry<String, String>>[];
    final matches = pattern.allMatches(text).toList();

    if (matches.isEmpty) {
      result.add(MapEntry('', text));
      return result;
    }

    // 第一个匹配之前的内容
    if (matches.first.start > 0) {
      result.add(MapEntry('', text.substring(0, matches.first.start)));
    }

    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i < matches.length - 1
          ? matches[i + 1].start
          : text.length;
      final key = matches[i].group(0)!;
      final value = text.substring(start, end);
      result.add(MapEntry(key, value));
    }

    return result;
  }

  /// 解析题型标题
  static QuestionType? _parseTypeHeader(String header) {
    if (header.contains('判断')) return QuestionType.trueFalse;
    if (header.contains('单选')) return QuestionType.singleChoice;
    if (header.contains('多选')) return QuestionType.multiChoice;
    if (header.contains('填空')) return QuestionType.fillBlank;
    if (header.contains('简答')) return QuestionType.shortAnswer;
    return null;
  }

  /// 从文本块中提取每道题
  static List<ParsedQuestion> _extractQuestions(
      String block, QuestionType type, String? chapter) {
    final questions = <ParsedQuestion>[];

    // 匹配题号：数字．/ 数字. / 数字、/ 数字．
    final questionPattern = RegExp(
        r'(?:^|\n)\s*(\d{1,3})\s*[．、.](?!\s*[A-Za-zＡ-Ｚａ-ｚ．、])',
        multiLine: true);

    final matches = questionPattern.allMatches(block).toList();

    if (matches.isEmpty) return questions;

    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i < matches.length - 1 ? matches[i + 1].start : block.length;
      final questionText = block.substring(start, end).trim();

      final parsed = _parseSingleQuestion(questionText, type, chapter);
      if (parsed != null) {
        questions.add(parsed);
      }
    }

    return questions;
  }

  /// 解析单道题
  static ParsedQuestion? _parseSingleQuestion(
      String text, QuestionType defaultType, String? chapter) {
    // 去掉开头的换行
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;

    // 分离题干（第一行）和选项/答案（后续行）
    final lines = cleaned.split('\n');

    // 第一行包含题号和题干
    final firstLine = lines.isNotEmpty ? lines.first : '';
    final remainingText = lines.length > 1
        ? lines.sublist(1).join('\n')
        : '';

    // 提取内嵌答案：题干末尾的 (A) 或 (BCD) 等
    final answerPattern = RegExp(r'[（(]\s*([A-Za-z]+)\s*[）)]\s*[。.]?\s*$');
    final answerMatch = answerPattern.firstMatch(firstLine);

    String? extractedAnswer;
    String stem = firstLine;

    if (answerMatch != null) {
      extractedAnswer = answerMatch.group(1)!.toUpperCase();
      // 去掉答案部分
      stem = firstLine.substring(0, answerMatch.start).trim();
    }

    // 去掉题号前缀
    stem = stem.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[．、.]\s*'), '').trim();

    // 解析选项
    List<String> options;
    if (remainingText.isNotEmpty) {
      options = _extractOptions(remainingText);
    } else {
      // 选项可能在同一行（空格分隔）
      options = _extractOptions(firstLine);
    }

    // 如果选项提取失败，尝试在 remainingText 中找答案
    if (extractedAnswer == null && remainingText.isNotEmpty) {
      final answerInRemaining =
          answerPattern.firstMatch(remainingText);
      if (answerInRemaining != null) {
        extractedAnswer = answerInRemaining.group(1)!.toUpperCase();
      }
    }

    // 推断题型
    QuestionType type = defaultType;
    if (options.length == 2 && extractedAnswer != null) {
      type = QuestionType.trueFalse;
    } else if (options.length >= 3) {
      // 根据答案长度判断：多选题答案多为多个字母
      if (extractedAnswer != null && extractedAnswer.length > 1) {
        type = QuestionType.multiChoice;
      } else {
        type = QuestionType.singleChoice;
      }
    }

    // 如果没有选项但有答案，可能是填空题或简答题
    if (options.isEmpty &&
        extractedAnswer != null &&
        extractedAnswer.length > 1) {
      type = defaultType == QuestionType.fillBlank
          ? QuestionType.fillBlank
          : QuestionType.shortAnswer;
    }

    return ParsedQuestion(
      type: type,
      stem: stem,
      options: options,
      answer: extractedAnswer ?? '',
      chapter: chapter,
    );
  }

  /// 提取选项列表
  ///
  /// 支持格式：
  /// A．xxx（换行）B．yyy（换行）...
  /// A．xxx     B．yyy     C．zzz     D．www  （空格分隔，同行）
  static List<String> _extractOptions(String text) {
    // 匹配选项起始标记 A．/ A. / A、 等，按标记位置切分
    final optionPattern = RegExp(r'[A-E]\s*[．、.]');
    final matches = optionPattern.allMatches(text).toList();

    if (matches.length < 2) return [];

    final options = <String>[];
    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i < matches.length - 1 ? matches[i + 1].start : text.length;
      final option = text.substring(start, end).trim();
      if (option.isNotEmpty) options.add(option);
    }

    return options;
  }
}

/// 解析中间结果——还未分配 ID 的题目
class ParsedQuestion {
  final QuestionType type;
  final String stem;
  final List<String> options;
  final String answer;
  final String? chapter;

  ParsedQuestion({
    required this.type,
    required this.stem,
    required this.options,
    required this.answer,
    this.chapter,
  });

  /// 转换为完整的 Question 对象（导入时使用）
  Question toQuestion({required String id, required String bankId}) {
    return Question(
      id: id,
      bankId: bankId,
      type: type,
      stem: stem,
      options: options,
      answer: answer,
      chapter: chapter,
    );
  }

  @override
  String toString() =>
      'ParsedQuestion(type: ${type.label}, stem: $stem, answer: $answer, options: ${options.length})';
}
