import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'widgets/cache_manager.dart';
import '../../../features/jsplugin/presentation/widgets/jsplugin_manager.dart';
import 'widgets/scan_manager.dart';
import 'widgets/theme_selector.dart';
import 'widgets/frontend_upgrade_dialog.dart';
import 'widgets/upgrade_dialog.dart';
import 'providers/settings_provider.dart';

/// 设置页面
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _apiUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 嵌入模式下 API 地址已由 main() 设定，无需加载存储的地址
    if (!AppConfig.isEmbedded) {
      _loadApiUrl();
    }
  }

  Future<void> _loadApiUrl() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final url = prefs.getApiBaseUrl();
      if (url != null) {
        _apiUrlController.text = url;
      }
    } catch (e) {
      // 忽略
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // 分组1: 外观设置
          _buildSectionCard(
            title: '外观设置',
            icon: Icons.palette_outlined,
            children: [
              const ListTile(
                leading: Icon(Icons.brightness_6),
                title: Text('主题模式'),
                subtitle: Text('选择应用的主题外观'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: ThemeSelector(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 分组2: 音乐库管理
          _buildSectionCard(
            title: '音乐库管理',
            icon: Icons.library_music_outlined,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: ScanManager()),
              const Divider(height: 1),
              _buildAutoConvertTile(),
            ],
          ),

          const SizedBox(height: 16),

          // 分组4: 插件管理
          _buildSectionCard(
            title: '扩展',
            icon: Icons.extension_outlined,
            children: [const JSPluginManager()],
          ),

          const SizedBox(height: 16),

          // 分组: 缓存管理
          _buildSectionCard(
            title: '缓存管理',
            icon: Icons.storage_outlined,
            children: [const CacheManager()],
          ),

          const SizedBox(height: 16),

          // 分组6: 系统
          _buildSectionCard(
            title: '系统',
            icon: Icons.settings_outlined,
            children: [
              _buildServerVersionTile(),
              if (!AppConfig.isEmbedded) ...[
                const Divider(height: 1),
                _buildFrontendUpdateTile(),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                subtitle: const Text('版本信息和许可证'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAboutDialog,
              ),
            ],
          ),

          // 分组7: 账户
          _buildSectionCard(
            title: '账户',
            icon: Icons.account_circle_outlined,
            children: [
              if (!AppConfig.isEmbedded) ...[
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('API 地址'),
                  subtitle: _buildApiUrlSubtitle(),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showApiUrlDialog,
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '退出登录',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLogoutDialog,
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认退出'),
            content: const Text('确定要退出当前账户吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('确认退出'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await ref.read(authStateProvider.notifier).logout();
    }
  }

  /// 构建服务端版本号 + 检查更新入口
  Widget _buildServerVersionTile() {
    final serverVersion = ref.watch(serverVersionProvider);

    return serverVersion.when(
      data:
          (version) => ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('检查服务端更新 (仅 Docker 可升级)'),
            subtitle: Text('当前版本: $version'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => UpgradeDialog.show(context),
          ),
      loading:
          () => const ListTile(
            leading: Icon(Icons.dns),
            title: Text('检查服务端更新 (仅 Docker 可升级)'),
            subtitle: Text('正在获取版本信息...'),
            trailing: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      error:
          (_, _) => ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('检查服务端更新 (仅 Docker 可升级)'),
            subtitle: const Text('获取版本信息失败'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => UpgradeDialog.show(context),
          ),
    );
  }

  /// 构建前端（客户端）更新检测入口
  Widget _buildFrontendUpdateTile() {
    final frontendCheck = ref.watch(frontendVersionCheckProvider);
    final versionDisplay = AppConfig.frontendVersionDisplay;

    return frontendCheck.when(
      data: (check) {
        final subtitle =
            check.hasUpdate
                ? '发现新版本: v${check.latestVersion}'
                : '当前版本: $versionDisplay (已是最新)';

        return ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('检查客户端更新'),
          subtitle: Text(
            subtitle,
            style:
                check.hasUpdate
                    ? TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )
                    : null,
          ),
          trailing:
              check.hasUpdate
                  ? Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.primary,
                  )
                  : const Icon(Icons.chevron_right),
          onTap: () {
            if (check.hasUpdate) {
              FrontendUpgradeDialog.show(context, versionCheck: check);
            } else {
              ResponsiveSnackBar.show(
                context,
                message: '当前已是最新版本 $versionDisplay',
              );
            }
          },
        );
      },
      loading:
          () => ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('检查客户端更新'),
            subtitle: Text('当前版本: $versionDisplay'),
            trailing: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      error:
          (_, _) => ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('检查客户端更新'),
            subtitle: Text('当前版本: $versionDisplay'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.invalidate(frontendVersionCheckProvider),
          ),
    );
  }

  /// 网络歌曲自动转本地开关
  Widget _buildAutoConvertTile() {
    final enabledAsync = ref.watch(autoConvertEnabledProvider);
    final enabled = enabledAsync.value ?? false;

    return SwitchListTile(
      secondary: const Icon(Icons.download_done_outlined),
      title: const Text('网络歌曲自动转为本地'),
      subtitle: const Text('网络歌曲缓存完成后,自动落地到音乐库,按歌单分目录存储'),
      value: enabled,
      onChanged: enabledAsync.isLoading
          ? null
          : (value) async {
              final dio = ref.read(dioProvider);
              try {
                await dio.put(
                  '${AppConfig.apiPrefix}/settings/auto-convert',
                  data: {'enabled': value},
                );
                ref.invalidate(autoConvertEnabledProvider);
                if (!mounted) return;
                ResponsiveSnackBar.show(
                  context,
                  message: value ? '已开启自动转换' : '已关闭自动转换',
                );
              } catch (e) {
                if (!mounted) return;
                ResponsiveSnackBar.showError(context, message: '保存失败: $e');
              }
            },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容
          ...children,
        ],
      ),
    );
  }

  Widget _buildApiUrlSubtitle() {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return prefsAsync.when(
      data: (prefs) {
        final url = prefs.getApiBaseUrl();
        return Text(url ?? '使用默认地址');
      },
      loading: () => const Text('加载中...'),
      error: (_, _) => const Text('使用默认地址'),
    );
  }

  Future<void> _showApiUrlDialog() async {
    // 先加载当前值
    String oldUrl = '';
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final currentUrl = prefs.getApiBaseUrl();
      oldUrl = currentUrl ?? '';
      _apiUrlController.text = oldUrl;
    } catch (e) {
      _apiUrlController.text = '';
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('API 地址'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设置服务器 API 地址。'),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'http://example.com:8080',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  final dialogContext = context;
                  try {
                    final prefs = await ref.read(appPreferencesProvider.future);
                    final urlBeforeReset = prefs.getApiBaseUrl() ?? '';
                    await prefs.clearApiBaseUrl();
                    _apiUrlController.clear();
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (!mounted) return;
                    if (urlBeforeReset.isNotEmpty) {
                      // 地址从有值变为空（重置），需要重新登录
                      AppConfig.baseUrl = '';
                      ref.invalidate(dioProvider);
                      await ref.read(authStateProvider.notifier).logout();
                      if (mounted) {
                        ResponsiveSnackBar.show(
                          this.context,
                          message: 'API 地址已重置，请重新登录',
                        );
                      }
                    } else {
                      if (mounted) {
                        ResponsiveSnackBar.show(
                          this.context,
                          message: '已重置为默认地址',
                        );
                      }
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ResponsiveSnackBar.showError(
                        dialogContext,
                        message: '重置失败: $e',
                      );
                    }
                  }
                },
                child: const Text('重置'),
              ),
              FilledButton(
                onPressed: () async {
                  final dialogContext = context;
                  final url = _apiUrlController.text.trim().replaceAll(
                    RegExp(r'/+$'),
                    '',
                  );
                  if (url.isNotEmpty && !Uri.tryParse(url)!.hasScheme) {
                    ResponsiveSnackBar.show(
                      dialogContext,
                      message: '请输入有效的 URL（包含 http:// 或 https://）',
                    );
                    return;
                  }

                  try {
                    final prefs = await ref.read(appPreferencesProvider.future);
                    if (url.isEmpty) {
                      await prefs.clearApiBaseUrl();
                    } else {
                      await prefs.setApiBaseUrl(url);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (!mounted) return;
                    if (url != oldUrl) {
                      // 地址发生变化，更新运行时配置并退出登录
                      AppConfig.baseUrl = url;
                      ref.invalidate(dioProvider);
                      await ref.read(authStateProvider.notifier).logout();
                      if (mounted) {
                        ResponsiveSnackBar.show(
                          this.context,
                          message: 'API 地址已更新，请重新登录',
                        );
                      }
                    } else {
                      if (mounted) {
                        ResponsiveSnackBar.show(
                          this.context,
                          message: 'API 地址已更新',
                        );
                      }
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ResponsiveSnackBar.showError(
                        dialogContext,
                        message: '保存失败: $e',
                      );
                    }
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showAboutDialog() async {
    String version = '1.0.0';
    String? gitCommit;

    try {
      final dio = ref.read(dioProvider);
      final response = await dio
          .get('${AppConfig.apiPrefix}/version')
          .timeout(const Duration(seconds: 3));
      final data = response.data as Map<String, dynamic>;
      final ver = data['version'] as String?;
      if (ver != null && ver.isNotEmpty) {
        version = ver;
      }
      final commit = data['git_commit'] as String?;
      if (commit != null && commit != 'unknown' && commit.isNotEmpty) {
        gitCommit = commit;
      }
    } catch (_) {
      // 忽略错误，使用默认版本号
    }

    if (!mounted) return;

    showAboutDialog(
      context: context,
      applicationName: 'Songloft',
      applicationVersion: version,
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/icons/app_icon.png', width: 48, height: 48),
      ),
      applicationLegalese: '© 2024-2026 Songloft. All rights reserved.',
      children: [
        const SizedBox(height: 16),
        const Text('Songloft 是一个开源的个人音乐服务器应用。'),
        const SizedBox(height: 8),
        const Text('支持本地音乐库管理、在线播放和插件扩展。'),
        if (gitCommit != null) ...[
          const SizedBox(height: 8),
          Text(
            'Git: $gitCommit',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),
        InkWell(
          onTap: () => _launchUrl('https://github.com/songloft-org/songloft'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'GitHub: songloft-org/songloft',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
