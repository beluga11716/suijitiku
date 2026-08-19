import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randomselector/app.dart';
import 'package:randomselector/database/database_helper.dart';
import 'package:randomselector/database/dao.dart';
import 'package:randomselector/models/question.dart';
import 'package:randomselector/models/question_bank.dart';
import 'package:randomselector/models/quiz_session.dart';
import 'package:randomselector/providers/bank_provider.dart';
import 'package:randomselector/providers/current_bank_provider.dart';
import 'package:randomselector/providers/quiz_provider.dart';
import 'package:randomselector/providers/settings_provider.dart';
import 'package:randomselector/providers/wrong_book_provider.dart';

/// 真实 IO（数据库初始化）必须在 runAsync 中执行——
/// testWidgets 的 fake async 区无法完成真实文件 IO
Future<void> _initDb() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }
  await DatabaseHelper.instance.database;
}

Future<void> _seedExamSession({
  required String sessionId,
  required String bankId,
  String status = 'in_progress',
}) async {
  final dao = Dao();
  await dao.insertBank(QuestionBank(id: bankId, name: '测试题库'));
  await dao.insertQuestions([
    Question(
      id: '$bankId-q1',
      bankId: bankId,
      type: QuestionType.singleChoice,
      stem: '第一题题干',
      options: const ['A. 选项一', 'B. 选项二'],
      answer: 'A',
    ),
    Question(
      id: '$bankId-q2',
      bankId: bankId,
      type: QuestionType.singleChoice,
      stem: '第二题题干',
      options: const ['A. 选项一', 'B. 选项二'],
      answer: 'B',
    ),
  ]);
  await dao.insertSession(QuizSession(
    id: sessionId,
    bankId: bankId,
    mode: 'basic',
    quizStyle: 'exam',
    questionCount: 2,
    name: '试卷测试',
    source: 'bank',
    questionIds: ['$bankId-q1', '$bankId-q2'],
    status: status,
  ));
}

/// 组装 app + providers，从指定 initialLocation 启动。
/// [currentBankId] 非空时预置当前题库（CurrentBankProvider.selectBank）。
Future<SettingsProvider> _pumpAppAt(
  WidgetTester tester,
  String initialLocation, {
  QuizProvider? quizProvider,
  String? currentBankId,
}) async {
  late final SettingsProvider settings;
  late final CurrentBankProvider currentBank;
  await tester.runAsync(() async {
    await _initDb();
    settings = SettingsProvider();
    await settings.loadSettings();
    currentBank = CurrentBankProvider();
    if (currentBankId != null) {
      await currentBank.selectBank(currentBankId);
    }
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BankProvider()),
        ChangeNotifierProvider.value(value: quizProvider ?? QuizProvider()),
        ChangeNotifierProvider(create: (_) => WrongBookProvider()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: currentBank),
      ],
      child: RandomSelectorApp(initialLocation: initialLocation),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

/// 组装 app + providers，并把 QuizProvider 恢复到指定会话
Future<(QuizProvider, SettingsProvider)> _pumpExamApp(
  WidgetTester tester,
  String sessionId,
) async {
  late final QuizProvider quizProvider;
  await tester.runAsync(() async {
    await _initDb();
    quizProvider = QuizProvider();
    await quizProvider.resumeSession(sessionId);
  });
  final settings = await _pumpAppAt(
    tester,
    '/quiz/$sessionId?returnTo=/tests',
    quizProvider: quizProvider,
  );
  return (quizProvider, settings);
}

/// 模拟 Android 系统返回键/手势（引擎发 popRoute 平台消息，与真机同一链路）
Future<void> _pressSystemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('试卷模式：交卷后应跳转到结果页', (WidgetTester tester) async {
    const sessionId = 'exam-submit-nav';
    await tester.runAsync(() async {
      await _initDb();
      await _seedExamSession(sessionId: sessionId, bankId: 'bank-submit');
    });
    await _pumpExamApp(tester, sessionId);

    expect(find.text('试卷模式'), findsOneWidget);

    // 点 AppBar 的「交卷」→ 确认 dialog 出现
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    expect(find.text('确认交卷'), findsOneWidget);

    // 点 dialog 内的交卷按钮（FilledButton，区分于 AppBar 的 TextButton）
    await tester.tap(find.widgetWithText(FilledButton, '交卷'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog 退场动画

    // submitExam 走真实 DB IO，在 runAsync 中轮询直到会话落库
    await tester.runAsync(() async {
      final dao = Dao();
      for (var i = 0; i < 100; i++) {
        final s = await dao.getSession(sessionId);
        if (s?.status == 'completed') return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    // 交卷成功 → 必须离开试卷页进入结果页
    expect(find.text('刷题结果'), findsOneWidget);
    expect(find.text('试卷模式'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('试卷模式：系统返回键应弹出退出确认而非直接退出',
      (WidgetTester tester) async {
    const sessionId = 'exam-back-confirm';
    await tester.runAsync(() async {
      await _initDb();
      await _seedExamSession(sessionId: sessionId, bankId: 'bank-back');
    });
    await _pumpExamApp(tester, sessionId);

    expect(find.text('试卷模式'), findsOneWidget);

    // 模拟手机系统返回键
    await _pressSystemBack(tester);

    // 应弹出「退出刷题」确认 dialog，页面不离开试卷
    expect(find.text('退出刷题'), findsOneWidget);
    expect(find.text('试卷模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('交卷确认 dialog 关闭后框架仍接管系统返回（Android 13+ 预测返回）',
      (WidgetTester tester) async {
    // 记录框架上报给引擎的「框架是否接管系统返回」——Android 13+ 上若上报
    // false，系统会在下一次返回手势直接销毁 Activity（app 退出）。
    final handlesBackCalls = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/platform',
      (message) async {
        final call = const JSONMethodCodec().decodeMethodCall(message);
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handlesBackCalls.add(call.arguments as bool);
        }
        return null;
      },
    );
    // 测试环境生命周期默认 detached，需切到 resumed 才会向引擎上报
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    const sessionId = 'exam-back-poisoning';
    await tester.runAsync(() async {
      await _initDb();
      await _seedExamSession(sessionId: sessionId, bankId: 'bank-poison');
    });
    await _pumpExamApp(tester, sessionId);

    // 进入试卷页后框架应上报「框架接管返回」
    expect(handlesBackCalls, isNotEmpty);
    expect(handlesBackCalls.last, isTrue);

    // 打开交卷确认 dialog 再取消（模拟交卷前犹豫）
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    expect(find.text('确认交卷'), findsOneWidget);
    await tester.tap(find.text('继续作答'));
    await tester.pumpAndSettle();

    // dialog 关闭后 root Navigator 重新上报——若变成 false，
    // Android 13+ 系统将接管返回手势，直接销毁 Activity。
    expect(handlesBackCalls.last, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果页：系统返回回到已完成测试列表（不退出）',
      (WidgetTester tester) async {
    const sessionId = 'result-back';
    await tester.runAsync(() async {
      await _initDb();
      await _seedExamSession(
        sessionId: sessionId,
        bankId: 'bank-result',
        status: 'completed',
      );
    });
    await _pumpAppAt(
      tester,
      '/result/$sessionId',
      currentBankId: 'bank-result',
    );

    // 结果页渲染完成
    expect(find.text('刷题结果'), findsOneWidget);

    // 模拟手机系统返回键
    await _pressSystemBack(tester);

    // 应回到刷题列表已完成 tab：结果页消失、已完成会话卡片可见
    expect(find.text('刷题结果'), findsNothing);
    expect(find.text('已完成 (1)'), findsOneWidget);
    expect(find.text('试卷测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
