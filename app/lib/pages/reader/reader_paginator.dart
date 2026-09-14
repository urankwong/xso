import 'package:flutter/material.dart';

/// 一页内的可见片段：第 [paragraphIndex] 段的这段文本
class ReaderPageFragment {
  final int paragraphIndex;
  final String text;
  const ReaderPageFragment(this.paragraphIndex, this.text);
}

/// 一页 = 若干段落片段（按文档序）。
/// 注意与 reader_page.dart 的 ReaderPage widget 重名，故取此名。
typedef ReaderPageContent = List<ReaderPageFragment>;

/// TextPainter 排版分页器：把章节文本按画布尺寸切成左右翻页的页。
///
/// 算法：逐段贪心装页——整段测高放得下就整段放入；放不下时对段内文本
/// 做"最大可容纳字符数"二分（TextPainter 逐长度测高），把段拆成页内
/// 头部与页间尾部。
///
/// **一致性约束**：渲染端必须用与测量端完全相同的样式/宽度，否则
/// 分页结果与实际渲染漂移（页尾溢出或留白）。段首缩进以全角空格
/// 前缀并入测量文本，保证缩进行为一致。
class ReaderPaginator {
  /// 中文段首两字符缩进
  static const indent = '　　';

  static List<String> splitParagraphs(String content) => content
      .split(RegExp(r'\n+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static List<ReaderPageContent> paginate({
    required String content,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final paragraphs = splitParagraphs(content);
    final pages = <ReaderPageContent>[];
    if (paragraphs.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return [
        [for (var i = 0; i < paragraphs.length; i++) ReaderPageFragment(i, indent + paragraphs[i])]
      ];
    }

    var currentPage = <ReaderPageFragment>[];
    var remaining = maxHeight;

    void flush() {
      if (currentPage.isNotEmpty) pages.add(currentPage);
      currentPage = <ReaderPageFragment>[];
      remaining = maxHeight;
    }

    double heightOf(String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection,
      )..layout(maxWidth: maxWidth);
      final h = tp.height;
      tp.dispose();
      return h;
    }

    /// 二分求"高度不超过 budget 的最大前缀长度"
    int fitLength(String text, double budget) {
      // 快速出口：全段放得下
      if (heightOf(text) <= budget) return text.length;
      var lo = 0;
      var hi = text.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (heightOf(text.substring(0, mid)) <= budget) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      // 避免在行首/行尾切出孤立字符：向前吸掉空白
      while (lo > 0 && _isBreakableSpace(text, lo - 1)) {
        lo--;
      }
      return lo < 0 ? 0 : lo;
    }

    for (var pi = 0; pi < paragraphs.length; pi++) {
      var rest = indent + paragraphs[pi];
      while (rest.isNotEmpty) {
        final len = fitLength(rest, remaining);
        if (len <= 0) {
          // 当前页连一个字符都放不下 → 换页
          flush();
          continue;
        }
        currentPage.add(ReaderPageFragment(pi, rest.substring(0, len)));
        remaining -= heightOf(rest.substring(0, len));
        rest = rest.substring(len);
        if (rest.isNotEmpty && remaining <= 0) flush();
      }
    }
    flush();
    return pages.isEmpty ? [<ReaderPageFragment>[]] : pages;
  }

  static bool _isBreakableSpace(String text, int index) {
    final c = text.codeUnitAt(index);
    // 空格 / 全角空格
    return c == 0x20 || c == 0x3000;
  }
}