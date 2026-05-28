# Flutter 前端版本发布指南

本目录包含 Songloft Flutter 前端的版本发布脚本和最佳实践。

## 📋 版本发布脚本

### `release-frontend.sh`

用于自动化 Flutter 前端的版本发布流程。

**位置**: `songloft-player/scripts/release-frontend.sh`

**用法**:

```bash
# 补丁版本升级（修复 bug，1.0.0 -> 1.0.1）
./scripts/release-frontend.sh patch

# 次版本号升级（新增功能，1.0.0 -> 1.1.0）
./scripts/release-frontend.sh minor

# 主版本号升级（重大变更，1.0.0 -> 2.0.0）
./scripts/release-frontend.sh major

# 查看帮助信息
./scripts/release-frontend.sh --help
```

## 🔧 脚本功能

执行 `release-frontend.sh` 后，脚本会自动完成以下操作：

1. **读取当前版本号** - 从 `pubspec.yaml` 中提取当前版本
2. **升级版本号** - 根据指定的升级类型（major/minor/patch）计算新版本
3. **更新 pubspec.yaml** - 自动修改版本号，保留 build number
4. **检查并更新 README.md** - 如果存在版本号引用则更新
5. **Git 提交更改** - 将修改的文件提交到 git
6. **创建 Git 标签** - 创建 annotated tag，格式为 `v{version}`
7. **推送标签** - 将 Git 标签推送到远程仓库

## 🛡️ 安全机制

- ✅ **Git 仓库检查** - 确保在 git 仓库中执行
- ✅ **未提交更改检测** - 存在未提交更改时会提示确认
- ✅ **交互式确认** - 关键步骤需要用户确认
- ✅ **标签冲突处理** - 如果 tag 已存在会提示是否覆盖
- ✅ **错误处理** - 完善的错误处理和友好的错误提示

## 📝 语义化版本控制

遵循 [Semantic Versioning](https://semver.org/) 规范：

- **MAJOR** (主版本号): 不兼容的 API 或重大功能变更
- **MINOR** (次版本号): 向下兼容的功能性新增
- **PATCH** (补丁版本): 向下兼容的问题修正

**示例**:
- `1.0.0` → `2.0.0` (major) - 重大更新
- `1.0.0` → `1.1.0` (minor) - 新功能
- `1.0.0` → `1.0.1` (patch) - Bug 修复

## 🚀 完整发布流程

### 1. 发布新版本

```bash
cd songloft-player

# 选择合适的版本升级类型
./scripts/release-frontend.sh patch  # 或 minor / major
```

### 2. 构建所有平台

```bash
# 等待 Git 标签推送完成后，构建所有平台
./scripts/build-frontend.sh all
```

### 3. 创建 GitHub Release

访问 https://github.com/songloft-org/songloft-player/releases/new

- Tag version: 选择刚创建的 tag (如 `v1.0.1`)
- Release title: `v1.0.1`
- Description: 描述本次更新的 changelog

### 4. 上传构建产物

将 `songloft-player-build/` 目录下的各平台构建产物上传到 Release。

## 📦 构建产物说明

| 文件 | 说明 |
|------|------|
| `songloft-web-standalone.tar.gz` | Web 独立部署版 |
| `songloft-web-embedded.tar.gz` | Web 嵌入版（用于 Go 后端） |
| `songloft-linux-x64/` | Linux 桌面版 |
| `songloft-linux-amd64.deb` | Debian/Ubuntu 安装包 |
| `songloft-windows-x64.zip` | Windows 便携版 |
| `songloft-macos.dmg` | macOS DMG |
| `songloft-arm64-v8a.apk` | Android APK (ARM64) |
| `songloft-ios-nosign.ipa` | iOS IPA (无签名) |

## 🔄 与后端版本发布的区别

| 项目 | 前端 (`release-frontend.sh`) | 后端 (`release.sh`) |
|------|---------------------------|-------------------|
| 版本文件 | `pubspec.yaml` | `Makefile` |
| Swagger 更新 | ❌ | ✅ |
| CHANGELOG 更新 | ❌ | ✅ |
| Docker 构建 | ❌ | ✅ |
| GitHub Release | 手动创建 | 自动创建 |
| 构建触发 | 手动 | 自动 |

## ⚠️ 注意事项

1. **发布前检查**
   - 确保所有测试通过
   - 确保代码已格式化
   - 确保没有未提交的更改

2. **版本号规则**
   - 版本号格式：`X.Y.Z+W` (X=主版本，Y=次版本，Z=补丁，W=build number)
   - 脚本只修改 `X.Y.Z` 部分，保留 build number

3. **Git 标签**
   - 标签格式：`v{version}` (如 `v1.0.1`)
   - 使用 annotated tag，包含发布信息

4. **发布时机**
   - PATCH: Bug 修复，随时发布
   - MINOR: 新功能积累，定期发布
   - MAJOR: 重大更新，谨慎发布

## 🆘 故障排除

### 问题：脚本提示 "未检测到 Flutter"

**解决**: 确保 Flutter SDK 已安装并添加到 PATH

```bash
flutter --version  # 检查 Flutter 是否可用
```

### 问题：Git 标签推送失败

**解决**: 检查是否有远程仓库权限

```bash
git remote -v  # 检查远程仓库配置
git push origin v1.0.1  # 手动测试推送
```

### 问题：pubspec.yaml 格式错误

**解决**: 确保 version 字段格式正确

```yaml
version: 1.0.0+1  # 正确格式
```

## 📚 相关文档

- [构建脚本使用指南](./BUILD_FRONTEND_GUIDE.md)
- [Songloft 后端发布流程](../scripts/release.sh)
- [Flutter 版本管理](https://flutter.dev/docs/development/tools/pubspec)
