import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'database/database_helper.dart';
import 'providers/bank_provider.dart';
import 'providers/quiz_provider.dart';
import 'providers/wrong_book_provider.dart';
import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端需要初始化 sqflite FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 确保数据库初始化
  await DatabaseHelper.instance.database;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BankProvider()),
        ChangeNotifierProvider(create: (_) => QuizProvider()),
        ChangeNotifierProvider(create: (_) => WrongBookProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const RandomSelectorApp(),
    ),
  );
}
