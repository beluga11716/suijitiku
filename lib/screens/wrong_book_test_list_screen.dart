import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/quiz_provider.dart';
import '../database/dao.dart';

class WrongBookTestListScreen extends StatefulWidget {
  const WrongBookTestListScreen({super.key});

  @override
  State<WrongBookTestListScreen> createState() =>
      _WrongBookTestListScreenState();
}

class _WrongBookTestListScreenState extends State<WrongBookTestListScreen>
    with SingleTickerProviderStateMixin {
  final _dao = Dao();
  late TabController _tabController;
  List<dynamic> _allSessions = [];
  bool _loading = true;

  // 批量选择模式
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // 恢复 tab 状态
      try {
        final uri = GoRouterState.of(context).uri;
        final tab = int.tryParse(uri.queryParameters['tab'] ?? '');
        if (tab != null && tab >= 0 && tab < 2) {
          _tabController.index = tab;
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await _dao.getSessionsBySource('wrongbook');
    if (mounted) {
      setState(() {
        _allSessions = sessions;
        _loading = false;
      });
    }
  }

  List<dynamic> get _inProgress =>
      _allSessions.where((s) => !s.isCompleted).toList();
  List<dynamic> get _completed =>
      _allSessions.where((s) => s.isCompleted).toList();

  // ==================== 批量选择 ====================

  void _enterSelecting() => setState(() => _selecting = true);
  void _exitSelecting() =>
      setState(() { _selecting = false; _selectedIds.clear(); });

  void _toggleItem(String id) {
    setState(() {
      _selectedIds.contains(id)
          ? _selectedIds.remove(id)
          : _selectedIds.add(id);
    });
  }

  void _toggleSelectAll() {
    final currentList = _tabController.index == 0 ? _inProgress : _completed;
    final allIds = currentList.map((s) => s.id as String).toSet();
    setState(() {
      if (_selectedIds.containsAll(allIds)) {
        _selectedIds.removeAll(allIds);
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个测试吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      for (final id in _selectedIds.toList()) {
        await _dao.deleteSession(id);
      }
      _exitSelecting();
      await _load();
    }
  }

  // ==================== 单个操作 ====================

  Future<String?> _showRenameDialog(String initialName) async {
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名测试'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '测试名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => Navigator.pop(dialogContext, v.trim()));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => Navigator.pop(dialogContext, controller.text.trim()));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteSession(dynamic session) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除测试'),
        content: const Text('删除后数据无法恢复，确定要删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _dao.deleteSession(session.id);
      await _load();
    }
  }

  // ==================== 导航 ====================

  Future<void> _onTapSession(dynamic session) async {
    if (_selecting) {
      _toggleItem(session.id);
      return;
    }
    if (session.isCompleted) {
      if (mounted) context.go('/result/${session.id}');
    } else {
      await context.read<QuizProvider>().resumeSession(session.id);
      if (mounted) context.go('/quiz/${session.id}?returnTo=/wrongbook/tests');
    }
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTab(_inProgress, theme),
                _buildTab(_completed, theme),
              ],
            ),
    );
  }

  AppBar _buildAppBar(ThemeData theme) {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelecting,
        ),
        title: Text('已选 ${_selectedIds.length} 项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: '全选',
            onPressed: _toggleSelectAll,
          ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: '删除选中',
              onPressed: _deleteSelected,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '未完成 (${_inProgress.length})'),
            Tab(text: '已完成 (${_completed.length})'),
          ],
        ),
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/wrongbook'),
      ),
      title: const Text('错题测试'),
      actions: [
        if (_allSessions.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: '批量选择',
            onPressed: _enterSelecting,
          ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '创建错题测试',
          onPressed: _showCreateDialog,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: [
          Tab(text: '未完成 (${_inProgress.length})'),
          Tab(text: '已完成 (${_completed.length})'),
        ],
      ),
    );
  }

  Widget _buildTab(List<dynamic> sessions, ThemeData theme) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('还没有错题测试',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            Text('点击右上角 + 创建错题测试',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sessions.length,
        itemBuilder: (_, i) => _buildSessionCard(sessions[i], theme),
      ),
    );
  }

  Widget _buildSessionCard(dynamic session, ThemeData theme) {
    final icon = session.quizStyle == 'exam'
        ? Icons.assignment
        : Icons.looks_one;
    final dateStr =
        '${session.startedAt.year}-${session.startedAt.month.toString().padLeft(2, '0')}-${session.startedAt.day.toString().padLeft(2, '0')}';
    final progress =
        '${session.answeredCount}/${session.questionCount} 题';
    final name = session.name.isNotEmpty ? session.name : '未命名测试';
    final isSelected = _selectedIds.contains(session.id);

    return Card(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: ListTile(
        leading: _selecting
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleItem(session.id),
              )
            : CircleAvatar(
                backgroundColor: theme.colorScheme.errorContainer,
                child: Icon(icon,
                    color: theme.colorScheme.onErrorContainer, size: 20),
              ),
        title: Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$progress · $dateStr · 随机 · ${session.quizStyle == 'exam' ? '试卷' : '逐题'}',
        ),
        trailing: _selecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: const Text('错',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white)),
                    backgroundColor: Colors.red,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'rename') _doRename(session);
                      if (v == 'delete') _deleteSession(session);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('重命名'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('删除',
                              style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
        onTap: () => _onTapSession(session),
        onLongPress: () {
          if (!_selecting) {
            _enterSelecting();
            _toggleItem(session.id);
          }
        },
      ),
    );
  }

  Future<void> _doRename(dynamic session) async {
    final newName = await _showRenameDialog(session.name);
    if (newName != null && newName.isNotEmpty && newName != session.name) {
      await _dao.updateSession(session.copyWith(name: newName));
      await _load();
    }
  }

  // ==================== 创建错题测试 ====================

  void _showCreateDialog() async {
    final totalWrong = await _dao.getWrongQuestionCount();
    if (!mounted) return;
    if (totalWrong == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有错题，无法创建测试')));
      return;
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CreateWrongBookDialog(totalCount: totalWrong),
    ).then((result) {
      if (result != null && result is Map) {
        _createAndStart(
          result['name'] as String,
          result['style'] as String,
          result['count'] as int,
        );
      }
    });
  }

  Future<void> _createAndStart(
      String name, String quizStyle, int count) async {
    await context.read<QuizProvider>().startWrongBookSession(
          count: count,
          quizStyle: quizStyle,
          name: name,
        );

    if (!mounted) return;
    final quiz = context.read<QuizProvider>();
    if (quiz.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(quiz.error!)));
      return;
    }
    context.go('/quiz/${quiz.currentSession!.id}?returnTo=/wrongbook/tests');
  }
}

// ==================== 创建错题测试 Dialog ====================

class _CreateWrongBookDialog extends StatefulWidget {
  final int totalCount;
  const _CreateWrongBookDialog({required this.totalCount});

  @override
  State<_CreateWrongBookDialog> createState() => _CreateWrongBookDialogState();
}

class _CreateWrongBookDialogState extends State<_CreateWrongBookDialog> {
  late final TextEditingController _nameCtrl;
  String _quizStyle = 'per_question';
  late int _selectedCount;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    final now = DateTime.now();
    _nameCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 错题复习';
    _selectedCount =
        (widget.totalCount / 2).round().clamp(1, widget.totalCount);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建错题测试'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '测试名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('答题方式'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'per_question',
                  label: Text('逐题'),
                  icon: Icon(Icons.looks_one)),
              ButtonSegment(
                  value: 'exam',
                  label: Text('试卷'),
                  icon: Icon(Icons.assignment)),
            ],
            selected: {_quizStyle},
            onSelectionChanged: (v) =>
                setState(() => _quizStyle = v.first),
          ),
          const SizedBox(height: 12),
          Text('题目数量: $_selectedCount 题'),
          Slider(
            value: _selectedCount.toDouble(),
            min: 1,
            max: widget.totalCount.toDouble(),
            divisions: widget.totalCount > 1 ? widget.totalCount - 1 : null,
            label: '$_selectedCount',
            onChanged: (v) =>
                setState(() => _selectedCount = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': _nameCtrl.text.trim(),
              'style': _quizStyle,
              'count': _selectedCount,
            });
          },
          child: const Text('开始'),
        ),
      ],
    );
  }
}
