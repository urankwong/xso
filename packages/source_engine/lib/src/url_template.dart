/// URL 模板渲染：支持 {{keyword}}（URL 编码）/ {{page}} / {{detailUrl}}（原文替换）
String renderUrlTemplate(
  String template, {
  String? keyword,
  int? page,
  String? detailUrl,
}) {
  return template.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
    final varName = m.group(1)!;
    switch (varName) {
      case 'keyword':
        if (keyword == null) throw ArgumentError('模板用了 {{keyword}} 但未提供');
        return Uri.encodeComponent(keyword);
      case 'page':
        if (page == null) throw ArgumentError('模板用了 {{page}} 但未提供');
        return page.toString();
      case 'detailUrl':
        if (detailUrl == null) throw ArgumentError('模板用了 {{detailUrl}} 但未提供');
        return detailUrl;
      default:
        throw ArgumentError('未知模板变量 {{$varName}}');
    }
  });
}
