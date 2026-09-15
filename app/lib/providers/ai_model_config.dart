import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 模型供应商配置：用户自填 OpenAI 兼容接口信息。
/// 不锁定厂商，baseUrl + apiKey + model 三件套即可接入任意兼容服务。
class AiModelConfig {
  /// 显示名（如「我的 GPT」），纯 UI 用
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 是否支持 function/tool-calling。不支持时对话层降级为纯文本，
  /// 不调用工具（用户只能聊天，不能让 AI 操作 App）。
  final bool supportsTools;

  const AiModelConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.supportsTools = true,
  });

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  factory AiModelConfig.empty() => const AiModelConfig(
        name: '',
        baseUrl: '',
        apiKey: '',
        model: '',
      );

  AiModelConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? supportsTools,
  }) =>
      AiModelConfig(
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        supportsTools: supportsTools ?? this.supportsTools,
      );
}

/// 模型配置持久化：SharedPreferences 存 baseUrl/apiKey/model/name/supportsTools。
/// apiKey 明文存 SP（与项目其他配置一致）；后续可升级为加密存储。
class AiModelConfigNotifier extends StateNotifier<AiModelConfig> {
  AiModelConfigNotifier() : super(AiModelConfig.empty());

  static const _kName = 'ai.model.name';
  static const _kBaseUrl = 'ai.model.baseUrl';
  static const _kApiKey = 'ai.model.apiKey';
  static const _kModel = 'ai.model.model';
  static const _kSupportsTools = 'ai.model.supportsTools';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = AiModelConfig(
      name: p.getString(_kName) ?? '',
      baseUrl: p.getString(_kBaseUrl) ?? '',
      apiKey: p.getString(_kApiKey) ?? '',
      model: p.getString(_kModel) ?? '',
      supportsTools: p.getBool(_kSupportsTools) ?? true,
    );
  }

  Future<void> save(AiModelConfig cfg) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, cfg.name);
    await p.setString(_kBaseUrl, cfg.baseUrl);
    await p.setString(_kApiKey, cfg.apiKey);
    await p.setString(_kModel, cfg.model);
    await p.setBool(_kSupportsTools, cfg.supportsTools);
    state = cfg;
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kName);
    await p.remove(_kBaseUrl);
    await p.remove(_kApiKey);
    await p.remove(_kModel);
    await p.remove(_kSupportsTools);
    state = AiModelConfig.empty();
  }
}

final aiModelConfigProvider =
    StateNotifierProvider<AiModelConfigNotifier, AiModelConfig>(
        (ref) => AiModelConfigNotifier());