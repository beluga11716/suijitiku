import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/wrong_book_provider.dart';

class WrongBookScreen extends StatefulWidget {
  const WrongBookScreen({super.key});

  @override
  State<WrongBookScreen> createState() => _WrongBookScreenState();
}

class _WrongBookScreenState extends State<WrongBookScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WrongBookProvider>().loadBanksWithWrongQuestions();
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空所有错题'),
        content: const Text('确定要清空所有题库的错题记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WrongBookProvider>().clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WrongBookProvider>();
    final banks = provider.banksWithWrong;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        actions: [
          if (banks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空全部错题',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: banks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('太棒了，没有错题！',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  const Text('继续保持'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () =>
                  provider.loadBanksWithWrongQuestions(),
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: banks.length,
                itemBuilder: (_, i) {
                  final bank = banks[i];
                  final bankId = bank['bank_id'] as String;
                  final bankName = bank['bank_name'] as String;
                  final wrongCount = bank['wrong_count'] as int;
                  final totalCount = bank['total_count'] as int;

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        child: Text('$wrongCount'),
                      ),
                      title: Text(bankName),
                      subtitle: Text('错题 $wrongCount · 总题 $totalCount'),
                      trailing:
                          const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.go('/wrongbook/$bankId'),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
