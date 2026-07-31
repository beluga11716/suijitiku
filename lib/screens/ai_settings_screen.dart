import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../ai/llm_client.dart';

/// AI 配置独立页面，包含模型配置和 Prompt 模板编辑
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final settings = context.read<SettingsProvider>();
    _apiKeyController.text = settings.apiKey ?? '';
    _baseUrlController.text = settings.baseUrl ?? '';
    _modelController.text = settings.modelName ?? '';
    _promptController.text = settings.aiPrompt;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    final settings = context.read<SettingsProvider>();
    await settings.setBaseUrl(_baseUrlController.text.trim());
    await settings.setApiKey(_apiKeyController.text.trim());
    await settings.setModelName(_modelController.text.trim());
    await settings.setAiPrompt(_promptController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
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
    } else if (type == 'deepseek') {
      _baseUrlController.text = 'https://api.deepseek.com';
      _modelController.text = 'deepseek-chat';
      await settings.setBaseUrl('https://api.deepseek.com');
      await settings.setModelName('deepseek-chat');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已填入 $type 默认配置')));
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Base URL 和 API Key')),
      );
      return;
    }

    BuildContext? loadingCtx;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        loadingCtx = dialogContext;
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      final models = await LlmClient.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );

      if (!mounted) return;
      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }

      final selected = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('选择模型'),
          content: SizedBox(
            width: 300,
            height: 400,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(models[i]),
                onTap: () => Navigator.pop(dialogContext, models[i]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
      );

      if (selected != null && mounted) {
        _modelController.text = selected;
      }
    } catch (e) {
      if (!mounted) return;
      if (loadingCtx != null && Navigator.canPop(loadingCtx!)) {
        Navigator.pop(loadingCtx!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取模型列表失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空 AI 配置'),
        content: const Text('将清除 Base URL、API Key、Model Name，并恢复 Prompt 为默认值。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _baseUrlController.clear();
      _apiKeyController.clear();
      _modelController.clear();
      _promptController.text = LlmClient.defaultPrompt;
      await _saveAll();
    }
  }

  void _resetPrompt() {
    _promptController.text = LlmClient.defaultPrompt;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('AI 配置'),
            if (settings.hasLLM) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
              const SizedBox(width: 2),
              Text('已配置',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.green.shade600)),
            ],
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================== 模型配置 ====================
          Text('模型配置',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('配置 LLM API 以启用 LLM 精选分析和主观题判分',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),

          // 预设按钮
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
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
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _setPreset('deepseek'),
                  child: const Text('DeepSeek 默认'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Base URL
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // API Key
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: OutlineInputBorder(),
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
                icon: const Icon(Icons.cloud_download),
                tooltip: '获取模型列表',
                onPressed: _fetchModels,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 保存按钮
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('保存配置'),
            ),
          ),
          const SizedBox(height: 24),

          // ==================== Prompt 模板 ====================
          Row(
            children: [
              Text('LLM 分析 Prompt',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetPrompt,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复默认'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('自定义 LLM 分析题目的标准。占位符 {questions_json} 会被替换为实际题目数据',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '输入 Prompt 模板...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),

          // ==================== 自动分析 ====================
          Text('导入设置',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('导入题库后自动 LLM 分析'),
            subtitle: const Text('导入新题库后自动调用 LLM 进行分析（需已配置 LLM）'),
            value: settings.autoLlmAnalyze,
            onChanged: (v) => settings.setAutoLlmAnalyze(v),
          ),
          const SizedBox(height: 16),

          // 清空配置
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _clearConfig,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: const Text('清空 AI 配置', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
