import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/quiz_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/current_bank_provider.dart';
import '../models/question.dart';
import '../database/dao.dart';

class TestListScreen extends StatefulWidget {
  const TestListScreen({super.key});

  @override
  State<TestListScreen> createState() => _TestListScreenState();
}

class _TestListScreenState extends State<TestListScreen>
    with SingleTickerProviderStateMixin {
  final _dao = Dao();
  late TabController _tabController;
  String _bankName = '';
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
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) {
      if (mounted) {
        setState(() {
          _bankName = '';
          _allSessions = [];
          _loading = false;
        });
      }
      return;
    }

    final bank = await _dao.getBank(currentBankId);
    final sessions = await _dao.getSessionsByBank(currentBankId);
    // 只显示题库测试，错题测试归 WrongBookScreen 管理
    final bankSessions = sessions.where((s) => s.source != 'wrongbook').toList();
    if (mounted) {
      setState(() {
        _bankName = bank?.name ?? '未知题库';
        _allSessions = bankSessions;
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
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _RenameTestDialog(initialName: initialName),
    );
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
      if (mounted) context.go('/quiz/${session.id}?returnTo=/tests');
    }
  }

  // ==================== 创建测试 ====================

  Future<void> _showCreateDialog() async {
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) return;
    final hasLLM = context.read<SettingsProvider>().hasLLM;
    final questions = await _dao.getBankQuestions(currentBankId);
    final bank = await _dao.getBank(currentBankId);
    if (!mounted) return;

    final totalQuestions = questions.length;
    if (totalQuestions == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('题库中没有题目')));
      return;
    }

    final result = await showDialog<Map>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CreateTestDialog(
        bankName: bank?.name ?? '',
        totalQuestions: totalQuestions,
        hasSubjective: questions.any((q) => !q.type.isObjective),
        hasLLM: hasLLM,
      ),
    );

    if (result == null || !mounted) return;

    final types = result['types'] as List<String>?;
    await context.read<QuizProvider>().startSession(
          bankId: currentBankId,
          mode: result['mode'] as String,
          quizStyle: result['style'] as String,
          count: result['count'] as int,
          name: result['name'] as String? ?? '',
          questionTypes: types,
        );

    final quiz = context.read<QuizProvider>();
    if (quiz.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(quiz.error!)));
      return;
    }
    if (mounted) {
      context.go('/quiz/${quiz.currentSession!.id}?returnTo=/tests');
    }
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBankId = context.watch<CurrentBankProvider>().currentBankId;

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: currentBankId == null
          ? _buildNoBank(theme)
          : _loading
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

  Widget _buildNoBank(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_books_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('请先在首页选择题库',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
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
      title: Text(_bankName.isEmpty ? '刷题记录' : _bankName),
      actions: [
        if (_allSessions.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: '批量选择',
            onPressed: _enterSelecting,
          ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '创建新测试',
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
      return _buildEmpty(theme);
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

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('还没有测试',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          Text('点击右上角 + 创建新测试',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildSessionCard(dynamic session, ThemeData theme) {
    final icon = session.quizStyle == 'exam'
        ? Icons.assignment
        : Icons.looks_one;
    final dateStr =
        '${session.startedAt.year}-${session.startedAt.month.toString().padLeft(2, '0')}-${session.startedAt.day.toString().padLeft(2, '0')}';
    final progress = '${session.answeredCount}/${session.questionCount} 题';
    final name = session.name.isNotEmpty ? session.name : '未命名测试';
    final isSelected = _selectedIds.contains(session.id);
    final isWrongBook = session.source == 'wrongbook';

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
                backgroundColor: isWrongBook
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                child: Icon(icon,
                    color: isWrongBook
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSecondaryContainer),
              ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$progress · $dateStr · ${session.mode == 'featured' ? 'AI精选' : '随机'} · ${session.quizStyle == 'exam' ? '试卷' : '逐题'}',
        ),
        trailing: _selecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWrongBook)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: const Text('错',
                            style: TextStyle(fontSize: 12, color: Colors.white)),
                        backgroundColor: Colors.red,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
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
                          Text('删除', style: TextStyle(color: Colors.red)),
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
}

// ==================== 重命名测试 Dialog ====================

class _RenameTestDialog extends StatefulWidget {
  final String initialName;
  const _RenameTestDialog({required this.initialName});

  @override
  State<_RenameTestDialog> createState() => _RenameTestDialogState();
}

class _RenameTestDialogState extends State<_RenameTestDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop([String? value]) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.pop(context, value));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名测试'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '测试名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => _pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _pop(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ==================== 创建测试 Dialog ====================

class _CreateTestDialog extends StatefulWidget {
  final String bankName;
  final int totalQuestions;
  final bool hasSubjective;
  final bool hasLLM;

  const _CreateTestDialog({
    required this.bankName,
    required this.totalQuestions,
    required this.hasSubjective,
    required this.hasLLM,
  });

  @override
  State<_CreateTestDialog> createState() => _CreateTestDialogState();
}

class _CreateTestDialogState extends State<_CreateTestDialog> {
  late final TextEditingController _nameCtrl;
  String _mode = 'basic';
  String _quizStyle = 'per_question';
  late int _selectedCount;
  Set<QuestionType> _selectedTypes = QuestionType.values.toSet();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    final now = DateTime.now();
    _nameCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${widget.bankName}';
    _selectedCount = (widget.totalQuestions / 2).round().clamp(1, widget.totalQuestions);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _blocked => widget.hasSubjective && !widget.hasLLM;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建测试'),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 题库信息
              Text('${widget.bankName} · 共 ${widget.totalQuestions} 道题',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              // 测试名称
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '测试名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // 抽题模式
              const Text('抽题模式'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'basic', label: Text('随机'), icon: Icon(Icons.shuffle)),
                  ButtonSegment(value: 'featured', label: Text('AI精选'), icon: Icon(Icons.auto_awesome)),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              if (_mode == 'featured')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('按难度/重要性/理论性综合排序，优先抽高分题',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              // 答题方式
              const Text('答题方式'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'per_question', label: Text('逐题'), icon: Icon(Icons.looks_one)),
                  ButtonSegment(value: 'exam', label: Text('试卷'), icon: Icon(Icons.assignment)),
                ],
                selected: {_quizStyle},
                onSelectionChanged: (v) => setState(() => _quizStyle = v.first),
              ),
              const SizedBox(height: 12),
              // 题目数量
              Text('题目数量: $_selectedCount 题'),
              Slider(
                value: _selectedCount.toDouble(),
                min: 1,
                max: widget.totalQuestions.toDouble(),
                divisions: widget.totalQuestions > 1 ? widget.totalQuestions - 1 : null,
                label: '$_selectedCount',
                onChanged: (v) => setState(() => _selectedCount = v.round()),
              ),
              const SizedBox(height: 12),
              // 题型筛选
              Text('题型筛选',
                  style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 8,
                children: QuestionType.values.map((type) {
                  final selected = _selectedTypes.contains(type);
                  return FilterChip(
                    label: Text(type.label),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedTypes.add(type);
                        } else if (_selectedTypes.length > 1) {
                          _selectedTypes.remove(type);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              // 主观题提示
              if (_blocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(children: [
                        Icon(Icons.info_outline),
                        SizedBox(width: 8),
                        Expanded(child: Text('含主观题，需先在设置中配置 LLM API')),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _blocked
              ? null
              : () => _pop({
                  'name': _nameCtrl.text.trim(),
                  'mode': _mode,
                  'style': _quizStyle,
                  'count': _selectedCount,
                  'types': _selectedTypes.length == QuestionType.values.length
                      ? null
                      : _selectedTypes.map((t) => t.dbValue).toList(),
                }),
          child: const Text('开始'),
        ),
      ],
    );
  }

  void _pop([dynamic value]) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Navigator.pop(context, value));
  }
}
