import 'dart:io';
import 'package:source_engine/source_engine.dart';

void main() {
  final html = File('test/fixtures/knaben_search.html').readAsStringSync();
  for (final container in ['tr[data-id]', 'tr.border-start', 'tbody tr']) {
    final rows = interpretHtml(html, container: container, fields: {
      'title': const FieldRule(selector: 'td.text-wrap > a'),
      'url': const FieldRule(selector: 'td.text-wrap > a', attr: 'href'),
      'size': const FieldRule(selector: 'td[title*="Bytes"]'),
      'date': const FieldRule(selector: 'td[title*=":"]'),
    });
    print('$container -> ${rows.length} rows');
    if (rows.isNotEmpty) {
      for (final r in rows.take(3)) {
        final t = r['title'] ?? '';
        print('  title=${t.substring(0, t.length < 50 ? t.length : 50)}');
        print('  url=${r['url']?.substring(0, 40)}...');
        print('  size=${r['size']} date=${r['date']}');
      }
      break;
    }
  }
}
