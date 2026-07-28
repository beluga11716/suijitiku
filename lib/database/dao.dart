import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/question_bank.dart';
import '../models/question.dart';
import '../models/quiz_session.dart';
import '../models/quiz_answer.dart';

class Dao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ==================== 题库 ====================

  Future<int> insertBank(QuestionBank bank) async {
    final db = await _dbHelper.database;
    return db.insert('question_banks', bank.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<QuestionBank>> getAllBanks() async {
    final db = await _dbHelper.database;
    final maps = await db.query('question_banks',
        orderBy: 'created_at DESC');
    return maps.map((m) => QuestionBank.fromMap(m)).toList();
  }

  Future<QuestionBank?> getBank(String id) async {
    final db = await _dbHelper.database;
    final maps =
        await db.query('question_banks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return QuestionBank.fromMap(maps.first);
  }

  Future<int> updateBank(QuestionBank bank) async {
    final db = await _dbHelper.database;
    return db.update('question_banks', bank.toMap(),
        where: 'id = ?', whereArgs: [bank.id]);
  }

  Future<int> deleteBank(String id) async {
    final db = await _dbHelper.database;
    return db.delete('question_banks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllBanks() async {
    final db = await _dbHelper.database;
    await db.delete('question_banks');
  }

  // ==================== 题目 ====================

  Future<void> insertQuestions(List<Question> questions) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('questions', q.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Question>> getBankQuestions(String bankId) async {
    final db = await _dbHelper.database;
    final maps = await db
        .query('questions', where: 'bank_id = ?', whereArgs: [bankId]);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  Future<int> getBankQuestionCount(String bankId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM questions WHERE bank_id = ?',
        [bankId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> updateQuestion(Question q) async {
    final db = await _dbHelper.database;
    return db.update('questions', q.toMap(),
        where: 'id = ?', whereArgs: [q.id]);
  }

  Future<void> updateQuestionsScores(
      List<Question> questions) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final q in questions) {
      batch.update('questions',
          {'difficulty_score': q.difficultyScore,
           'importance_score': q.importanceScore,
           'theory_score': q.theoryScore,
           'featured_score': q.featuredScore},
          where: 'id = ?', whereArgs: [q.id]);
    }
    await batch.commit(noResult: true);
  }

  // ==================== 刷题会话 ====================

  Future<void> insertSession(QuizSession session) async {
    final db = await _dbHelper.database;
    await db.insert('quiz_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSession(QuizSession session) async {
    final db = await _dbHelper.database;
    await db.update('quiz_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<QuizSession?> getSession(String id) async {
    final db = await _dbHelper.database;
    final maps = await db
        .query('quiz_sessions', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return QuizSession.fromMap(maps.first);
  }

  Future<List<QuizSession>> getAllSessions() async {
    final db = await _dbHelper.database;
    final maps = await db.query('quiz_sessions',
        orderBy: 'started_at DESC');
    return maps.map((m) => QuizSession.fromMap(m)).toList();
  }

  /// 获取某题库的测试列表（含错题测试）
  Future<List<QuizSession>> getSessionsByBank(String bankId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('quiz_sessions',
        where: 'bank_id = ?',
        whereArgs: [bankId],
        orderBy: 'started_at DESC');
    return maps.map((m) => QuizSession.fromMap(m)).toList();
  }

  /// 按 source 获取测试列表
  Future<List<QuizSession>> getSessionsBySource(String source) async {
    final db = await _dbHelper.database;
    final maps = await db.query('quiz_sessions',
        where: 'source = ?',
        whereArgs: [source],
        orderBy: 'started_at DESC');
    return maps.map((m) => QuizSession.fromMap(m)).toList();
  }

  /// 删除测试及其答题记录
  Future<void> deleteSession(String id) async {
    final db = await _dbHelper.database;
    await db.delete('quiz_answers', where: 'session_id = ?', whereArgs: [id]);
    await db.delete('quiz_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllRecords() async {
    final db = await _dbHelper.database;
    await db.delete('quiz_answers');
    await db.delete('quiz_sessions');
    await db.delete('wrong_questions');
  }

  Future<void> clearWrongQuestions() async {
    final db = await _dbHelper.database;
    await db.delete('wrong_questions');
  }

  // ==================== 答题记录 ====================

  Future<void> insertAnswer(QuizAnswer answer) async {
    final db = await _dbHelper.database;
    await db.insert('quiz_answers', answer.toMap());
  }

  Future<List<QuizAnswer>> getSessionAnswers(String sessionId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('quiz_answers',
        where: 'session_id = ?', whereArgs: [sessionId],
        orderBy: 'answered_at ASC');
    return maps.map((m) => QuizAnswer.fromMap(m)).toList();
  }

  // ==================== 错题本 ====================

  /// 获取有错题的题库列表（含错题数）
  Future<List<Map<String, dynamic>>> getBanksWithWrongQuestions() async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT
        qb.id AS bank_id,
        qb.name AS bank_name,
        qb.question_count AS total_count,
        COUNT(wq.id) AS wrong_count
      FROM wrong_questions wq
      JOIN questions q ON wq.question_id = q.id
      JOIN question_banks qb ON q.bank_id = qb.id
      GROUP BY qb.id
      ORDER BY MAX(wq.last_wrong_at) DESC
    ''');
  }

  /// 获取指定题库的错题列表
  Future<List<Question>> getWrongQuestionsByBank(String bankId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT q.* FROM questions q
      JOIN wrong_questions wq ON wq.question_id = q.id
      WHERE q.bank_id = ?
      ORDER BY wq.last_wrong_at DESC
    ''', [bankId]);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  /// 获取指定题库的错题数
  Future<int> getWrongQuestionCountByBank(String bankId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM wrong_questions wq
      JOIN questions q ON wq.question_id = q.id
      WHERE q.bank_id = ?
    ''', [bankId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 清空指定题库的错题
  Future<void> clearWrongQuestionsByBank(String bankId) async {
    final db = await _dbHelper.database;
    await db.rawDelete('''
      DELETE FROM wrong_questions WHERE question_id IN (
        SELECT id FROM questions WHERE bank_id = ?
      )
    ''', [bankId]);
  }

  Future<void> addWrongQuestion(String questionId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    // 检查是否已存在
    final existing = await db.query('wrong_questions',
        where: 'question_id = ?', whereArgs: [questionId]);
    if (existing.isEmpty) {
      await db.insert('wrong_questions', {
        'id': 'w_$questionId',
        'question_id': questionId,
        'wrong_count': 1,
        'last_wrong_at': now,
        'created_at': now,
      });
    } else {
      await db.update('wrong_questions',
          {'wrong_count': (existing.first['wrong_count'] as int) + 1,
           'last_wrong_at': now},
          where: 'question_id = ?', whereArgs: [questionId]);
    }
  }

  Future<void> removeWrongQuestion(String questionId) async {
    final db = await _dbHelper.database;
    await db.delete('wrong_questions',
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  /// 获取某道题用户最后一次的错误答案
  Future<String?> getLastWrongAnswer(String questionId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('quiz_answers',
        where: 'question_id = ? AND is_correct = 0',
        whereArgs: [questionId],
        orderBy: 'answered_at DESC',
        limit: 1);
    if (maps.isEmpty) return null;
    return maps.first['user_answer'] as String?;
  }

  Future<List<String>> getWrongQuestionIds() async {
    final db = await _dbHelper.database;
    final maps =
        await db.query('wrong_questions', orderBy: 'last_wrong_at DESC');
    return maps
        .map((m) => m['question_id'] as String)
        .toList();
  }

  Future<int> getWrongQuestionCount() async {
    final db = await _dbHelper.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM wrong_questions');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Question>> getWrongQuestions() async {
    final ids = await getWrongQuestionIds();
    if (ids.isEmpty) return [];
    final db = await _dbHelper.database;
    final placeholders = ids.map((_) => '?').join(',');
    final maps = await db.query('questions',
        where: 'id IN ($placeholders)', whereArgs: ids);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  // 根据 question_id 获取完整题目
  Future<Question?> getQuestionById(String questionId) async {
    final db = await _dbHelper.database;
    final maps = await db
        .query('questions', where: 'id = ?', whereArgs: [questionId]);
    if (maps.isEmpty) return null;
    return Question.fromMap(maps.first);
  }

  // ==================== 统计 ====================

  Future<int> getTotalQuestionCount() async {
    final db = await _dbHelper.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM questions');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalBankCount() async {
    final db = await _dbHelper.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM question_banks');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalQuizCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM quiz_sessions WHERE status = ?',
        ['completed']);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> getOverallAccuracy() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
        'SELECT SUM(correct_count) as correct, SUM(question_count) as total FROM quiz_sessions WHERE status = ?',
        ['completed']);
    if (result.isEmpty) return 0.0;
    final correct = (result.first['correct'] as int?) ?? 0;
    final total = (result.first['total'] as int?) ?? 0;
    if (total == 0) return 0.0;
    return correct / total;
  }

  // ==================== 设置 ====================

  Future<String?> getSetting(String key) async {
    final db = await _dbHelper.database;
    final maps =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
