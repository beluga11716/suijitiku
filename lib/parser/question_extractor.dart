import '../models/question.dart';

/// 将纯文本解析为结构化题目列表
///
/// 支持的格式（按优先级尝试）：
/// 1. 标题级题型检测（"马克思主义原理判断题" → trueFalse，"思考题" → shortAnswer）
/// 2. 按章节分割（"第X章" 或 "导论"）
/// 3. 按题型分割（"一、判断题" / "二、单选题" / "三、多选题"）
/// 4. 按题号提取每道题（支持同行无换行紧凑格式）
/// 5. 识别内嵌答案：题干末尾 "(A)" 或 "(BCD)" 或 "（对）"/"（错）"
/// 6. 识别选项：A．/ B．/ A. / B.
/// 7. 识别主观题答案标记：解析：/ 参考答案：
/// 8. 题型推断
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

    if (cleaned.isEmpty) return questions;

    // Step 0: 从标题推断全局题型
    final globalType = _detectTypeFromTitle(cleaned);

    // Step 1: 按章节分割
    final chapterPattern =
        RegExp(r'(第[一二三四五六七八九十\d]+章[^\n]*|导\s*论)');
    final chapters = _splitByPattern(cleaned, chapterPattern);

    for (final chapterPair in chapters) {
      final chapterName =
          chapterPair.key.isEmpty ? null : chapterPair.key.trim();
      final chapterText = chapterPair.value;

      // 从章节文本中也可能检测题型
      final chapterType = _detectTypeFromTitle(chapterText);

      // Step 2: 按题型分割
      final typePattern =
          RegExp(r'([一二三四五]、\s*(判断|单选|多选|填空|简答|问答|主观|思考)[题]?)');
      final typeBlocks = _splitByPattern(chapterText, typePattern);

      QuestionType? currentType;

      for (final typePair in typeBlocks) {
        if (typePair.key.isNotEmpty) {
          currentType = _parseTypeHeader(typePair.key);
        }
        // 优先用标题推断的题型，其次用 section header 推断的题型，最后用全局题型
        final effectiveType =
            chapterType ?? currentType ?? globalType ?? QuestionType.singleChoice;

        // Step 3: 按题号提取每道题
        final questionsInBlock =
            _extractQuestions(typePair.value, effectiveType, chapterName);
        questions.addAll(questionsInBlock);
      }

      // 如果题型分割后没有提取到题目（或只有一段），尝试直接提取
      if (questions.isEmpty ||
          (typeBlocks.length <= 1 && chapters.length == 1)) {
        final directType =
            globalType ?? QuestionType.singleChoice;
        final directQuestions =
            _extractQuestions(cleaned, directType, null);
        if (directQuestions.isNotEmpty) {
          return directQuestions;
        }
      }
    }

    return questions;
  }

  /// 从文本标题中检测题型
  ///
  /// 匹配模式：
  /// - "XXX判断题" / "XXX判断题 XXX" → trueFalse
  /// - "XXX思考题" / "XXX问答题" / "XXX简答题" → shortAnswer
  /// - "XXX单选题" / "XXX选择题" → singleChoice（单选优先）
  /// - "XXX多选题" → multiChoice
  /// - "XXX填空题" → fillBlank
  static QuestionType? _detectTypeFromTitle(String text) {
    // 只看前 200 个字符（标题区域）
    final header = text.length > 200 ? text.substring(0, 200) : text;

    // 判断题（优先级最高，因为"判断题"比较独特）
    if (header.contains('判断题')) {
      return QuestionType.trueFalse;
    }
    // 思考题 / 问答题 / 简答题 → 主观题
    if (header.contains('思考题') ||
        header.contains('问答题') ||
        header.contains('简答题')) {
      return QuestionType.shortAnswer;
    }
    // 多选题（必须在单选题之前检测，因为"多选题"包含"选题"）
    if (header.contains('多选题')) {
      return QuestionType.multiChoice;
    }
    // 填空题
    if (header.contains('填空题')) {
      return QuestionType.fillBlank;
    }
    // 单选题 / 选择题
    if (header.contains('单选题') || header.contains('选择题')) {
      return QuestionType.singleChoice;
    }
    return null;
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
      final end =
          i < matches.length - 1 ? matches[i + 1].start : text.length;
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
    if (header.contains('简答') ||
        header.contains('问答') ||
        header.contains('思考') ||
        header.contains('主观')) {
      return QuestionType.shortAnswer;
    }
    return null;
  }

  /// 从文本块中提取每道题
  ///
  /// 支持两种格式：
  /// 1. 每题一行（常规格式）：题号后换行
  /// 2. 紧凑格式（判断题常见）：所有题在同一行，如 "1. xxx（对）2. yyy（错）3. zzz（对）"
  static List<ParsedQuestion> _extractQuestions(
      String block, QuestionType type, String? chapter) {
    // 先尝试紧凑格式（判断题常见）
    if (type == QuestionType.trueFalse) {
      final compact = _extractCompactTrueFalse(block, chapter);
      if (compact.isNotEmpty) return compact;
    }

    final questions = <ParsedQuestion>[];

    // 匹配题号：数字．/ 数字. / 数字、/ 数字．
    // 支持题号前无换行（紧凑格式）和题号前有换行（常规格式）
    // 前缀：字符串开头 / 换行 / 非字母数字字符后（中文、括号等都行）
    final questionPattern = RegExp(
        r'(?<![0-9A-Za-z])\s*(\d{1,3})\s*[．、.]\s*',
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

  /// 提取紧凑格式的判断题（所有题在同一行/段落）
  ///
  /// 格式: "1. 题干（对）2. 题干（错）3. 题干（对）"
  static List<ParsedQuestion> _extractCompactTrueFalse(
      String block, String? chapter) {
    // 先规范化：在 "）数字." 或 ")数字." 前插入换行
    // 匹配 "（对）1." 或 "（错）2." 或 ")1." 这种模式
    final normalized = block.replaceAllMapped(
      RegExp(r'([）)])\s*(\d{1,3}\s*[．、.])'),
      (m) => '${m.group(1)}\n${m.group(2)}',
    );

    // 如果规范化后与原始相同（没有紧凑格式的特征），返回空
    if (normalized == block) return [];

    final questions = <ParsedQuestion>[];
    final questionPattern = RegExp(
        r'(?<![0-9A-Za-z])\s*(\d{1,3})\s*[．、.]\s*', multiLine: true);
    final matches = questionPattern.allMatches(normalized).toList();

    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i < matches.length - 1 ? matches[i + 1].start : normalized.length;
      final questionText = normalized.substring(start, end).trim();

      final parsed =
          _parseSingleQuestion(questionText, QuestionType.trueFalse, chapter);
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
    final remainingText =
        lines.length > 1 ? lines.sublist(1).join('\n') : '';

    // 提取内嵌答案：
    // 1. 字母答案：题干末尾的 (A) 或 (BCD) 等
    // 2. 中文判断题答案：题干末尾的（对）/（错）/(对)/(错)
    final letterAnswerPattern =
        RegExp(r'[（(]\s*([A-Za-z]+)\s*[）)]\s*[。.]?\s*$');
    final chineseAnswerPattern = RegExp(r'[（(]\s*(对|错|正确|错误|√|×|✓|✗)\s*[）)]');

    String? extractedAnswer;
    String stem = firstLine;

    // 先检查中文判断题答案
    final chineseMatch = chineseAnswerPattern.firstMatch(firstLine);
    if (chineseMatch != null) {
      final raw = chineseMatch.group(1)!;
      // 标准化为 对/错
      if (raw == '对' || raw == '正确' || raw == '√' || raw == '✓') {
        extractedAnswer = '对';
      } else {
        extractedAnswer = '错';
      }
      stem = firstLine.substring(0, chineseMatch.start).trim();
    } else {
      // 再检查字母答案
      final letterMatch = letterAnswerPattern.firstMatch(firstLine);
      if (letterMatch != null) {
        extractedAnswer = letterMatch.group(1)!.toUpperCase();
        stem = firstLine.substring(0, letterMatch.start).trim();
      }
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
      // 先尝试中文答案
      final chineseInRemaining =
          chineseAnswerPattern.firstMatch(remainingText);
      if (chineseInRemaining != null) {
        final raw = chineseInRemaining.group(1)!;
        extractedAnswer =
            (raw == '对' || raw == '正确' || raw == '√' || raw == '✓')
                ? '对'
                : '错';
      } else {
        // 再尝试字母答案
        final letterInRemaining =
            letterAnswerPattern.firstMatch(remainingText);
        if (letterInRemaining != null) {
          extractedAnswer = letterInRemaining.group(1)!.toUpperCase();
        }
      }
    }

    // 提取解析/参考答案（主观题）
    String? explanation;
    if (remainingText.isNotEmpty &&
        (defaultType == QuestionType.shortAnswer ||
            defaultType == QuestionType.fillBlank)) {
      final answerPair =
          _extractSubjectiveAnswer(remainingText, cleaned);
      if (answerPair != null) {
        extractedAnswer = answerPair.key;
        explanation = answerPair.value;
      }
    }

    // 推断题型
    QuestionType type = defaultType;

    // 判断题特征：2个选项 + 对/错答案，或者中文对错答案
    if (extractedAnswer != null &&
        (extractedAnswer == '对' || extractedAnswer == '错')) {
      type = QuestionType.trueFalse;
    } else if (options.length == 2 && extractedAnswer != null) {
      type = QuestionType.trueFalse;
    } else if (options.length >= 3) {
      // 根据答案长度判断：多选题答案多为多个字母
      if (extractedAnswer != null && extractedAnswer.length > 1) {
        type = QuestionType.multiChoice;
      } else {
        type = QuestionType.singleChoice;
      }
    }

    // 如果没有选项但有答案，可能是填空题或主观题
    if (options.isEmpty && extractedAnswer != null) {
      if (defaultType == QuestionType.fillBlank) {
        type = QuestionType.fillBlank;
      } else if (extractedAnswer.length > 10) {
        // 答案较长 → 主观题
        type = QuestionType.shortAnswer;
      } else if (extractedAnswer == '对' || extractedAnswer == '错') {
        type = QuestionType.trueFalse;
      }
    }
    // 没有选项也没有提取到答案 → 保持默认题型（标题推断的结果）

    return ParsedQuestion(
      type: type,
      stem: stem,
      options: options,
      answer: extractedAnswer ?? '',
      explanation: explanation,
      chapter: chapter,
    );
  }

  /// 提取主观题答案（解析/参考答案标记）
  ///
  /// 支持格式：
  /// - "解析：xxx" / "解析: xxx"
  /// - "参考答案：xxx" / "参考答案: xxx"
  /// - "答案：xxx"
  /// 返回 (answer, explanation) 或 null
  static MapEntry<String, String>? _extractSubjectiveAnswer(
      String remainingText, String fullText) {
    // 要搜索的文本：先搜 remainingText，再搜 fullText
    final searchTexts = [remainingText, fullText];

    for (final text in searchTexts) {
      // 匹配 "解析：..." 或 "参考答案：..." 等
      final patterns = [
        RegExp(r'解析\s*[：:]\s*(.+?)(?=\n\d{1,3}\s*[．、.]|\n*(?:解析|参考|答案)|$)',
            dotAll: true),
        RegExp(r'参考答案\s*[：:]\s*(.+?)(?=\n\d{1,3}\s*[．、.]|\n*(?:解析|参考|答案)|$)',
            dotAll: true),
        RegExp(r'答案\s*[：:]\s*(.+?)(?=\n\d{1,3}\s*[．、.]|\n*(?:解析|参考|答案)|$)',
            dotAll: true),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          final answer = match.group(1)!.trim();
          if (answer.isNotEmpty) {
            return MapEntry(answer, answer);
          }
        }
      }
    }
    return null;
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
      final end =
          i < matches.length - 1 ? matches[i + 1].start : text.length;
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
  final String? explanation;
  final String? chapter;

  ParsedQuestion({
    required this.type,
    required this.stem,
    required this.options,
    required this.answer,
    this.explanation,
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
      explanation: explanation,
      chapter: chapter,
    );
  }

  @override
  String toString() =>
      'ParsedQuestion(type: ${type.label}, stem: $stem, answer: $answer, options: ${options.length})';
}
