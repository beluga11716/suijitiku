import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/bank_provider.dart';
import '../providers/wrong_book_provider.dart';
import '../database/dao.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dao = Dao();
  int _totalQuestions = 0;
  int _totalBanks = 0;
  int _totalQuizzes = 0;
  double _accuracy = 0.0;
  int _wrongCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    final bankProv = context.read<BankProvider>();
    final wrongProv = context.read<WrongBookProvider>();
    final totalQuestions = await _dao.getTotalQuestionCount();
    final totalBanks = await _dao.getTotalBankCount();
    final totalQuizzes = await _dao.getTotalQuizCount();
    final accuracy = await _dao.getOverallAccuracy();
    await bankProv.loadBanks();
    await wrongProv.loadWrongQuestions();

    if (mounted) {
      setState(() {
        _totalQuestions = totalQuestions;
        _totalBanks = totalBanks;
        _totalQuizzes = totalQuizzes;
        _accuracy = accuracy;
        _wrongCount = wrongProv.count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = context.watch<BankProvider>().banks;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('题库抽题器'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 统计卡片
            _StatsGrid(
              totalBanks: _totalBanks,
              totalQuestions: _totalQuestions,
              totalQuizzes: _totalQuizzes,
              accuracy: _accuracy,
            ),
            const SizedBox(height: 24),

            // 错题提醒
            if (_wrongCount > 0)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(Icons.warning_amber,
                      color: theme.colorScheme.onErrorContainer),
                  title: Text('$_wrongCount 道错题待复习',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600)),
                  trailing: FilledButton(
                    onPressed: () => context.go('/wrongbook'),
                    style: FilledButton.styleFrom(
                        backgroundColor:
                            theme.colorScheme.onErrorContainer,
                        foregroundColor:
                            theme.colorScheme.errorContainer),
                    child: const Text('去复习'),
                  ),
                ),
              ),
            if (_wrongCount > 0) const SizedBox(height: 24),

            // 快速选择题库
            Text('选择题库开始刷题',
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),

            if (banks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('还没有题库，去导入一份吧',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              ...banks.take(10).map((bank) => Card(
                    child: ListTile(
                      title: Text(bank.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${bank.questionCount} 道题 · ${_formatDate(bank.createdAt)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.go('/banks/${bank.id}/tests'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _StatsGrid extends StatelessWidget {
  final int totalBanks;
  final int totalQuestions;
  final int totalQuizzes;
  final double accuracy;

  const _StatsGrid({
    required this.totalBanks,
    required this.totalQuestions,
    required this.totalQuizzes,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: '题库', value: '$totalBanks')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: '题目', value: '$totalQuestions')),
        const SizedBox(width: 8),
        Expanded(
            child:
                _StatCard(label: '已刷', value: '$totalQuizzes 次')),
        const SizedBox(width: 8),
        Expanded(
            child: _StatCard(
                label: '正确率',
                value: '${(accuracy * 100).toStringAsFixed(0)}%')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
