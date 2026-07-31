import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'database/database_helper.dart';
import 'database/dao.dart';
import 'providers/bank_provider.dart';
import 'providers/quiz_provider.dart';
import 'providers/wrong_book_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/current_bank_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端需要初始化 sqflite FFI；移动端用原生的 platform channel 实现
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 确保数据库初始化
  await DatabaseHelper.instance.database;

  // 读取启动 tab 设置
  final dao = Dao();
  final startTab = await dao.getSetting('start_tab') ?? 'home';
  final initialLocation = startTab == 'tests'
      ? '/tests'
      : startTab == 'wrongbook'
          ? '/wrongbook'
          : '/';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BankProvider()),
        ChangeNotifierProvider(create: (_) => QuizProvider()),
        ChangeNotifierProvider(create: (_) => WrongBookProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => CurrentBankProvider()),
      ],
      child: RandomSelectorApp(initialLocation: initialLocation),
    ),
  );
}
