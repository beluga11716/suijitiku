import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randomselector/app.dart';
import 'package:randomselector/database/database_helper.dart';
import 'package:randomselector/providers/bank_provider.dart';
import 'package:randomselector/providers/current_bank_provider.dart';
import 'package:randomselector/providers/quiz_provider.dart';
import 'package:randomselector/providers/settings_provider.dart';
import 'package:randomselector/providers/wrong_book_provider.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    // 真实 IO（数据库初始化）必须在 runAsync 中执行——
    // testWidgets 的 fake async 区无法完成真实文件 IO
    late final SettingsProvider settingsProvider;
    await tester.runAsync(() async {
      // 测试环境用 FFI NoIsolate 工厂（isolate 版在 flutter_tester 下握手挂起）
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfiNoIsolate;
      }
      await DatabaseHelper.instance.database;
      settingsProvider = SettingsProvider();
      await settingsProvider.loadSettings();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BankProvider()),
          ChangeNotifierProvider(create: (_) => QuizProvider()),
          ChangeNotifierProvider(create: (_) => WrongBookProvider()),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider(create: (_) => CurrentBankProvider()),
        ],
        child: const RandomSelectorApp(),
      ),
    );
    await tester.pump();
    // Verify the app renders without crashing
    expect(find.text('题库抽题器'), findsOneWidget);
  });
}
