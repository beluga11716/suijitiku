import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/theme/theme_type.dart';
import '../models/theme/theme_color_type.dart';
import '../providers/settings_provider.dart';
import '../providers/bank_provider.dart';
import '../providers/wrong_book_provider.dart';
import '../database/dao.dart';
import 'ai_settings_screen.dart';
import 'theme_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dao = Dao();

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

  void _openAiSettings() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );
  }

  void _openThemeColorSettings() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()),
    );
  }

  void _openGeneralSettings() {
    _showGeneralSettingsDialog();
  }

  Future<void> _showThemeModeDialog() async {
    final settings = context.read<SettingsProvider>();
    ThemeType? selected = settings.themeType;
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('主题模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ThemeType.values
                .map((t) => ListTile(
                      title: Text(t.label),
                      trailing: selected == t
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        setDialogState(() => selected = t);
                        settings.setThemeModeIndex(t.index);
                        Navigator.pop(dialogContext);
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showGeneralSettingsDialog() async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('通用设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 启动 Tab
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启动时进入'),
                subtitle: const Text('选择打开软件时默认显示的页面'),
                trailing: DropdownButton<String>(
                  value: context.watch<SettingsProvider>().startTab,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'home', child: Text('首页')),
                    DropdownMenuItem(value: 'tests', child: Text('刷题')),
                    DropdownMenuItem(value: 'wrongbook', child: Text('错题本')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      context.read<SettingsProvider>().setStartTab(v);
                    }
                  },
                ),
              ),
              const Divider(),
              // 错题提醒开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('首页显示错题提醒'),
                subtitle: const Text('在首页顶部显示当前题库的错题数量卡片'),
                value: context.watch<SettingsProvider>().showWrongTitle,
                onChanged: (v) {
                  context.read<SettingsProvider>().setShowWrongTitle(v);
                },
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================== 通用设置 ====================
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('通用设置'),
            subtitle: Text('启动 Tab · ${settings.startTab == 'home' ? '首页' : settings.startTab == 'tests' ? '刷题' : '错题本'}，错题提醒${settings.showWrongTitle ? '开' : '关'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openGeneralSettings,
          ),

          const Divider(),

          // ==================== 主题设置 ====================
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Text(settings.themeType.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showThemeModeDialog,
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题颜色'),
            subtitle: Text(themeColorPresets[settings.themeColorIndex].label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openThemeColorSettings,
          ),

          const Divider(),

          // ==================== AI 配置 ====================
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('AI 配置'),
            subtitle: Text(settings.hasLLM ? '✅ 已配置' : '未配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAiSettings,
          ),

          const Divider(),

          // ==================== 数据管理 ====================
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

          const SizedBox(height: 24),

          // ==================== 关于 ====================
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('题库抽题器'),
            subtitle: Text('版本 1.0.0 · GPL-3.0'),
          ),
        ],
      ),
    );
  }
}
