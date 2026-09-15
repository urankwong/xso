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
    /// 首段判定为章节标题时使用的样式。
    ///
    /// 必须传：标题的渲染样式与正文不同（字号更大、上下有留白），
    /// 若测量时仍按正文样式算高度，实际渲染就会比测量值高，
    /// 直接违反本类顶部那条"测量与渲染必须一致"的约束，导致页尾溢出。
    TextStyle? headingStyle,
    /// 判定首段是否为章节标题（由调用方提供，分页器不关心书的目录结构）
    bool Function(String paragraph)? isHeading,
    /// 标题渲染时额外占用的上下留白总高度。
    ///
    /// 渲染端给标题套了 Padding（居中标题需要呼吸感），这段高度**不在
    /// TextPainter 的测量结果里** —— 不计入就一定会溢出（实测 18px 的
    /// 留白直接把首页顶出 39px）。
    double headingSpacing = 0,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final paragraphs = splitParagraphs(content);
    final pages = <ReaderPageContent>[];

    // 首段是否按标题排版：三条都成立才算（调用方给了标题样式与判定函数，
    // 且判定函数认可首段）。不成立时行为与改造前完全一致。
    final firstIsHeading = headingStyle != null &&
        isHeading != null &&
        paragraphs.isNotEmpty &&
        isHeading(paragraphs[0]);
    // 用可空的中间变量，避免 Dart 在闭包里跨变量推断造成的 `!` 告警
    final heading = firstIsHeading ? headingStyle : null;
    TextStyle styleAt(int pi) => (pi == 0 && heading != null) ? heading : style;

    if (paragraphs.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return [
        [
          for (var i = 0; i < paragraphs.length; i++)
            ReaderPageFragment(
                i, (i == 0 && firstIsHeading) ? paragraphs[i] : indent + paragraphs[i])
        ]
      ];
    }

    var currentPage = <ReaderPageFragment>[];
    var remaining = maxHeight;
    // 首页含标题时，先把标题的上下留白从预算里扣掉
    if (firstIsHeading && headingSpacing > 0) remaining -= headingSpacing;

    void flush() {
      if (currentPage.isNotEmpty) pages.add(currentPage);
      currentPage = <ReaderPageFragment>[];
      remaining = maxHeight;
    }

    double heightOf(String text, TextStyle st) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: st),
        textDirection: textDirection,
      )..layout(maxWidth: maxWidth);
      final h = tp.height;
      tp.dispose();
      return h;
    }

    /// 二分求"高度不超过 budget 的最大前缀长度"
    int fitLength(String text, double budget, TextStyle st) {
      // 快速出口：全段放得下
      if (heightOf(text, st) <= budget) return text.length;
      var lo = 0;
      var hi = text.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (heightOf(text.substring(0, mid), st) <= budget) {
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
      final st = styleAt(pi);
      // 标题不加段首缩进（渲染端是居中显示，缩进只会造成测量/渲染不一致）
      var rest = (pi == 0 && firstIsHeading) ? paragraphs[pi] : indent + paragraphs[pi];
      while (rest.isNotEmpty) {
        final len = fitLength(rest, remaining, st);
        if (len <= 0) {
          // 当前页连一个字符都放不下 → 换页
          flush();
          continue;
        }
        currentPage.add(ReaderPageFragment(pi, rest.substring(0, len)));
        remaining -= heightOf(rest.substring(0, len), st);
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