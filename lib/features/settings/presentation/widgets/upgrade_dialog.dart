import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exceptions.dart';
import '../../../../core/theme/responsive.dart';
import '../../data/upgrade_api.dart';
import '../providers/settings_provider.dart';

/// 升级对话框
class UpgradeDialog extends ConsumerStatefulWidget {
  const UpgradeDialog({super.key});

  /// 显示升级对话框
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UpgradeDialog(),
    );
  }

  @override
  ConsumerState<UpgradeDialog> createState() => _UpgradeDialogState();
}

class _UpgradeDialogState extends ConsumerState<UpgradeDialog> {
  /// 预设的 GitHub 代理列表
  static const List<_ProxyOption> _presetProxies = [
    _ProxyOption(label: '直连 (不使用代理)', value: ''),
    _ProxyOption(label: 'ghproxy.com', value: 'https://ghproxy.com/'),
    _ProxyOption(label: 'ghfast.top', value: 'https://ghfast.top/'),
    _ProxyOption(label: 'gh.con.sh', value: 'https://gh.con.sh/'),
    _ProxyOption(
      label: 'mirror.ghproxy.com',
      value: 'https://mirror.ghproxy.com/',
    ),
  ];

  bool _isChecking = true;
  bool _isStarting = false;
  bool _isResetting = false;
  String? _error;
  UpgradeCheck? _checkResult;

  /// 当前选中的版本类型索引（在 availableUpdates 列表中的索引）
  int _selectedVersionIndex = 0;

  /// 当前选中的代理索引，-1 表示自定义
  int _selectedProxyIndex = 0;
  final TextEditingController _customProxyController = TextEditingController();

  /// 上次检查时使用的代理地址，用于检测代理是否变化
  String _lastCheckedProxy = '';

  /// 获取当前生效的代理地址
  String get _effectiveProxy {
    if (_selectedProxyIndex == -1) {
      return _customProxyController.text.trim();
    }
    if (_selectedProxyIndex >= 0 &&
        _selectedProxyIndex < _presetProxies.length) {
      return _presetProxies[_selectedProxyIndex].value;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 延迟调用，避免在 initState 中访问 inherited widget
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkUpgrade();
    });
  }

  @override
  void dispose() {
    _customProxyController.dispose();
    super.dispose();
  }

  /// 代理是否在上次检查后发生了变化
  bool get _proxyChanged => _effectiveProxy != _lastCheckedProxy;

  Future<void> _checkUpgrade() async {
    final proxy = _effectiveProxy;
    setState(() {
      _isChecking = true;
      _error = null;
      _checkResult = null;
      _lastCheckedProxy = proxy;
    });

    try {
      final upgradeApi = ref.read(upgradeApiProvider);
      final result = await upgradeApi
          .checkUpgrade(githubProxy: proxy.isNotEmpty ? proxy : null)
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _checkResult = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = '检查更新超时，请尝试切换代理后重试');
    } catch (e) {
      if (mounted) setState(() => _error = '检查更新失败: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  /// 获取当前选中的版本信息
  UpdateVersionInfo? get _selectedVersion {
    if (_checkResult == null || _checkResult!.availableUpdates.isEmpty) {
      return null;
    }
    if (_selectedVersionIndex >= 0 &&
        _selectedVersionIndex < _checkResult!.availableUpdates.length) {
      return _checkResult!.availableUpdates[_selectedVersionIndex];
    }
    return _checkResult!.availableUpdates.first;
  }

  Future<void> _startUpgrade() async {
    final version = _selectedVersion;
    if (version == null) return;

    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final proxy = _effectiveProxy;
      await ref
          .read(upgradeProgressProvider.notifier)
          .startUpgrade(
            versionType: version.type,
            githubProxy: proxy.isNotEmpty ? proxy : null,
          );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '启动升级失败: $e');
    } finally {
      setState(() => _isStarting = false);
    }
  }

  Future<void> _resetToBaseImage() async {
    // 二次确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认回退'),
            content: const Text('确定要回退到 Docker 镜像的底包版本吗？\n\n回退后服务将自动重启。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认回退'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      await ref.read(upgradeProgressProvider.notifier).resetToBaseImage();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '回退失败: $e');
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final upgradeProgress = ref.watch(upgradeProgressProvider);

    return AlertDialog(
      title: const Row(
        children: [Icon(Icons.system_update), SizedBox(width: 8), Text('检查更新')],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.responsiveDialogMaxWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 错误信息
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),

              // GitHub 代理选择（升级过程中不显示）
              if (!upgradeProgress.isUpgrading && !upgradeProgress.isCompleted)
                _buildProxySelector(theme, colorScheme),

              // 正在检查
              if (_isChecking)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在检查更新...'),
                    ],
                  ),
                )
              // 正在升级
              else if (upgradeProgress.isUpgrading)
                _buildUpgradeProgress(upgradeProgress)
              // 升级完成
              else if (upgradeProgress.isCompleted)
                _buildUpgradeCompleted()
              // 升级出错
              else if (upgradeProgress.isError)
                _buildUpgradeError(upgradeProgress)
              // 本地捕获的错误（如 API 返回 403）- 错误信息已在顶部显示
              else if (_error != null)
                const SizedBox.shrink()
              // 显示检查结果
              else if (_checkResult != null)
                _buildCheckResult(_checkResult!),
            ],
          ),
        ),
      ),
      actions: _buildActions(upgradeProgress),
    );
  }

  Widget _buildProxySelector(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GitHub 代理', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          // 预设代理选项 + 自定义代理选项
          RadioGroup<int>(
            groupValue: _selectedProxyIndex,
            onChanged: (value) {
              if (value != null) setState(() => _selectedProxyIndex = value);
            },
            child: Column(
              children: [
                ...List.generate(_presetProxies.length, (index) {
                  final proxy = _presetProxies[index];
                  return RadioListTile<int>(
                    title: Text(proxy.label, style: theme.textTheme.bodyMedium),
                    value: index,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }),
                // 自定义代理选项
                RadioListTile<int>(
                  title: Text('自定义代理', style: theme.textTheme.bodyMedium),
                  value: -1,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 自定义代理输入框
          if (_selectedProxyIndex == -1)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: TextField(
                controller: _customProxyController,
                decoration: const InputDecoration(
                  hintText: 'https://your-proxy.com/',
                  helperText: '输入代理地址，如 https://ghproxy.com/',
                  helperMaxLines: 2,
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _buildCheckResult(UpgradeCheck check) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!check.hasUpdate) {
      return Center(
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 16),
            const Text('已是最新版本'),
            const SizedBox(height: 8),
            Text(
              '当前版本: ${check.currentVersion ?? '未知'}',
              style: theme.textTheme.bodySmall,
            ),
            // 仅 Docker 环境显示回退按钮
            if (check.isDocker) ...[
              const SizedBox(height: 16),
              _buildResetButton(theme),
            ],
          ],
        ),
      );
    }

    final selectedVersion = _selectedVersion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前版本
        Text(
          '当前版本: ${check.currentVersion ?? '未知'}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),

        // 版本选择（多个可用更新时显示，仅 Docker 环境）
        if (check.isDocker && check.availableUpdates.length > 1) ...[
          Text('选择升级版本:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: _selectedVersionIndex,
            onChanged: (value) {
              if (value != null) setState(() => _selectedVersionIndex = value);
            },
            child: Column(
              children: [
                ...List.generate(check.availableUpdates.length, (index) {
                  final update = check.availableUpdates[index];
                  return RadioListTile<int>(
                    title: Text(
                      '${update.label} (${update.version})',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle:
                        update.buildTime != null
                            ? Text(
                              '构建时间: ${update.buildTime}',
                              style: theme.textTheme.bodySmall,
                            )
                            : null,
                    value: index,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 选中版本的详细信息
        if (selectedVersion != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.new_releases, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${selectedVersion.label} ${selectedVersion.version}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 发布说明
          if (selectedVersion.releaseNotes != null &&
              selectedVersion.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('更新说明:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  selectedVersion.releaseNotes!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ],

        // 仅 Docker 环境显示回退到底包按钮
        if (check.isDocker) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Center(child: _buildResetButton(theme)),
        ],
      ],
    );
  }

  Widget _buildResetButton(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: _isResetting ? null : _resetToBaseImage,
      icon:
          _isResetting
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.restore, size: 18),
      label: Text(_isResetting ? '正在回退...' : '回退到底包版本'),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _buildUpgradeProgress(UpgradeProgress progress) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress.progress / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 16),
        Text(progress.statusText),
        if (progress.message != null) ...[
          const SizedBox(height: 8),
          Text(progress.message!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildUpgradeCompleted() {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          const Text('升级完成'),
          const SizedBox(height: 8),
          Text('应用即将重启', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildUpgradeError(UpgradeProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(Icons.error, color: colorScheme.error, size: 48),
        const SizedBox(height: 16),
        const Text('升级失败'),
        if (progress.message != null) ...[
          const SizedBox(height: 8),
          Text(
            progress.message!,
            style: TextStyle(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// 打开 GitHub Release 下载页面
  Future<void> _launchReleaseUrl() async {
    final releaseUrl =
        _checkResult?.releaseUrl ??
        'https://github.com/songloft-org/songloft/releases/latest';
    final url = Uri.parse(releaseUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  List<Widget> _buildActions(UpgradeProgress upgradeProgress) {
    // 正在升级时不显示按钮
    if (upgradeProgress.isUpgrading) {
      return [];
    }

    // 升级完成
    if (upgradeProgress.isCompleted) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
      ];
    }

    // 升级出错
    if (upgradeProgress.isError) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(upgradeProgressProvider.notifier).reset();
            _checkUpgrade();
          },
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('重试'),
        ),
      ];
    }

    // 正在检查
    if (_isChecking) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('取消'),
        ),
        if (_proxyChanged)
          FilledButton(
            onPressed: _checkUpgrade,
            style: FilledButton.styleFrom(
              minimumSize: context.responsiveButtonMinSize,
            ),
            child: const Text('重新检查'),
          ),
      ];
    }

    // 检查时发生错误（已捕获）
    if (_error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _checkUpgrade,
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('重试'),
        ),
      ];
    }

    // 检查结果：有更新
    if (_checkResult != null && _checkResult!.hasUpdate) {
      // 非 Docker 环境：显示"前往下载"按钮
      if (!_checkResult!.isDocker) {
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              minimumSize: context.responsiveButtonMinSize,
            ),
            child: const Text('稍后'),
          ),
          if (_proxyChanged)
            OutlinedButton(
              onPressed: _checkUpgrade,
              style: OutlinedButton.styleFrom(
                minimumSize: context.responsiveButtonMinSize,
              ),
              child: const Text('重新检查'),
            ),
          FilledButton.icon(
            onPressed: () => _launchReleaseUrl(),
            style: FilledButton.styleFrom(
              minimumSize: context.responsiveButtonMinSize,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('前往下载'),
          ),
        ];
      }

      // Docker 环境：显示"立即升级"按钮
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('稍后'),
        ),
        if (_proxyChanged)
          OutlinedButton(
            onPressed: _checkUpgrade,
            style: OutlinedButton.styleFrom(
              minimumSize: context.responsiveButtonMinSize,
            ),
            child: const Text('重新检查'),
          ),
        FilledButton(
          onPressed: _isStarting ? null : _startUpgrade,
          style: FilledButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child:
              _isStarting
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('立即升级'),
        ),
      ];
    }

    if (_checkResult != null) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: context.responsiveButtonMinSize,
          ),
          child: const Text('关闭'),
        ),
        if (_proxyChanged)
          FilledButton(
            onPressed: _checkUpgrade,
            style: FilledButton.styleFrom(
              minimumSize: context.responsiveButtonMinSize,
            ),
            child: const Text('重新检查'),
          ),
      ];
    }

    return [];
  }
}

/// GitHub 代理选项
class _ProxyOption {
  final String label;
  final String value;

  const _ProxyOption({required this.label, required this.value});
}
