import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_model_config.dart';

/// 设置页「AI 助手」分区：配置 OpenAI 兼容模型供应商。
/// 填入 baseUrl / apiKey / model 后即可在 AI 对话页用自然语言操控 App。
class AiConfigSection extends ConsumerStatefulWidget {
  const AiConfigSection({super.key});
  @override
  ConsumerState<AiConfigSection> createState() => _AiConfigSectionState();
}

class _AiConfigSectionState extends ConsumerState<AiConfigSection> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  bool _supportsTools = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(aiModelConfigProvider.notifier).load();
    final cfg = ref.read(aiModelConfigProvider);
    if (!mounted) return;
    _name.text = cfg.name;
    _baseUrl.text = cfg.baseUrl;
    _apiKey.text = cfg.apiKey;
    _model.text = cfg.model;
    _supportsTools = cfg.supportsTools;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(aiModelConfigProvider.notifier).save(AiModelConfig(
      name: _name.text.trim().isEmpty ? '我的模型' : _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      supportsTools: _supportsTools,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _clear() async {
    await ref.read(aiModelConfigProvider.notifier).clear();
    _name.clear();
    _baseUrl.clear();
    _apiKey.clear();
    _model.clear();
    setState(() => _supportsTools = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除配置')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(Icons.smart_toy_outlined, color: scheme.primary),
      title: const Text('AI 助手'),
      subtitle: const Text('配置模型后可在对话页用自然语言操控 App',
          style: TextStyle(fontSize: 12)),
      initiallyExpanded: false,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '显示名',
              hintText: '我的模型',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: '接口地址 (Base URL)',
              hintText: 'https://api.openai.com/v1',
              isDense: true,
              border: OutlineInputBorder(),
              helperText: '不含 /chat/completions，到 /v1 即可',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: '模型名',
              hintText: 'gpt-4o-mini',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _supportsTools,
            title: const Text('支持工具调用'),
            subtitle: const Text('关闭则纯聊天，不能操作 App', style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _supportsTools = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: _save, child: const Text('保存')),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _clear, child: const Text('清除')),
            ],
          ),
        ],
      ],
    );
  }
}