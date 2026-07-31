import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/test_list_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/result_screen.dart';
import 'screens/wrong_book_screen.dart';
import 'screens/settings_screen.dart';

class RandomSelectorApp extends StatefulWidget {
  final String initialLocation;

  const RandomSelectorApp({super.key, this.initialLocation = '/'});

  @override
  State<RandomSelectorApp> createState() => _RandomSelectorAppState();
}

class _RandomSelectorAppState extends State<RandomSelectorApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppScaffold(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: '/tests',
              builder: (context, state) => const TestListScreen(),
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
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final seedColor = settings.themeColor;
    final themeMode = settings.themeType.toThemeMode;

    return MaterialApp.router(
      title: '题库抽题器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

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
                  icon: Icon(Icons.assignment_outlined),
                  selectedIcon: Icon(Icons.assignment),
                  label: '刷题',
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
      // 仅刷题中和结果页全屏隐藏导航栏
      if (location.startsWith('/quiz/')) return false;
      if (location.startsWith('/result')) return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  int _calculateSelectedIndex(BuildContext context) {
    try {
      final location = GoRouterState.of(context).uri.toString();
      if (location.startsWith('/tests')) return 1;
      if (location.startsWith('/wrongbook')) return 2;
      if (location.startsWith('/settings')) return 3;
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
        context.go('/tests');
      case 2:
        context.go('/wrongbook');
      case 3:
        context.go('/settings');
    }
  }
}
