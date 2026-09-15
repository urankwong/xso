import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_chat_provider.dart';
import '../providers/ai_model_config.dart';
import 'settings_page.dart';

/// AI 对话页：用户用自然语言操控 App（搜歌搜书、打开最近读的书、播放最近听的歌…）。
///
/// 依赖设置页配置的 AI 模型（OpenAI 兼容）。未配置时引导去设置。
/// 工具调用过程对用户可见（"正在执行操作…"），让 AI 行为可学习、可信任。
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});
  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    ref.read(aiChatProvider.notifier).send(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiModelConfigProvider);
    final state = ref.watch(aiChatProvider);
    final scheme = Theme.of(context).colorScheme;

    if (!cfg.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 助手')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 64, color: scheme.outline),
                const SizedBox(height: 16),
                const Text('还未配置 AI 模型', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                const Text('填入 OpenAI 兼容的接口信息即可用自然语言操控 App',
                    style: TextStyle(fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsPage())),
                  icon: const Icon(Icons.settings),
                  label: const Text('去设置'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          IconButton(
            onPressed: () => ref.read(aiChatProvider.notifier).clear(),
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空对话',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: state.messages.length,
              itemBuilder: (context, i) {
                final m = state.messages[i];
                if (m.role == 'system') return const SizedBox.shrink();
                if (m.role == 'tool') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('✓ 已执行操作',
                          style: TextStyle(
                              fontSize: 11, color: scheme.outline)),
                    ),
                  );
                }
                final isUser = m.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m.content.isEmpty && m.toolCalls != null
                          ? '正在调用工具…'
                          : m.content,
                      style: TextStyle(
                          color: isUser
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface),
                    ),
                  ),
                );
              },
            ),
          ),
          if (state.stage == ChatStage.thinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('AI 思考中…', style: TextStyle(fontSize: 12)),
            ),
          if (state.stage == ChatStage.callingTool)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('正在执行操作…', style: TextStyle(fontSize: 12)),
            ),
          if (state.stage == ChatStage.error && state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(state.error!,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '打开我最近读的书…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: state.stage != ChatStage.idle ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}