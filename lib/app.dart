import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/bank_list_screen.dart';
import 'screens/test_list_screen.dart';
import 'screens/test_create_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/result_screen.dart';
import 'screens/wrong_book_screen.dart';
import 'screens/wrong_book_bank_detail_screen.dart';
import 'screens/wrong_book_test_list_screen.dart';
import 'screens/settings_screen.dart';

class RandomSelectorApp extends StatelessWidget {
  const RandomSelectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '题库抽题器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4A90D9),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4A90D9),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/banks',
          builder: (context, state) => const BankListScreen(),
        ),
        GoRoute(
          path: '/banks/:bankId/tests',
          builder: (context, state) => TestListScreen(
            bankId: state.pathParameters['bankId']!,
          ),
        ),
        GoRoute(
          path: '/banks/:bankId/tests/create',
          builder: (context, state) => TestCreateScreen(
            bankId: state.pathParameters['bankId']!,
          ),
        ),
        GoRoute(
          path: '/wrongbook/tests',
          builder: (context, state) => const WrongBookTestListScreen(),
        ),
        GoRoute(
          path: '/wrongbook/:bankId',
          builder: (context, state) => WrongBookBankDetailScreen(
            bankId: state.pathParameters['bankId']!,
          ),
        ),
        GoRoute(
          path: '/quiz/:sessionId',
          builder: (context, state) => QuizScreen(
            sessionId: state.pathParameters['sessionId']!,
            returnTo: state.uri.queryParameters['returnTo'],
          ),
        ),
        GoRoute(
          path: '/result/:sessionId',
          builder: (context, state) => ResultScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
        GoRoute(
          path: '/wrongbook',
          builder: (context, state) => const WrongBookScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);

class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final showNav = _shouldShowNav(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: showNav
          ? NavigationBar(
              selectedIndex: _calculateSelectedIndex(context),
              onDestinationSelected: (index) => _onItemTapped(index, context),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: '题库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.error_outline_outlined),
                  selectedIcon: Icon(Icons.error_outline),
                  label: '错题本',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            )
          : null,
    );
  }

  /// 刷题和结果页面全屏显示，隐藏底部导航
  bool _shouldShowNav(BuildContext context) {
    try {
      final location = GoRouterState.of(context).uri.toString();
      // 刷题页面全屏
      if (location.startsWith('/quiz/')) {
        return false;
      }
      if (location.startsWith('/result')) {
        return false;
      }
      // 测试列表/创建页全屏
      if (location.startsWith('/banks/') && location.contains('/tests')) {
        return false;
      }
      if (location.startsWith('/wrongbook/tests')) {
        return false;
      }
      // 错题本按题库查看详情页全屏
      if (RegExp(r'^/wrongbook/[^/]+$').hasMatch(location)) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  int _calculateSelectedIndex(BuildContext context) {
    try {
      final location = GoRouterState.of(context).uri.toString();
      if (location.startsWith('/banks')) {
        return 1;
      }
      if (location.startsWith('/wrongbook')) {
        return 2;
      }
      if (location.startsWith('/settings')) {
        return 3;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/banks');
      case 2:
        context.go('/wrongbook');
      case 3:
        context.go('/settings');
    }
  }
}
