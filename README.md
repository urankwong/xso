# 汇搜 · xso

一个跨来源的**聚合搜索 App**：音乐 / 书籍 / 磁力 / 网盘多品类统一搜索、播放、下载与收藏。App 本体遵循「空壳原则」，不绑定任何特定站点——通过**导入源规则**扩展能力，并**原生兼容 [Legado 简单书源](https://github.com/gedoor/legado)、[洛雪音乐助手 (lx-music) 音源](https://github.com/lyswhut/lx-music-mobile)、[MusicFree 插件](https://github.com/maotoumao/MusicFree)** 三种主流第三方源格式。

技术栈：Flutter + Riverpod + QuickJS（在 Dart 侧沙箱内运行源脚本的 JS 钩子）。

## 源格式兼容

xso 内置一个源引擎，可按不同协议加载源，也可自行编写 JSON/JS 源。目前兼容：

| 格式 | 对应生态 | 承载品类 | 导入方式 |
|---|---|---|---|
| **Legado 简单书源** | [gedoor/legado](https://github.com/gedoor/legado) | 小说 / 有声书 | 粘贴书源 JSON（`bookSourceName` / `ruleSearch` / `ruleBookInfo` / `ruleToc` / `ruleContent` 等字段），支持 `searchUrl` 变量与规则解释器 |
| **洛雪音源 (lx)** | [lyswhut/lx-music](https://github.com/lyswhut/lx-music-desktop) | 在线音乐 | 导入 `.js` 音源脚本（`registerSource` / 在线搜索 / 获取音址 `musicUrl` + `headers`），支持 128k/320k/flac 档位 |
| **MusicFree 插件** | [maotoumao/MusicFree](https://github.com/maotoumao/MusicFree) | 音乐 / 歌单 / 专辑 / MV / 有声 | 导入 `.js` 插件（`search` / `getMusicInfo` / `getAlbumInfo` / `getMediaSource` 等 action，`axios` / `env` 宿主桥） |
| **xso 自有 JSON 源** | 本项目 | 磁力 / 网盘 / 网页型 | CSS 选择器 / JSONPath 规则 + 可选 `buildRequest`/`parse` JS 钩子，两段式详情提取 |

> 三种第三方格式的源脚本在 QuickJS 沙箱内执行，网络请求统一由 Dart `dio` 代理，脚本无法越过白名单访问系统资源。

## 内置源（开箱可导入）

首次启动自动导入一批社区/公开规则的源，作为可直接试用的种子，也可随时在「源管理」页删除或替换：

- **洛雪音源 8 个**、**MusicFree 插件 21 个**（网易云 / QQ / 酷狗 / 酷我 / 咪咕 / B 站 / 喜马拉雅 / 苹果 iTunes 等）
- **Legado 书源 13 个**（含 libgen 等英文书直链下载源）
- **磁力源 47 个**、**网盘聚合源 40 个**（公开 BT/磁力搜索引擎 + 网盘搜索站）

站点改版导致失效是常态。任一源失效时，可在「源管理」页删除后导入社区最新规则，或用内置**源调试器**自行校准。

## 功能

- **聚合搜索**：多源并发、流式出结果，按类型（音乐/小说/磁力/网盘）筛选，来源健康度可视化
- **播放**：App 内音乐播放（just_audio），后台播放、歌词（内联歌词 + lrclib 回退）、跨源换源兜底、洛雪音址档位切换
- **下载**：磁力/网盘/音频/视频（B 站 MV 带 Referer）下载，ID3 写标签
- **收藏与历史**：按类型分类收藏 + 批量活性检测失效标红，搜索历史一键回搜
- **局域网助手**：内置 LAN 服务，从浏览器批量粘贴/导入源
- **账号态**：按源命名空间持久化 cookie / 用户变量，支持需登录的平台

## 结构

```
app/                    # Flutter 壳工程（UI、Riverpod、QuickJS 运行时注入、播放/下载/源管理页）
packages/core/          # 纯 Dart：结果模型、Action、Orchestrator、网盘识别、活性检测、DHT
packages/source_engine/ # 纯 Dart：源 schema、规则解释器、JS 沙箱抽象、Legado/洛雪/MusicFree 适配器
packages/data/          # 纯 Dart：drift 数据库（收藏/历史）、源文件仓库
docs/                   # 设计与各模块方案、测试报告
tools/                  # 内置源生成 / 打包脚本
```

## 构建

需要 Flutter 3.x（Dart 3.5+）。国内网络建议先设镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

```bash
cd app && flutter pub get && flutter run
```

三个纯 Dart package 使用 path 依赖，无需 melos bootstrap 也可直接构建。运行含 QuickJS 的测试时需保证 `quickjs_c_bridge.dll`（或对应平台的桥接库）在运行环境可加载。

## 测试

```bash
cd packages/core && dart test
cd packages/source_engine && dart test
cd packages/data && dart test
cd app && flutter test
```

## 使用流程

1. 首次启动自动导入内置源，也可在「源」页右上角重新导入，或导入自己的 Legado / 洛雪 / MusicFree 源
2. 「源」页点任一源进入**源调试器**，输入关键词试搜，逐步查看结果与错误，用于校准规则
3. 「搜索」页输入关键词 → 各源并发搜索、流式出结果（复制 / 打开 / 播放 / 下载 / 收藏）
4. 「收藏」页按类型筛选、批量活性检测；「历史」页点击关键词回搜

## 免责声明

本项目仅为**技术研究与个人学习**用途的聚合搜索空壳工具，不内置、不存储、不传播任何第三方站点的内容与源规则；源脚本的可用性、合法性由源提供者与使用者自行承担。请勿用于任何侵犯版权或违反所在地法律法规的用途。

## License

[MIT](LICENSE)
