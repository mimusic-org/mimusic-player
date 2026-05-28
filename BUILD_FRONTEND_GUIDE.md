# Songloft Flutter 前端构建指南

## 📦 概述

`build-frontend.sh` 用于构建 Songloft Flutter 前端，支持按平台单独构建或并行构建所有平台。

### 支持的平台

- ✅ **Web** - 独立部署版（standalone）
- ✅ **Web Embedded** - 嵌入版（用于 Go 后端嵌入）
- ✅ **Linux** - 桌面应用
- ✅ **Windows** - 桌面应用（需 Windows 系统）
- ✅ **macOS** - 桌面应用（需 macOS 系统）
- ✅ **Android** - APK + AAB（需 Android SDK）
- ⚠️ **iOS** - 仅在 macOS 环境可构建

## 🚀 快速开始

### 方法 1: 使用 Makefile（推荐）

```bash
# 构建指定平台
make build-frontend PLATFORM=web
make build-frontend PLATFORM=linux
make build-frontend PLATFORM=android

# 构建到自定义目录
make build-frontend PLATFORM=web OUTPUT_DIR=/tmp/songloft-player-build

# 构建当前系统支持的所有平台
make build-frontend-all

# 快捷目标
make build-frontend-web        # Web standalone
make build-frontend-linux      # Linux 桌面
make build-frontend-windows    # Windows 桌面
make build-frontend-macos      # macOS 桌面
make build-frontend-android    # Android APK + AAB
make build-frontend-ios        # iOS（仅 macOS）
```

### 方法 2: 直接运行脚本

```bash
# 构建单个平台
./songloft-player/scripts/build-frontend.sh web
./songloft-player/scripts/build-frontend.sh linux
./songloft-player/scripts/build-frontend.sh android

# 指定输出目录
./songloft-player/scripts/build-frontend.sh web /tmp/songloft-player-build

# 构建所有平台（自动跳过不支持的平台）
./songloft-player/scripts/build-frontend.sh all
```

## ⚡ 并行构建特性

### 工作原理

脚本使用后台进程（`&`）和 `wait` 命令实现真正的并行构建：

1. **同时启动多个构建进程** - Web、Linux、Windows、macOS、Android 同时开始构建
2. **独立日志记录** - 每个平台的输出保存到单独的日志文件
3. **统一错误处理** - 等待所有进程完成后检查失败情况

### 性能提升

相比串行构建，并行构建可以显著减少总时间：

```
串行构建：Web(2m) + Linux(5m) + Windows(5m) + macOS(5m) + Android(8m) = ~25 分钟
并行构建：max(Web, Linux, Windows, macOS, Android) = ~8-10 分钟
```

**预计速度提升 60-70%** 🚀

## 📁 输出结构

```
songloft-player-build/
├── .build_logs/          # 构建日志目录
│   ├── web.log
│   ├── linux.log
│   ├── windows.log
│   ├── macos.log
│   ├── android.log
│   └── ios.log (如果构建)
├── web-standalone/       # Web 独立部署版
├── linux/                # Linux 桌面版
├── windows/              # Windows 桌面版
├── macos/                # macOS 桌面版
├── android/
│   ├── apk/              # Android APK 文件
│   └── bundle/           # Android AAB 文件
├── ios/                  # iOS 应用（仅 macOS）
└── BUILD_REPORT.md       # 构建报告
```

## 🔍 构建日志

每个平台的构建日志保存在 `.build_logs/` 目录：

```bash
# 查看 Web 构建日志
cat songloft-player-build/.build_logs/web.log

# 查看所有日志
ls -la songloft-player-build/.build_logs/
```

## ❌ 错误处理

如果某个平台构建失败：

1. 脚本会等待所有其他平台完成
2. 显示失败提示和日志文件位置
3. 返回非零退出码

```bash
# 检查是否有平台失败
if [ $? -ne 0 ]; then
    echo "构建失败，查看日志："
    ls songloft-player-build/.build_logs/*.log
fi
```

## 📊 构建报告

脚本会自动生成 `BUILD_REPORT.md`，包含：

- 构建时间和环境信息
- 各平台产物大小
- 文件数量统计
- 下一步操作建议

## 💡 高级用法

### 1. 在 CI/CD 中使用

```yaml
# GitHub Actions 示例 - 多平台矩阵构建
jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            platform: web
          - os: ubuntu-latest
            platform: linux
          - os: macos-latest
            platform: macos
          - os: macos-latest
            platform: ios
          - os: windows-latest
            platform: windows
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.0'
      - name: Build
        run: ./songloft-player/scripts/build-frontend.sh ${{ matrix.platform }} ${{ runner.temp }}/songloft-player-build
      - uses: actions/upload-artifact@v4
        with:
          name: songloft-${{ matrix.platform }}
          path: ${{ runner.temp }}/songloft-player-build/
```

### 2. Docker 构建（Web + Linux + Android）

```bash
# 默认构建所有 Linux 容器支持的平台（Web + Linux + Android）
docker build -t songloft-frontend-builder songloft-player/

# 仅构建 Web
docker build --build-arg BUILD_PLATFORM=web -t songloft-frontend-builder songloft-player/

# 仅构建 Android
docker build --build-arg BUILD_PLATFORM=android -t songloft-frontend-builder songloft-player/

# 提取产物到本地
docker create --name tmp-frontend songloft-frontend-builder
docker cp tmp-frontend:/output/ ./songloft-player-build/
docker rm tmp-frontend

# 或使用便捷脚本（支持指定平台参数）
./songloft-player/scripts/docker-build-frontend.sh              # 构建所有平台
./songloft-player/scripts/docker-build-frontend.sh android      # 仅构建 Android
```

## 🛠️ 环境要求

### 通用要求

- Flutter SDK 3.29+
- Dart SDK 3.7+
- Bash shell

### 平台特定要求

**Linux:**
```bash
# Ubuntu/Debian
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
```

**Windows:**
- Visual Studio 2022 (带 C++ 桌面开发)
- Windows 10 SDK

**macOS:**
- Xcode 15+
- CocoaPods (`sudo gem install cocoapods`)

**Android:**
- Android SDK
- Android NDK
- Java JDK 17+

**iOS:**
- macOS (必需)
- Xcode 15+
- iOS SDK

## 🐛 故障排查

### 问题 1: 构建卡在某个平台

查看对应日志文件：

```bash
tail -f songloft-player-build/.build_logs/<platform>.log
```

### 问题 2: 内存不足

Flutter 构建比较消耗内存，建议：

- 关闭其他应用
- 增加 swap 空间（Linux）
- 分批次构建（修改脚本，去掉部分平台的 `&`）

### 问题 3: Android 构建失败

```bash
# 接受许可证
sdkmanager --licenses

# 清理 Gradle 缓存
cd songloft-player
flutter clean
rm -rf android/.gradle
```

### 问题 4: iOS 构建失败（macOS）

```bash
# 清理 Pod
cd songloft-player/ios
pod deintegrate
pod install

# 清理构建
flutter clean
flutter pub get
```

## 📈 性能优化建议

1. **使用 SSD** - 构建速度提升 30-50%
2. **足够内存** - 建议 16GB+
3. **网络代理** - 加速依赖下载
4. **构建缓存** - 保留 `.flutter-plugins` 等文件

## 📝 示例输出

```
========================================
Songloft Flutter 前端全平台并行构建工具
========================================

输出目录：/Users/hanxi/toy/songloft/songloft-player-build
前端目录：/Users/hanxi/toy/songloft/songloft-player
CPU 核心数：8 (用于控制并发)

Flutter 版本:
Flutter 3.29.0 • channel stable

[准备阶段] 清理并创建输出目录...
✓ 输出目录已准备：/Users/hanxi/toy/songloft/frontend-build

[准备阶段] 安装 Flutter 依赖...
✓ 依赖安装完成

========================================
[并行构建阶段] 启动并发构建...
========================================

→ 启动 Web 构建进程
→ 启动 Linux 构建进程
→ 启动 Windows 构建进程
→ 启动 macOS 构建进程
→ 启动 Android 构建进程
→ 启动 iOS 构建进程

等待所有构建进程完成...

[Web] 开始构建 Web 独立部署版...
[Linux] 开始构建 Linux 版本...
[Windows] 开始构建 Windows 版本...
[macOS] 开始构建 macOS 版本...
[Android] 开始构建 Android 版本...
[iOS] 开始构建 iOS 版本...

✓[Web] Web 构建完成
✓[Linux] Linux 构建完成
✓[Windows] Windows 构建完成
✓[macOS] macOS 构建完成
✓[Android] Android 构建完成
✓[iOS] iOS 构建完成

========================================
✓ 所有平台构建完成！
========================================

总大小：2.1GB

  Web (standalone):     45MB
  Linux:               180MB
  Windows:             220MB
  macOS:               250MB
  Android:             180MB
  iOS:                 320MB

构建报告已保存至：songloft-player-build/BUILD_REPORT.md
```

## 📞 支持

如有问题，请查看：

1. 各平台构建日志
2. `BUILD_REPORT.md` 构建报告
3. Flutter 官方文档：https://docs.flutter.dev
