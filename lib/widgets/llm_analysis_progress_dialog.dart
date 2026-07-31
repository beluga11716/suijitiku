import 'package:flutter/material.dart';
import '../ai/llm_client.dart';
import '../ai/llm_analysis_service.dart';

/// LLM 分析进度 Dialog
///
/// StatefulWidget：在 initState → addPostFrameCallback 中启动分析，
/// 通过 setState 更新进度。完成后自动关闭。
class LlmAnalysisProgressDialog extends StatefulWidget {
  final String bankId;
  final String bankName;
  final LlmClient client;
  final String prompt;

  const LlmAnalysisProgressDialog({
    super.key,
    required this.bankId,
    required this.bankName,
    required this.client,
    required this.prompt,
  });

  @override
  State<LlmAnalysisProgressDialog> createState() =>
      _LlmAnalysisProgressDialogState();
}

class _LlmAnalysisProgressDialogState
    extends State<LlmAnalysisProgressDialog> {
  bool _isAnalyzing = true;
  bool _isCancelled = false;
  int _completed = 0;
  int _total = 0;
  String? _error;
  int _selectedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAnalysis());
  }

  Future<void> _startAnalysis() async {
    try {
      final service = LlmAnalysisService();
      _selectedCount = await service.analyzeBank(
        bankId: widget.bankId,
        client: widget.client,
        prompt: widget.prompt,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _completed = completed;
              _total = total;
            });
          }
        },
        isCancelled: () => _isCancelled,
      );
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
      // Auto-close after short delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isAnalyzing ? 'LLM 分析中' : (_error != null ? '分析失败' : '分析完成')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.bankName, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          if (_isAnalyzing) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('已完成 $_completed / $_total 批次'),
            if (_total > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _completed / _total,
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => _isCancelled = true),
              icon: const Icon(Icons.cancel, size: 18),
              label: const Text('取消'),
            ),
          ] else if (_error != null) ...[
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text('分析失败',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: Colors.red)),
            const SizedBox(height: 4),
            Text(_error!,
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ] else ...[
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 48),
            const SizedBox(height: 8),
            Text('LLM 分析完成！'),
            const SizedBox(height: 4),
            Text('选中 $_selectedCount 道题',
                style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
