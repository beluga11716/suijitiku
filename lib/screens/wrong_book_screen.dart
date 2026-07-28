import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/wrong_book_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/current_bank_provider.dart';
import '../database/dao.dart';
import '../models/question.dart';
import '../widgets/quiz_card.dart';

class WrongBookScreen extends StatefulWidget {
  const WrongBookScreen({super.key});

  @override
  State<WrongBookScreen> createState() => _WrongBookScreenState();
}

class _WrongBookScreenState extends State<WrongBookScreen>
    with SingleTickerProviderStateMixin {
  final _dao = Dao();
  bool _loading = true;

  // 子页面切换
  bool _showTestList = false;
  late TabController _tabController;
  List<dynamic> _wrongSessions = [];
  bool _sessionsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetail();
      // 从 URL 恢复子页面状态（quiz/result 返回时携带 sub=tests）
      try {
        final uri = GoRouterState.of(context).uri;
        if (uri.queryParameters['sub'] == 'tests') {
          setState(() => _showTestList = true);
          _loadWrongSessions();
        }
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

  Future<void> _loadDetail() async {
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await context.read<WrongBookProvider>().loadWrongQuestionsByBank(currentBankId);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWrongSessions() async {
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) return;
    setState(() => _sessionsLoading = true);
    // 当前题库的错题测试 = 该 bankId + source='wrongbook'
    final allSessions = await _dao.getSessionsByBank(currentBankId);
    final wrongSessions = allSessions.where((s) => s.source == 'wrongbook').toList();
    if (mounted) {
      setState(() {
        _wrongSessions = wrongSessions;
        _sessionsLoading = false;
      });
    }
  }

  // ==================== 错题详情视图 ====================

  void _openQuestionDetail(Question question) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => QuestionDetailPage(question: question),
      ),
    );
  }

  Future<void> _clearBankWrongQuestions() async {
    final provider = context.read<WrongBookProvider>();
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) return;
    final bank = await _dao.getBank(currentBankId);
    final bankName = bank?.name ?? '未知题库';

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空错题'),
        content: Text('确定要清空"$bankName"的所有错题记录吗？'),
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
      await provider.clearByBank(currentBankId);
      await _loadDetail();
    }
  }

  // ==================== 错题测试列表视图 ====================

  void _enterTestList() {
    _tabController.index = 0;
    setState(() => _showTestList = true);
    _loadWrongSessions();
  }

  void _exitTestList() {
    setState(() => _showTestList = false);
  }

  List<dynamic> get _inProgress =>
      _wrongSessions.where((s) => !s.isCompleted).toList();
  List<dynamic> get _completed =>
      _wrongSessions.where((s) => s.isCompleted).toList();

  Future<void> _createWrongSession() async {
    final currentBankId = context.read<CurrentBankProvider>().currentBankId;
    if (currentBankId == null) return;
    final totalWrong = await _dao.getWrongQuestionCountByBank(currentBankId);
    if (!mounted) return;
    if (totalWrong == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有错题，无法创建测试')));
      return;
    }

    final bank = await _dao.getBank(currentBankId);
    final bankName = bank?.name ?? '未知题库';
    if (!mounted) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CreateWrongBookDialog(totalCount: totalWrong, bankName: bankName),
    ).then((result) async {
      if (result == null || !mounted) return;

      await context.read<QuizProvider>().startWrongBookSessionByBank(
            bankId: currentBankId,
            count: result['count'] as int,
            quizStyle: result['style'] as String,
            name: result['name'] as String,
          );

      if (!mounted) return;
      final quiz = context.read<QuizProvider>();
      if (quiz.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(quiz.error!)));
        return;
      }
      context.go('/quiz/${quiz.currentSession!.id}?returnTo=${Uri.encodeComponent('/wrongbook?sub=tests')}');
      // 返回后自动刷新错题测试列表
      _loadWrongSessions();
    });
  }

  Future<void> _onTapWrongSession(dynamic session) async {
    if (session.isCompleted) {
      if (mounted) context.go('/result/${session.id}');
    } else {
      await context.read<QuizProvider>().resumeSession(session.id);
      if (mounted) context.go('/quiz/${session.id}?returnTo=${Uri.encodeComponent('/wrongbook?sub=tests')}');
    }
  }

  Future<void> _deleteWrongSession(dynamic session) async {
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
      await _loadWrongSessions();
    }
  }

  Future<void> _renameWrongSession(dynamic session) async {
    final newName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _RenameWrongSessionDialog(initialName: session.name),
    );
    if (newName != null && newName.isNotEmpty && newName != session.name) {
      await _dao.updateSession(session.copyWith(name: newName));
      await _loadWrongSessions();
    }
  }

  // ==================== 构建主视图 ====================

  @override
  Widget build(BuildContext context) {
    final currentBankId = context.watch<CurrentBankProvider>().currentBankId;

    if (_showTestList) {
      return _buildTestListSubPage(currentBankId);
    }

    return _buildDetailView(currentBankId);
  }

  Widget _buildDetailView(String? currentBankId) {
    final provider = context.watch<WrongBookProvider>();
    final wrongQuestions = provider.wrongQuestions;
    final theme = Theme.of(context);

    // 无选中题库
    if (currentBankId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错题本')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_outlined,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('请先在首页选择题库',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        actions: [
          if (wrongQuestions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearBankWrongQuestions,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wrongQuestions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('该题库没有错题',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                      const SizedBox(height: 8),
                      const Text('继续保持'),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 统计 + 刷错题
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text('${provider.count}',
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red)),
                                    const Text('错题数'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 72,
                              child: FilledButton.icon(
                                onPressed: _enterTestList,
                                icon: const Icon(Icons.replay),
                                label: const Text('刷错题'),
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 错题列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: wrongQuestions.length,
                        itemBuilder: (_, i) {
                          final q = wrongQuestions[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                                child: Text('${i + 1}'),
                              ),
                              title: Text(q.stem,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${q.type.label} · 答案：${q.answer}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openQuestionDetail(q),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  // ==================== 错题测试列表子页面 ====================

  Widget _buildTestListSubPage(String? currentBankId) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _exitTestList,
        ),
        title: const Text('错题测试列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '创建错题测试',
            onPressed: _createWrongSession,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '未完成 (${_inProgress.length})'),
            Tab(text: '已完成 (${_completed.length})'),
          ],
        ),
      ),
      body: _sessionsLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWrongSessionTab(_inProgress, theme),
                _buildWrongSessionTab(_completed, theme),
              ],
            ),
    );
  }

  Widget _buildWrongSessionTab(List<dynamic> sessions, ThemeData theme) {
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
      onRefresh: _loadWrongSessions,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sessions.length,
        itemBuilder: (_, i) => _buildWrongSessionCard(sessions[i], theme),
      ),
    );
  }

  Widget _buildWrongSessionCard(dynamic session, ThemeData theme) {
    final icon = session.quizStyle == 'exam'
        ? Icons.assignment
        : Icons.looks_one;
    final dateStr =
        '${session.startedAt.year}-${session.startedAt.month.toString().padLeft(2, '0')}-${session.startedAt.day.toString().padLeft(2, '0')}';
    final progress = '${session.answeredCount}/${session.questionCount} 题';
    final name = session.name.isNotEmpty ? session.name : '未命名测试';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.errorContainer,
          child: Icon(icon, color: theme.colorScheme.onErrorContainer, size: 20),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$progress · $dateStr · 随机 · ${session.quizStyle == 'exam' ? '试卷' : '逐题'}',
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'rename') _renameWrongSession(session);
            if (v == 'delete') _deleteWrongSession(session);
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
        onTap: () => _onTapWrongSession(session),
      ),
    );
  }
}

// ==================== 错题详情页 ====================

class QuestionDetailPage extends StatefulWidget {
  final Question question;
  const QuestionDetailPage({super.key, required this.question});

  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  final _dao = Dao();
  String? _userAnswer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final answer = await _dao.getLastWrongAnswer(widget.question.id);
    if (mounted) {
      setState(() {
        _userAnswer = answer;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('题目详情'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuizCard(
                question: widget.question,
                showAnswer: true,
                initialAnswer: _userAnswer,
              ),
            ),
    );
  }
}

// ==================== 创建错题测试 Dialog ====================

class _CreateWrongBookDialog extends StatefulWidget {
  final int totalCount;
  final String bankName;
  const _CreateWrongBookDialog(
      {required this.totalCount, required this.bankName});

  @override
  State<_CreateWrongBookDialog> createState() =>
      _CreateWrongBookDialogState();
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
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${widget.bankName} 错题复习';
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
              ButtonSegment(value: 'per_question', label: Text('逐题'), icon: Icon(Icons.looks_one)),
              ButtonSegment(value: 'exam', label: Text('试卷'), icon: Icon(Icons.assignment)),
            ],
            selected: {_quizStyle},
            onSelectionChanged: (v) => setState(() => _quizStyle = v.first),
          ),
          const SizedBox(height: 12),
          Text('题目数量: $_selectedCount 题'),
          Slider(
            value: _selectedCount.toDouble(),
            min: 1,
            max: widget.totalCount.toDouble(),
            divisions: widget.totalCount > 1 ? widget.totalCount - 1 : null,
            label: '$_selectedCount',
            onChanged: (v) => setState(() => _selectedCount = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _pop({
            'name': _nameCtrl.text.trim(),
            'style': _quizStyle,
            'count': _selectedCount,
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

// ==================== 重命名错题测试 Dialog ====================

class _RenameWrongSessionDialog extends StatefulWidget {
  final String initialName;
  const _RenameWrongSessionDialog({required this.initialName});

  @override
  State<_RenameWrongSessionDialog> createState() =>
      _RenameWrongSessionDialogState();
}

class _RenameWrongSessionDialogState
    extends State<_RenameWrongSessionDialog> {
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
