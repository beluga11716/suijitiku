import 'package:flutter/foundation.dart';
import '../database/dao.dart';
import '../models/question_bank.dart';
import '../models/question.dart';

class BankProvider extends ChangeNotifier {
  final Dao _dao = Dao();

  List<QuestionBank> _banks = [];
  List<QuestionBank> get banks => _banks;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> loadBanks() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _banks = await _dao.getAllBanks();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> importBank({
    required String name,
    required String? sourceFile,
    required String? sourceType,
    required List<Question> questions,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final bank = QuestionBank(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        sourceFile: sourceFile,
        sourceType: sourceType,
        questionCount: questions.length,
      );

      // 设置 bank_id 并分配 ID
      final now = DateTime.now().millisecondsSinceEpoch;
      final qs = questions.asMap().entries.map((entry) => Question(
            id: '${now}_${entry.key}',
            bankId: bank.id,
            type: entry.value.type,
            stem: entry.value.stem,
            options: entry.value.options,
            answer: entry.value.answer,
            explanation: entry.value.explanation,
            difficultyScore: entry.value.difficultyScore,
            importanceScore: entry.value.importanceScore,
            theoryScore: entry.value.theoryScore,
            featuredScore: entry.value.featuredScore,
            chapter: entry.value.chapter,
          ));

      await _dao.insertBank(bank);
      await _dao.insertQuestions(qs.toList());
      await loadBanks();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> deleteBank(String id) async {
    await _dao.deleteBank(id);
    await loadBanks();
  }

  Future<List<Question>> getBankQuestions(String bankId) async {
    return _dao.getBankQuestions(bankId);
  }

  Future<void> clearAllBanks() async {
    await _dao.clearAllBanks();
    await loadBanks();
  }
}
