# 聚合搜索 App

网盘 / 磁力 / ed2k 聚合搜索**空壳**。App 本体不内置任何搜索源——导入源脚本（JSON 规则 + JS 钩子）后使用，兼容 MusicFree 插件 / 洛雪音乐源 / Legado 简单书源导入。

设计文档见 `docs/superpowers/specs/`，实施计划见 `docs/superpowers/plans/`。

## 结构

```
app/                    # Flutter 壳工程（UI、Riverpod、QuickJS 运行时注入）
packages/core/          # 纯 Dart：结果模型、Action、Orchestrator、网盘识别、活性检测
packages/source_engine/ # 纯 Dart：源 schema、规则解释器、JS 沙箱抽象、格式适配器
packages/data/          # 纯 Dart：drift 数据库（收藏/历史）、源文件仓库
```

## 构建

需要 Flutter 3.x（Dart 3.5+）。国内网络建议先设置：

```
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

```
cd app && flutter pub get && flutter run
```

（三个纯 Dart package 使用 path 依赖，无需 melos bootstrap 也可直接构建；`melos.yaml` 已备好，装了 melos 的可 `dart pub global activate melos && melos bootstrap`。）

## 使用流程

1. 首次启动会自动导入 3 个**内置示例源**（磁力 HTML 源 / 两段式网盘资源站源 / 磁力 JSON API 源），也可在「源」页点右上角重新导入
2. 「源」页点任一源进入**源调试器**，输入关键词试搜，能看到每步结果与错误——用于校准真实站点规则
3. 回「搜索」页输入关键词 → 各源并发搜索、流式出结果（复制/打开/收藏）
4. 「收藏」页可批量活性检测，失效标红；「历史」页点击关键词回搜

> **关于内置源**：App 遵循"空壳原则"，内置源是格式示例/模板，指向的演示域名不保证可用（站点改版是常态）。要获得真实可用的源：按 `assets/sources/` 里的模板改写目标站点的选择器，或从社区获取别人维护的源文件（自有 JSON 格式 / MusicFree / 洛雪 / Legado 简单书源），剪贴板导入即可。

## 测试

```
cd packages/core && dart test
cd packages/source_engine && dart test
cd packages/data && dart test
cd app && flutter test
```

## 第一期范围

- 自有 JSON 源：CSS 选择器 / JSONPath / JS 钩子（buildRequest/parse），两段式详情提取网盘链接+提取码
- 内置网盘识别器：百度/夸克/阿里/123/迅雷链接 + 提取码 + 失效特征
- JS 沙箱：QuickJS，超时强制终止，API 白名单，网络全部由 Dart dio 代理
- 预留：原生源（KAD/DHT）、download/push Action、iOS/桌面端
