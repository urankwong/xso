import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pages/home_shell.dart';

/// 底部导航当前 tab（供跨页跳转，如空态"去导入源"）
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00897B),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: '聚合搜索',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: scheme.surface,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      home: const HomeShell(),
    );
  }
}
