import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/bank_provider.dart';
import '../providers/wrong_book_provider.dart';
import '../database/dao.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _dao = Dao();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = context.read<SettingsProvider>();
    await settings.loadSettings();

    _apiKeyController.text = settings.apiKey ?? '';
    _baseUrlController.text = settings.baseUrl ?? '';
    _modelController.text = settings.modelName ?? '';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    await context
        .read<SettingsProvider>()
        .setApiKey(_apiKeyController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API Key 已保存')));
    }
  }

  Future<void> _saveBaseUrl() async {
    await context
        .read<SettingsProvider>()
        .setBaseUrl(_baseUrlController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Base URL 已保存')));
    }
  }

  Future<void> _saveModel() async {
    await context
        .read<SettingsProvider>()
        .setModelName(_modelController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Model 已保存')));
    }
  }

  Future<void> _setPreset(String type) async {
    final settings = context.read<SettingsProvider>();
    if (type == 'openai') {
      _baseUrlController.text = 'https://api.openai.com';
      _modelController.text = 'gpt-4o';
      await settings.setBaseUrl('https://api.openai.com');
      await settings.setModelName('gpt-4o');
    } else if (type == 'claude') {
      _baseUrlController.text = 'https://api.anthropic.com';
      _modelController.text = 'claude-sonnet-5';
      await settings.setBaseUrl('https://api.anthropic.com');
      await settings.setModelName('claude-sonnet-5');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已填入 $type 默认配置')));
    }
  }

  Future<void> _clearRecords() async {
    final wrongBookProv = context.read<WrongBookProvider>();
    final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
              title: const Text('清空刷题记录'),
              content: const Text('将删除所有刷题会话和答题记录，题库会保留。确定吗？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('清空')),
              ],
            ));
    if (ok == true && mounted) {
      await _dao.clearAllRecords();
      await wrongBookProv.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('刷题记录已清空')));
      }
    }
  }

  Future<void> _clearBanks() async {
    final bankProv = context.read<BankProvider>();
    final wrongBookProv = context.read<WrongBookProvider>();
    final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
              title: const Text('清空题库'),
              content: const Text('将删除所有题库和题目。此操作不可撤销！'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red),
                  child: const Text('清空全部'),
                ),
              ],
            ));
    if (ok == true && mounted) {
      await _dao.clearAllRecords();
      await bankProv.clearAllBanks();
      await wrongBookProv.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所有题库已清空')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // LLM API 配置
          Text('AI 配置（可选）',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('配置 LLM API 以启用 AI 精选分析和主观题判分',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),

          // 预设按钮
          Row(
            children: [
              OutlinedButton(
                onPressed: () => _setPreset('openai'),
                child: const Text('OpenAI 默认'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _setPreset('claude'),
                child: const Text('Claude 默认'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Base URL
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.save), onPressed: _saveBaseUrl),
            ),
          ),
          const SizedBox(height: 12),

          // API Key
          TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.save), onPressed: _saveApiKey),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),

          // Model
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              labelText: 'Model Name',
              hintText: 'gpt-4o',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.save), onPressed: _saveModel),
            ),
          ),
          if (settings.hasLLM)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Chip(
                avatar: Icon(Icons.check_circle, size: 18),
                label: Text('LLM 已配置'),
                color: WidgetStatePropertyAll(Colors.green),
              ),
            ),

          const SizedBox(height: 32),

          // 数据管理
          Text('数据管理',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('清空刷题记录'),
            subtitle: const Text('保留题库，仅删除刷题历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearRecords,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('清空所有题库',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('删除所有题库和题目，不可恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearBanks,
          ),

          const SizedBox(height: 32),

          // 关于
          Text('关于',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const ListTile(
            title: Text('题库抽题器'),
            subtitle: Text('版本 1.0.0 · GPL-3.0'),
          ),
        ],
      ),
    );
  }
}
