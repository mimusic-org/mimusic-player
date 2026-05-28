# Songloft Flutter

[![Build and Release](https://github.com/songloft-org/songloft-player/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/songloft-org/songloft-player/actions/workflows/build-and-release.yml)
[![GitHub License](https://img.shields.io/github/license/songloft-org/songloft-player)](https://github.com/songloft-org/songloft-player)
[![GitHub Release](https://img.shields.io/github/v/release/songloft-org/songloft-player)](https://github.com/songloft-org/songloft-player/releases)
[![Stars](https://img.shields.io/github/stars/songloft-org/songloft-player)](https://github.com/songloft-org/songloft-player/stargazers)

<p align="center">
  <strong>🎵 Songloft 跨平台音乐播放器 — 基于 Flutter 构建</strong>
</p>

Songloft 跨平台音乐播放器，基于 Flutter 构建，支持 iOS、Android、macOS、Windows、Linux、Web 六端。

<p align="center">
  <a href="https://github.com/songloft-org/songloft-player">🏠 GitHub</a> •
  <a href="https://github.com/songloft-org/songloft-player/releases">📥 下载</a> •
  <a href="https://github.com/songloft-org/songloft-player/issues">💬 问题反馈</a>
</p>

## 截图

https://github.com/songloft-org/songloft/issues/6

## 下载安装

从 [GitHub Releases](https://github.com/songloft-org/songloft-player/releases/latest) 下载最新版本：

| 平台 | 下载链接 | 说明 |
|------|----------|------|
| 🌐 **Web (standalone)** | [songloft-web-standalone.tar.gz](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-web-standalone.tar.gz) | 独立部署版，支持配置后端地址 |
| 🌐 **Web (embedded)** | [songloft-web-embedded.tar.gz](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-web-embedded.tar.gz) | 嵌入 Go 后端同域部署 |
| 🐧 **Linux** | [songloft-linux-x64.tar.gz](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-linux-x64.tar.gz) | x64 桌面版 |
| | [songloft-linux-x64.deb](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-linux-x64.deb) | Debian/Ubuntu x64 |
| | [songloft-linux-x64.rpm](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-linux-x64.rpm) | Fedora/RHEL/CentOS x64 |
| | [songloft-linux-x64.AppImage](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-linux-x64.AppImage) | 免安装可执行文件 |
| 🪟 **Windows** | [songloft-windows-x64.zip](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-windows-x64.zip) | x64 便携版 |
| | [songloft-windows-x64.msix](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-windows-x64.msix) | x64 安装版 |
| 🍎 **macOS** | [songloft-macos.dmg](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-macos.dmg) | Universal DMG (Intel/Apple Silicon) |
| | [songloft-macos.zip](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-macos.zip) | Universal App 压缩包 |
| 🤖 **Android** | [songloft-arm64-v8a.apk](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-arm64-v8a.apk) | ARM64 设备（推荐） |
| | [songloft-armeabi-v7a.apk](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-armeabi-v7a.apk) | ARMv7 设备 |
| | [songloft-x86_64.apk](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-x86_64.apk) | x86_64 模拟器/设备 |
| 📱 **iOS** | [songloft-ios-nosign.ipa](https://github.com/songloft-org/songloft-player/releases/latest/download/songloft-ios-nosign.ipa) | 未签名 IPA，可通过 AltStore/Sideloadly 安装 |

> 开发版可在 [main 分支 Release](https://github.com/songloft-org/songloft-player/releases/tag/main) 获取。

## 功能特性

- **跨平台支持**: iOS、Android（手机/平板/TV）、macOS、Windows、Linux、Web
- **响应式布局**: 4 级断点自适应（Mobile < 600px, Tablet 600-900px, Desktop 900-1920px, TV 1920px+）
- **自适应导航**: 手机底栏、平板侧栏、桌面侧边菜单、TV 顶部 Tab
- **音乐播放**: 基于 just_audio，支持本地和网络歌曲，后台播放
- **歌单管理**: 创建、编辑、删除歌单，添加/移除歌曲
- **歌曲库**: 分页加载、搜索过滤、歌曲编辑
- **主题切换**: 亮色/暗色/跟随系统
- **JWT 认证**: 双 Token 机制，安全存储（自动降级）
- **TV 适配**: D-Pad 焦点导航，大按钮/大字体

## 环境要求

- Flutter >= 3.29.0
- Dart SDK >= 3.7.0

## 快速开始

```bash
# 安装依赖
flutter pub get

# 运行（自动选择已连接设备）
flutter run

# 指定平台运行
flutter run -d chrome --no-web-resources-cdn  # Web（standalone 模式）
flutter run -d macos                          # macOS
flutter run -d "iPhone 16 Pro"                # iOS 模拟器
flutter run -d <device-id>                    # Android 设备
```

## 构建

```bash
# 各平台构建
flutter build web --no-web-resources-cdn                                       # Web (standalone)
flutter build web --no-web-resources-cdn --dart-define=DEPLOY_MODE=embedded    # Web (嵌入模式)
flutter build apk --split-per-abi                                              # Android APK
flutter build ios --no-codesign                                                # iOS
flutter build macos                                                            # macOS
flutter build linux                                                            # Linux
flutter build windows                                                          # Windows

# 使用构建脚本（支持并行构建所有平台）
./scripts/build-frontend.sh web           # 构建单个平台
./scripts/build-frontend.sh all           # 构建所有平台
```

详细构建说明参见 [BUILD_FRONTEND_GUIDE.md](BUILD_FRONTEND_GUIDE.md)。

## CI/CD

本仓库通过 GitHub Actions 自动构建和发布：

- **推送 `v*` tag** → 自动构建所有平台并创建正式 Release
- **手动触发** → 构建并发布到分支名对应的 Release（如 `main`）

工作流文件：[`.github/workflows/build-and-release.yml`](.github/workflows/build-and-release.yml)

## 项目结构

```
lib/
├── config/          # 应用配置（API 地址、常量）
├── core/            # 核心层
│   ├── audio/       # 音频播放服务
│   ├── network/     # HTTP 客户端、认证拦截器
│   ├── router/      # GoRouter 路由配置
│   ├── storage/     # 本地存储、安全存储
│   ├── theme/       # 主题、响应式断点
│   └── utils/       # 工具函数
├── features/        # 功能模块
│   ├── auth/        # 认证（登录/登出/Token 管理）
│   ├── home/        # 首页
│   ├── library/     # 歌曲库
│   ├── player/      # 播放器（桌面/移动/TV/迷你）
│   ├── playlist/    # 歌单管理
│   └── settings/    # 设置（主题/扫描/插件/升级）
├── shared/          # 共享层
│   ├── layouts/     # 自适应布局（AdaptiveScaffold、ShellLayout）
│   ├── models/      # 数据模型（Song、Playlist）
│   └── widgets/     # 通用组件
├── main.dart        # 应用入口
scripts/
├── build-frontend.sh         # 多平台构建脚本
├── release-frontend.sh       # 版本发布脚本（语义化版本控制）
└── docker-build-frontend.sh  # Docker 构建便捷脚本
```

## 技术栈

| 类别 | 技术 |
|------|------|
| 状态管理 | Riverpod |
| 路由 | GoRouter |
| HTTP | Dio + JWT 拦截器 |
| 音频 | just_audio + audio_service |
| 本地存储 | SharedPreferences + FlutterSecureStorage |
| 图片缓存 | CachedNetworkImage |

## 部署模式

| 模式 | 说明 |
|------|------|
| **standalone** | 前后端分离部署，显示 API 地址配置 UI，用户手动填写后端地址 |
| **embedded** | 嵌入 Go 后端同域部署，自动使用当前域名，隐藏 API 地址 UI |

默认构建（不传 `--dart-define`）等同于 standalone 模式。

## 版本发布

使用 `release-frontend.sh` 脚本进行版本发布（遵循语义化版本控制）：

```bash
# 补丁版本升级（1.0.0 -> 1.0.1）
./scripts/release-frontend.sh patch

# 次版本号升级（1.0.0 -> 1.1.0）
./scripts/release-frontend.sh minor

# 主版本号升级（1.0.0 -> 2.0.0）
./scripts/release-frontend.sh major
```

脚本会自动：
- 读取并升级 `pubspec.yaml` 中的版本号
- 创建 Git 标签（格式：`v{version}`）
- 推送 Git 标签到远程仓库
- 提供交互式确认和进度反馈

## 后端

需要配合 [Songloft 后端](https://github.com/songloft-org/songloft) 服务运行。默认连接 `http://localhost:58091`，可在登录页中修改 API 地址。

默认账号：admin / admin

🔗 **服务端 GitHub**: [https://github.com/songloft-org/songloft](https://github.com/songloft-org/songloft)

## 许可证 / 第三方组件

本项目基于 [Apache-2.0 license](LICENSE) 开源。

> **LGPL 合规提示**：本客户端在 Windows / Linux 上通过 `just_audio_media_kit` 调用 libmpv（LGPL-2.1+）作为音频后端。Windows 端打包的是 **audio-only LGPL 构建**（不含 GPL 编码器如 libx264 / libx265），Linux 端动态链接系统的 libmpv。完整的第三方组件清单、许可证类型与源码获取途径见 [NOTICE](NOTICE)。
