import 'dart:io';
import 'package:source_engine/source_engine.dart';

void main() {
  final html = File('test/fixtures/tpb_search.html').readAsStringSync();
  final rows = interpretHtml(html, container: '#searchResult tr', fields: {
    'title': const FieldRule(selector: 'a[title^="Details for"]'),
    'url': const FieldRule(selector: 'a[href^="magnet"]', attr: 'href'),
    'size': const FieldRule(selector: 'td[align="right"]'),
  });
  final good = rows.where((r) => (r['url'] ?? '').startsWith('magnet:')).toList();
  print('total=${rows.length} good=${good.length}');
  for (final r in good.take(3)) {
    final t = r['title'] ?? '(null)';
    print('  ${t.substring(0, t.length < 45 ? t.length : 45)}');
    print('    size=${r['size']?.replaceAll('\u00a0', ' ')} url_ok=${(r['url'] ?? '').startsWith('magnet:?xt=urn:btih:')}');
  }
}
