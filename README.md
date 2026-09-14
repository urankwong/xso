# 汇搜 · xso

中文 · [English](#english)

一个跨来源的**聚合搜索 App**：音乐 / 书籍 / 磁力 / 网盘多品类统一搜索、播放、下载与收藏。App 本体遵循「空壳原则」，不绑定任何特定站点——通过**导入源规则**扩展能力，并**原生兼容 [Legado 简单书源](https://github.com/gedoor/legado)、[洛雪音乐助手 (lx-music) 音源](https://github.com/lyswhut/lx-music-mobile)、[MusicFree 插件](https://github.com/maotoumao/MusicFree)** 三种主流第三方源格式。

技术栈：Flutter + Riverpod + QuickJS（在 Dart 侧沙箱内运行源脚本的 JS 钩子）。

## English

**xso (汇搜)** is a Flutter-based **aggregator search app** for music, novels, torrents and cloud-drive links — unified search, playback, download and favorites. It follows an *empty-shell* principle: it binds to no specific site and is fully source-driven, natively compatible with **[Legado](https://github.com/gedoor/legado) book sources**, **[lx-music](https://github.com/lyswhut/lx-music-desktop) sources** and **[MusicFree](https://github.com/maotoumao/MusicFree) plugins** — bring your own sources.

Built with Flutter + Riverpod + QuickJS (source JS hooks run in a Dart-side sandbox). See the sections below for supported source formats, features and build steps.

## 源格式兼容

xso 内置一个源引擎，可按不同协议加载源，也可自行编写 JSON/JS 源。目前兼容：

| 格式 | 对应生态 | 承载品类 | 导入方式 |
|---|---|---|---|
| **Legado 简单书源** | [gedoor/legado](https://github.com/gedoor/legado) | 小说 / 有声书 | 粘贴书源 JSON（`bookSourceName` / `ruleSearch` / `ruleBookInfo` / `ruleToc` / `ruleContent` 等字段），支持 `searchUrl` 变量与规则解释器 |
| **洛雪音源 (lx)** | [lyswhut/lx-music](https://github.com/lyswhut/lx-music-desktop) | 在线音乐 | 导入 `.js` 音源脚本（`registerSource` / 在线搜索 / 获取音址 `musicUrl` + `headers`），支持 128k/320k/flac 档位 |
| **MusicFree 插件** | [maotoumao/MusicFree](https://github.com/maotoumao/MusicFree) | 音乐 / 歌单 / 专辑 / MV / 有声 | 导入 `.js` 插件（`search` / `getMusicInfo` / `getAlbumInfo` / `getMediaSource` 等 action，`axios` / `env` 宿主桥） |
| **xso 自有 JSON 源** | 本项目 | 磁力 / 网盘 / 网页型 | CSS 选择器 / JSONPath 规则 + 可选 `buildRequest`/`parse` JS 钩子，两段式详情提取 |

> 三种第三方格式的源脚本在 QuickJS 沙箱内执行，网络请求统一由 Dart `dio` 代理，脚本无法越过白名单访问系统资源。
>
> 站点改版导致源失效是常态，可在「源管理」页删除后重新导入社区最新规则，或用**源调试器**自行校准。

## 功能

- **聚合搜索**：多源并发、流式出结果，按类型（音乐/小说/磁力/网盘）筛选，来源健康度可视化
- **播放**：App 内音乐播放（just_audio），后台播放、歌词（内联歌词 + lrclib 回退）、跨源换源兜底、洛雪音址档位切换
- **下载**：磁力/网盘/音频/视频（B 站 MV 带 Referer）下载，ID3 写标签
- **收藏与历史**：按类型分类收藏 + 批量活性检测失效标红，搜索历史一键回搜
- **局域网助手**：内置 LAN 服务，从浏览器批量粘贴/导入源
- **账号态**：按源命名空间持久化 cookie / 用户变量，支持需登录的平台
- **应用内更新**：从 GitHub Releases 检查新版本，App 内下载 APK 并唤起系统安装器；直连失败自动改用加速镜像，也可复制直链交给浏览器手动下载

## 结构

```
app/                    # Flutter 壳工程（UI、Riverpod、QuickJS 运行时注入、播放/下载/源管理页）
packages/core/          # 纯 Dart：结果模型、Action、Orchestrator、网盘识别、活性检测、DHT
packages/source_engine/ # 纯 Dart：源 schema、规则解释器、JS 沙箱抽象、Legado/洛雪/MusicFree 适配器
packages/data/          # 纯 Dart：drift 数据库（收藏/历史）、源文件仓库
docs/                   # 设计与各模块方案、测试报告
tools/                  # 源生成 / 打包脚本
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

## 发布与更新

推 `v*` tag 即由 GitHub Actions（`.github/workflows/build.yml`）构建 `app-debug.apk` 与分架构 release 包，并自动挂到该版本的 Releases 页面。

App 侧的「设置 → 检查更新」读取 `releases/latest`，按 `版本号+构建号` 比较（如 `v0.1.0+6`）：

- 启动时每天最多静默检查一次，可「跳过此版本」后不再提示
- 按设备 ABI 自动选包（拿不到架构时默认 `arm64-v8a`），下载进度可视、可取消
- 直连 GitHub 失败会自动依次尝试公共加速镜像前缀；仍失败时可复制直链交给浏览器下载
- 未认证的 GitHub API 限流约 60 次/小时/IP，故静默检查有节流；安装需在系统弹窗中允许「安装未知应用」

## 测试

```bash
cd packages/core && dart test
cd packages/source_engine && dart test
cd packages/data && dart test
cd app && flutter test
```

## 使用流程

1. 在「源」页导入你自己的 Legado / 洛雪 / MusicFree 源或 xso JSON 源（支持单个粘贴或批量导入）
2. 「源」页点任一源进入**源调试器**，输入关键词试搜，逐步查看结果与错误，用于校准规则
3. 「搜索」页输入关键词 → 各源并发搜索、流式出结果（复制 / 打开 / 播放 / 下载 / 收藏）
4. 「收藏」页按类型筛选、批量活性检测；「历史」页点击关键词回搜

## 免责声明

本项目仅为**技术研究与个人学习**用途的聚合搜索空壳工具，不内置、不存储、不传播任何第三方站点的内容与源规则；源脚本的可用性、合法性由源提供者与使用者自行承担。请勿用于任何侵犯版权或违反所在地法律法规的用途。

## License

本项目以 **GNU AGPL-3.0**（Affero General Public License v3.0）授权，完整条款见 [LICENSE](LICENSE)。

- 分发、或以网络服务形式提供本程序的衍生版本，均须以相同的 AGPL-3.0 许可公开其完整源代码。
- 通过 QuickJS 沙箱动态加载的第三方源脚本（Legado / 洛雪 / MusicFree 等）作为独立数据使用，其许可由源提供者自行决定，不因本项目而被传染。
