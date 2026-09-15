import 'dart:convert';


import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_service.dart';
import 'ai_model_config.dart';

/// 对话阶段：UI 据此显示"思考中 / 调用工具中 / 回复中"
enum ChatStage { idle, thinking, callingTool, error }

/// 一条对话消息。role: system/user/assistant/tool。
/// assistant 携带 toolCalls 时 content 可能为空。
class ChatMessage {
  final String role;
  final String content;
  final String? toolCallId;
  final List<AiToolCall>? toolCalls;

  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toApiJson() {
    final m = <String, dynamic>{'role': role, 'content': content};
    if (toolCallId != null) m['tool_call_id'] = toolCallId;
    if (toolCalls != null) {
      m['tool_calls'] = toolCalls!
          .map((tc) => {
                'id': tc.id,
                'type': 'function',
                'function': {'name': tc.name, 'arguments': tc.arguments},
              })
          .toList();
    }
    return m;
  }
}

class AiToolCall {
  final String id;
  final String name;
  final String arguments;
  const AiToolCall({required this.id, required this.name, required this.arguments});
}

class AiChatState {
  final List<ChatMessage> messages;
  final ChatStage stage;
  final String? error;
  const AiChatState({
    this.messages = const [],
    this.stage = ChatStage.idle,
    this.error,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    ChatStage? stage,
    String? error,
  }) =>
      AiChatState(
        messages: messages ?? this.messages,
        stage: stage ?? this.stage,
        error: error,
      );
}

const _systemPrompt = '''你是汇搜 App 的 AI 助手，可以通过工具帮用户操作 App（搜歌搜书、打开书、播放歌、查最近/收藏）。

规则：
1. 用户说"打开我最近读的书"时，先调 getRecent(kind="read") 拿候选列表。若多条，把候选（序号+书名）呈现给用户让其选择，不要自作主张选一条。用户确认后，用选定项的 sourceId/sourceName/title/url 调 openBook。
2. "播放我最近听的歌"同理，kind="play"，确认后调 playTrack。
3. "打开我收藏的书"调 getFavorites(type="novel") 或 getFavorites(type="book")，多条时同样让用户确认。
4. 工具返回的是 JSON，从中取字段调用下一个工具。
5. 用简体中文回复。''';

/// 工具 schema（OpenAI function-calling 格式）
final _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'getRecent',
      'description': '获取最近阅读/播放的内容列表。kind="read"为最近阅读，kind="play"为最近播放。返回候选列表，若多条应让用户确认后再执行动作。',
      'parameters': {
        'type': 'object',
        'properties': {
          'kind': {'type': 'string', 'enum': ['read', 'play'], 'description': 'read=最近阅读，play=最近播放'},
          'limit': {'type': 'integer', 'default': 5, 'description': '返回条数'},
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'getFavorites',
      'description': '获取收藏列表。type 为源类型名（novel/book/music/audiobook/comic 等），不传则返回全部。',
      'parameters': {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'description': '源类型，如 novel/book/music'},
          'limit': {'type': 'integer', 'default': 10},
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'search',
      'description': '聚合搜索：跨源搜歌/搜书。返回 SearchResult 列表（sourceId/sourceName/type/title/url）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string', 'description': '搜索关键词'},
          'type': {'type': 'string', 'description': '源类型过滤，如 music/novel/book'},
        },
        'required': ['keyword'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'openBook',
      'description': '打开一本书：导航到详情页，阅读器会自动续读到上次位置。需要 sourceId/sourceName/title/url，从 getRecent 或 getFavorites 或 search 的结果中取。',
      'parameters': {
        'type': 'object',
        'properties': {
          'sourceId': {'type': 'string'},
          'sourceName': {'type': 'string'},
          'title': {'type': 'string'},
          'url': {'type': 'string'},
          'type': {'type': 'string', 'default': 'novel'},
        },
        'required': ['sourceId', 'sourceName', 'title', 'url'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'playTrack',
      'description': '播放一首歌：解析直链后播放。需要 sourceId/sourceName/title/url，从 getRecent(kind=play) 或 getFavorites(type=music) 或 search 的结果中取。',
      'parameters': {
        'type': 'object',
        'properties': {
          'sourceId': {'type': 'string'},
          'sourceName': {'type': 'string'},
          'title': {'type': 'string'},
          'url': {'type': 'string'},
          'artist': {'type': 'string'},
          'cover': {'type': 'string'},
        },
        'required': ['sourceId', 'sourceName', 'title', 'url'],
      },
    },
  },
];

class AiChatController extends StateNotifier<AiChatState> {
  final Ref _ref;
  AiChatController(this._ref) : super(const AiChatState());

  void clear() => state = const AiChatState();

  /// 发送一条用户消息，执行 function-calling 循环直到最终回复。
  Future<void> send(String text) async {
    final cfg = _ref.read(aiModelConfigProvider);
    if (!cfg.isConfigured) {
      state = state.copyWith(stage: ChatStage.error, error: '请先在设置中配置 AI 模型');
      return;
    }

    var msgs = <ChatMessage>[
      ...state.messages,
      ChatMessage(role: 'user', content: text),
    ];
    // 首次对话注入 system prompt
    if (!msgs.any((m) => m.role == 'system')) {
      msgs = [ChatMessage(role: 'system', content: _systemPrompt), ...msgs];
    }
    state = state.copyWith(messages: msgs, stage: ChatStage.thinking, error: null);

    try {
      // function-calling 循环，最多 5 轮防失控
      for (var round = 0; round < 5; round++) {
        final resp = await _chatCompletion(cfg, msgs);
        final assistant = _parseAssistant(resp);
        msgs = [...msgs, assistant];
        state = state.copyWith(messages: msgs);

        final calls = assistant.toolCalls;
        if (calls == null || calls.isEmpty) {
          state = state.copyWith(stage: ChatStage.idle);
          return;
        }

        // 执行所有工具调用
        state = state.copyWith(stage: ChatStage.callingTool);
        for (final tc in calls) {
          final result = await _executeTool(tc.name, tc.arguments);
          msgs = [
            ...msgs,
            ChatMessage(role: 'tool', content: result, toolCallId: tc.id),
          ];
          state = state.copyWith(messages: msgs);
        }
        state = state.copyWith(stage: ChatStage.thinking);
      }
      // 超过 5 轮仍未结束，收尾
      state = state.copyWith(stage: ChatStage.idle);
    } catch (e) {
      state = state.copyWith(stage: ChatStage.error, error: '请求失败：$e');
    }
  }

  /// 调 OpenAI 兼容 /chat/completions（非流式）
  Future<Map<String, dynamic>> _chatCompletion(
    AiModelConfig cfg,
    List<ChatMessage> msgs,
  ) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ));
    try {
      final body = <String, dynamic>{
        'model': cfg.model,
        'messages': msgs.map((m) => m.toApiJson()).toList(),
      };
      if (cfg.supportsTools) {
        body['tools'] = _tools;
        body['tool_choice'] = 'auto';
      }
      final resp = await dio.post(
        '${cfg.baseUrl}/chat/completions',
        data: body,
        options: Options(headers: {
          'Authorization': 'Bearer ${cfg.apiKey}',
          'Content-Type': 'application/json',
        }),
      );
      return resp.data is Map ? resp.data as Map<String, dynamic> : {};
    } finally {
      dio.close(force: false);
    }
  }

  /// 从响应解析 assistant 消息（含 tool_calls）
  ChatMessage _parseAssistant(Map<String, dynamic> resp) {
    final choices = resp['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      return const ChatMessage(role: 'assistant', content: '(空响应)');
    }
    final msg = (choices[0] as Map)['message'] as Map? ?? {};
    final content = (msg['content'] as String?) ?? '';
    final rawCalls = msg['tool_calls'] as List?;
    List<AiToolCall>? toolCalls;
    if (rawCalls != null && rawCalls.isNotEmpty) {
      toolCalls = rawCalls.map((tc) {
        final fn = (tc as Map)['function'] as Map;
        return AiToolCall(
          id: tc['id'] as String,
          name: fn['name'] as String,
          arguments: (fn['arguments'] as String?) ?? '{}',
        );
      }).toList();
    }
    return ChatMessage(role: 'assistant', content: content, toolCalls: toolCalls);
  }

  /// 执行一个工具调用，返回 JSON 字符串结果（喂回模型）
  Future<String> _executeTool(String name, String argsJson) async {
    final svc = _ref.read(agentServiceProvider);
    final args = jsonDecode(argsJson) as Map<String, dynamic>;
    try {
      switch (name) {
        case 'getRecent':
          final list = await svc.getRecent(
            kind: args['kind'] as String?,
            limit: (args['limit'] as num?)?.toInt() ?? 5,
          );
          return jsonEncode({
            'items': list.map((r) => {
                  'sourceId': r.sourceId,
                  'sourceName': r.sourceName,
                  'kind': r.kind,
                  'title': r.title,
                  'url': r.url,
                  'usedAt': r.usedAt.toIso8601String(),
                }).toList(),
          });

        case 'getFavorites':
          final list = await svc.getFavorites(
            type: args['type'] as String?,
            limit: (args['limit'] as num?)?.toInt() ?? 10,
          );
          return jsonEncode({
            'items': list.map((f) => {
                  'sourceId': f.sourceId,
                  'sourceName': f.sourceName,
                  'type': f.type,
                  'title': f.title,
                  'url': f.url,
                  'createdAt': f.createdAt.toIso8601String(),
                }).toList(),
          });

        case 'search':
          final list = await svc.search(
            args['keyword'] as String,
            type: args['type'] as String?,
          );
          return jsonEncode({
            'items': list.map((r) => {
                  'sourceId': r.sourceId,
                  'sourceName': r.sourceName,
                  'type': r.type.name,
                  'title': r.title,
                  'url': r.url,
                }).toList(),
          });

        case 'openBook':
          final ok = await svc.openBook(
            sourceId: args['sourceId'] as String,
            sourceName: args['sourceName'] as String,
            title: args['title'] as String,
            url: args['url'] as String,
            extractCode: args['extractCode'] as String?,
            type: (args['type'] as String?) ?? 'novel',
          );
          return jsonEncode({'success': ok});

        case 'playTrack':
          final ok = await svc.playTrack(
            sourceId: args['sourceId'] as String,
            sourceName: args['sourceName'] as String,
            title: args['title'] as String,
            url: args['url'] as String,
            artist: args['artist'] as String?,
            cover: args['cover'] as String?,
          );
          return jsonEncode({'success': ok});

        default:
          return jsonEncode({'error': '未知工具：$name'});
      }
    } catch (e) {
      return jsonEncode({'error': '$e'});
    }
  }
}

final aiChatProvider =
    StateNotifierProvider<AiChatController, AiChatState>(
        (ref) => AiChatController(ref));