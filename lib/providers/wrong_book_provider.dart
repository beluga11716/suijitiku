import 'package:flutter/foundation.dart';
import '../database/dao.dart';
import '../models/question.dart';

class WrongBookProvider extends ChangeNotifier {
  final Dao _dao = Dao();

  // ==================== 全局（所有题库汇总） ====================

  List<Question> _wrongQuestions = [];
  List<Question> get wrongQuestions => _wrongQuestions;

  bool _loading = false;
  bool get loading => _loading;

  int get count => _wrongQuestions.length;

  // ==================== 按题库分组 ====================

  List<Map<String, dynamic>> _banksWithWrong = [];
  List<Map<String, dynamic>> get banksWithWrong => _banksWithWrong;

  /// 加载有错题的题库列表
  Future<void> loadBanksWithWrongQuestions() async {
    _loading = true;
    notifyListeners();
    _banksWithWrong = await _dao.getBanksWithWrongQuestions();
    _loading = false;
    notifyListeners();
  }

  /// 加载指定题库的错题
  Future<void> loadWrongQuestionsByBank(String bankId) async {
    _loading = true;
    notifyListeners();
    _wrongQuestions = await _dao.getWrongQuestionsByBank(bankId);
    _loading = false;
    notifyListeners();
  }

  // ==================== 全局操作（兼容旧逻辑） ====================

  Future<void> loadWrongQuestions() async {
    _loading = true;
    notifyListeners();
    _wrongQuestions = await _dao.getWrongQuestions();
    _loading = false;
    notifyListeners();
  }

  Future<void> removeWrongQuestion(String questionId) async {
    await _dao.removeWrongQuestion(questionId);
    _wrongQuestions.removeWhere((q) => q.id == questionId);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _dao.clearWrongQuestions();
    _wrongQuestions = [];
    _banksWithWrong = [];
    notifyListeners();
  }

  /// 清空指定题库的错题
  Future<void> clearByBank(String bankId) async {
    await _dao.clearWrongQuestionsByBank(bankId);
    _wrongQuestions = [];
    _banksWithWrong = [];
    notifyListeners();
  }
}
