import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exceptions.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../shared/utils/responsive_snackbar.dart';
import '../../data/scan_api.dart';
import '../providers/settings_provider.dart';
import 'exclude_dir_manager.dart';

/// 扫描管理组件
class ScanManager extends ConsumerStatefulWidget {
  const ScanManager({super.key});

  @override
  ConsumerState<ScanManager> createState() => _ScanManagerState();
}

class _ScanManagerState extends ConsumerState<ScanManager> {
  bool _isLoading = false;
  String? _error;
  String _scanMode = 'skip'; // 'skip' 或 'reimport'
  bool _showExcludeDirs = false; // 是否展开排除目录设置

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scanProgressProvider.notifier).refreshProgress();
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(scanProgressProvider.notifier)
          .startScan(reimport: _scanMode == 'reimport');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '扫描失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelScan() async {
    try {
      await ref.read(scanProgressProvider.notifier).cancelScan();
    } on ApiException catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(context, message: '取消失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(context, message: '取消失败: $e');
      }
    }
  }

  void _reset() {
    ref.read(scanProgressProvider.notifier).reset();
    setState(() => _error = null);
  }

  String get _modeDescription {
    return _scanMode == 'skip' ? '仅导入新发现的音乐文件' : '重新扫描并覆盖所有音乐信息';
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(scanProgressProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 错误信息
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _error = null),
                  iconSize: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 「自动创建歌单包含子目录」开关
        _buildIncludeSubdirsTile(),
        const SizedBox(height: AppSpacing.md),

        // 排除目录设置（可展开/折叠）
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.folder_off_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                title: const Text('排除目录设置'),
                subtitle: Text(
                  '配置扫描时需要忽略的目录',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  _showExcludeDirs
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                onTap: () {
                  setState(() => _showExcludeDirs = !_showExcludeDirs);
                },
              ),
              if (_showExcludeDirs)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: ExcludeDirManager(),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 根据状态显示不同内容
        if (progress.isIdle) _buildIdleState(),
        if (progress.isScanning) _buildScanningState(progress),
        if (progress.isCompleted) _buildCompletedState(progress),
        if (progress.isCancelled) _buildCancelledState(progress),
        if (progress.isError) _buildErrorState(progress),
      ],
    );
  }

  /// 构建空闲状态 UI（扫描模式选择 + 扫描按钮）
  Widget _buildIdleState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 带图标的 SegmentedButton（全宽）
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'skip',
                label: Text('跳过已存在'),
                icon: Icon(Icons.skip_next_outlined),
              ),
              ButtonSegment(
                value: 'reimport',
                label: Text('重新导入'),
                icon: Icon(Icons.refresh_outlined),
              ),
            ],
            selected: {_scanMode},
            onSelectionChanged: (selected) {
              setState(() => _scanMode = selected.first);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // 当前模式描述文字
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _modeDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 全宽扫描按钮
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _startScan,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_isLoading ? '正在启动...' : '扫描本地音乐'),
          ),
        ),
      ],
    );
  }

  Widget _buildScanningState(ScanProgress progress) {
    final isCreatingPlaylists = progress.isCreatingPlaylists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: isCreatingPlaylists ? null : progress.progress / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        if (isCreatingPlaylists)
          Text(
            '正在按目录自动创建歌单...',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          if (progress.currentFile != null)
            Text(
              '正在扫描: ${progress.currentFile}',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            '已处理: ${progress.scannedFiles}/${progress.totalFiles}, 导入: ${progress.importedFiles}, 跳过: ${progress.skippedFiles}, 失败: ${progress.failedFiles}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isCreatingPlaylists ? null : _cancelScan,
          icon: const Icon(Icons.cancel),
          label: const Text('取消扫描'),
        ),
      ],
    );
  }

  /// 「自动创建歌单包含子目录」开关
  Widget _buildIncludeSubdirsTile() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncValue = ref.watch(autoCreateIncludeSubdirsProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: SwitchListTile(
        secondary: Icon(
          Icons.account_tree_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        title: const Text('自动创建歌单包含子目录'),
        subtitle: Text(
          asyncValue.when(
            data: (_) => '开启后子目录歌曲也会加入到祖先目录歌单',
            loading: () => '加载中...',
            error: (_, __) => '读取配置失败',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: asyncValue.value ?? false,
        onChanged: asyncValue.isLoading
            ? null
            : (value) async {
                try {
                  await ref
                      .read(autoCreateIncludeSubdirsProvider.notifier)
                      .setValue(value);
                } catch (e) {
                  if (mounted) {
                    ResponsiveSnackBar.showError(
                      context,
                      message: '保存失败: $e',
                    );
                  }
                }
              },
      ),
    );
  }

  Widget _buildCompletedState(ScanProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('扫描完成'),
                    Text(
                      '导入 ${progress.importedFiles} 首, 跳过 ${progress.skippedFiles} 首, 失败 ${progress.failedFiles} 个',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ),
      ],
    );
  }

  Widget _buildCancelledState(ScanProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '扫描已取消 (已处理 ${progress.scannedFiles} 个文件)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ScanProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.error, color: colorScheme.error),
              const SizedBox(width: 8),
              const Expanded(child: Text('扫描出错')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
