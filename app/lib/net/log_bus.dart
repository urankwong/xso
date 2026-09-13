import 'dart:async';

/// 日志级别
enum LogLevel { info, warn, error }

/// 一条运行日志
class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag; // 来源模块：search / download / source / lan ...
  final String message;

  LogEntry(this.time, this.level, this.tag, this.message);

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
      };
}

/// 全局日志总线：环形缓冲（上限 500 条）+ 广播流，供局域网 SSE 推送与调试。
/// 采用进程级单例，任何模块 `logBus.add(...)` 即可埋点，无需持有 Ref。
class LogBus {
  LogBus._();
  static final LogBus instance = LogBus._();

  static const int _capacity = 500;
  final List<LogEntry> _buf = <LogEntry>[];
  final StreamController<LogEntry> _ctrl =
      StreamController<LogEntry>.broadcast();

  /// 当前缓冲快照（旧 → 新）
  List<LogEntry> get snapshot => List.unmodifiable(_buf);

  /// 追加一条日志（超出容量自动丢弃最旧）
  void add(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _buf.add(entry);
    if (_buf.length > _capacity) {
      _buf.removeAt(0);
    }
    if (!_ctrl.isClosed) _ctrl.add(entry);
  }

  void info(String tag, String message) => add(LogLevel.info, tag, message);
  void warn(String tag, String message) => add(LogLevel.warn, tag, message);
  void error(String tag, String message) => add(LogLevel.error, tag, message);

  /// 订阅实时日志流（供 SSE / 调试页使用）
  Stream<LogEntry> watch() => _ctrl.stream;

  /// 清空缓冲（调试用途）
  void clear() => _buf.clear();
}

/// 便捷全局访问器
final logBus = LogBus.instance;
