import 'package:flutter/foundation.dart';
import '../database/dao.dart';

class CurrentBankProvider extends ChangeNotifier {
  final Dao _dao = Dao();

  String? _currentBankId;
  String? get currentBankId => _currentBankId;
  bool get hasBank => _currentBankId != null;

  /// 启动时从 settings 恢复上次选中的题库
  Future<void> init() async {
    _currentBankId = await _dao.getSetting('current_bank_id');
    notifyListeners();
  }

  /// 切换当前题库，持久化并通知所有监听者
  Future<void> selectBank(String bankId) async {
    if (_currentBankId == bankId) return;
    _currentBankId = bankId;
    await _dao.setSetting('current_bank_id', bankId);
    notifyListeners();
  }
}
