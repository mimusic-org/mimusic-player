import 'dart:async';
import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/utils/color_extraction.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/url_helper.dart';
import '../../../shared/models/song.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/song_picker_modal.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../data/playlist_api.dart';
import '../domain/playlist.dart';
import 'providers/playlist_provider.dart';
import 'widgets/song_cover_picker_modal.dart';
import '../../../shared/widgets/loading_indicator.dart';

/// 歌单详情页面
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  int get _playlistIdInt => int.tryParse(widget.playlistId) ?? 0;

  /// 触底加载预留距离
  static const double _loadMoreThreshold = 300.0;

  late final ScrollController _scrollController;

  /// 排序模式
  bool _isSortMode = false;

  /// 多选模式
  bool _isSelectMode = false;

  /// 多选模式下选中的歌曲 ID
  final Set<int> _selectedSongIds = {};

  /// 排序模式下的可排序歌曲列表（本地副本）
  List<Song> _sortableSongs = [];

  /// 网络歌曲→本地歌曲转换进度
  ConvertProgress? _convertProgress;
  Timer? _convertTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    // 进入页面时主动检查是否有正在进行的转换任务,有则恢复进度轮询
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeConvertProgressIfRunning();
    });
  }

  /// 进入页面时检查后端是否有正在进行的转换,有则恢复轮询和 banner 显示
  Future<void> _resumeConvertProgressIfRunning() async {
    if (!mounted) return;
    try {
      final api = ref.read(playlistApiProvider);
      final progress = await api.getConvertProgress(_playlistIdInt);
      if (!mounted) return;
      if (progress.isRunning) {
        setState(() => _convertProgress = progress);
        _pollConvertProgress(api);
      }
    } catch (_) {
      // 查询失败静默忽略,不影响页面其他功能
    }
  }

  @override
  void dispose() {
    _convertTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听：接近底部时触发分页加载
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      ref.read(playlistSongsProvider(_playlistIdInt).notifier).loadMore();
    }
  }

  /// 进入排序模式（确保所有歌曲已加载）
  Future<void> _enterSortMode(List<Song> songs) async {
    // 手动排序需要全部歌曲在内存中
    await ref.read(playlistSongsProvider(_playlistIdInt).notifier).loadAll();
    if (!mounted) return;
    final fullSongs =
        ref.read(playlistSongsProvider(_playlistIdInt)).value?.items ?? songs;
    setState(() {
      _isSortMode = true;
      _isSelectMode = false;
      _selectedSongIds.clear();
      _sortableSongs = List.from(fullSongs);
    });
  }

  /// 退出排序模式并保存
  Future<void> _exitSortMode() async {
    final songIds = _sortableSongs.map((s) => s.id).toList();
    setState(() => _isSortMode = false);

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylistSongs(
      _playlistIdInt,
      songIds,
    );

    if (mounted) {
      if (success) {
        ResponsiveSnackBar.showSuccess(context, message: '排序已保存');
      } else {
        ResponsiveSnackBar.showError(context, message: '排序保存失败');
      }
    }
  }

  /// 自动按名称排序
  Future<void> _autoSortByName(
    List<Song> songs, {
    bool ascending = true,
  }) async {
    // 排序需要全部歌曲在内存中
    await ref.read(playlistSongsProvider(_playlistIdInt).notifier).loadAll();
    if (!mounted) return;
    final fullSongs =
        ref.read(playlistSongsProvider(_playlistIdInt)).value?.items ?? songs;

    final sorted = List<Song>.from(fullSongs);
    sorted.sort((a, b) {
      final result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return ascending ? result : -result;
    });

    final songIds = sorted.map((s) => s.id).toList();

    // 检查排序前后是否有变化，避免无意义的 API 调用
    final originalIds = fullSongs.map((s) => s.id).toList();
    if (_listEquals(songIds, originalIds)) {
      if (mounted) {
        ResponsiveSnackBar.show(context, message: '歌曲已是该排序顺序');
      }
      return;
    }

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylistSongs(
      _playlistIdInt,
      songIds,
    );

    if (mounted) {
      if (success) {
        ResponsiveSnackBar.showSuccess(
          context,
          message: ascending ? '已按名称升序排列' : '已按名称降序排列',
        );
      } else {
        ResponsiveSnackBar.showError(context, message: '排序失败');
      }
    }
  }

  /// 提取标题中第一个出现的数字（支持开头和中间位置）
  /// 例如: "04.校园故事" → 4, "干得漂亮 | 01 好意被辜负" → 1
  /// 如果没有数字，返回 null
  int? _extractFirstNumber(String title) {
    final match = RegExp(r'(\d+)').firstMatch(title);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 自动按数字前缀排序
  Future<void> _autoSortByNumberPrefix(List<Song> songs) async {
    // 排序需要全部歌曲在内存中
    await ref.read(playlistSongsProvider(_playlistIdInt).notifier).loadAll();
    if (!mounted) return;
    final fullSongs =
        ref.read(playlistSongsProvider(_playlistIdInt)).value?.items ?? songs;

    final sorted = List<Song>.from(fullSongs);
    sorted.sort((a, b) {
      final numA = _extractFirstNumber(a.title);
      final numB = _extractFirstNumber(b.title);

      // 都有数字前缀：按数值排序
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
        // 数值相同时按标题字母序
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      // 有数字前缀的排在前面
      if (numA != null) return -1;
      if (numB != null) return 1;
      // 都没有数字前缀：按标题字母序
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    final songIds = sorted.map((s) => s.id).toList();

    // 检查排序前后是否有变化
    final originalIds = fullSongs.map((s) => s.id).toList();
    if (_listEquals(songIds, originalIds)) {
      if (mounted) {
        ResponsiveSnackBar.show(context, message: '歌曲已是该排序顺序');
      }
      return;
    }

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylistSongs(
      _playlistIdInt,
      songIds,
    );

    if (mounted) {
      if (success) {
        ResponsiveSnackBar.showSuccess(context, message: '已按数字前缀排序');
      } else {
        ResponsiveSnackBar.showError(context, message: '排序失败');
      }
    }
  }

  /// 比较两个整数列表是否相等
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 取消排序模式（不保存）
  void _cancelSortMode() {
    setState(() {
      _isSortMode = false;
      _sortableSongs = [];
    });
  }

  /// 进入多选模式
  void _enterSelectMode() {
    setState(() {
      _isSelectMode = true;
      _isSortMode = false;
      _selectedSongIds.clear();
      _sortableSongs = [];
    });
  }

  /// 退出多选模式
  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  /// 切换歌曲选中状态
  void _toggleSongSelection(int songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  /// 全选/取消全选
  void _toggleSelectAll(List<Song> songs) {
    setState(() {
      if (_selectedSongIds.length == songs.length) {
        _selectedSongIds.clear();
      } else {
        _selectedSongIds.addAll(songs.map((s) => s.id));
      }
    });
  }

  /// 批量删除选中的歌曲
  Future<void> _batchRemoveSelectedSongs() async {
    if (_selectedSongIds.isEmpty) return;

    final count = _selectedSongIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('批量移除'),
            content: Text('确定要从歌单中移除 $count 首歌曲吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('移除'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.batchRemoveSongs(
      _playlistIdInt,
      _selectedSongIds,
    );

    if (mounted) {
      if (success) {
        ResponsiveSnackBar.showSuccess(context, message: '已移除 $count 首歌曲');
        _exitSelectMode();
      } else {
        ResponsiveSnackBar.showError(context, message: '移除失败');
      }
    }
  }

  /// 拖拽排序回调
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _sortableSongs.removeAt(oldIndex);
      _sortableSongs.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(playlistDetailProvider(_playlistIdInt));
    final songsAsync = ref.watch(playlistSongsProvider(_playlistIdInt));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(playlistDetailProvider(_playlistIdInt));
          ref.invalidate(playlistSongsProvider(_playlistIdInt));
        },
        child: playlistAsync.when(
          data: (playlist) => _buildContent(context, playlist, songsAsync),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _buildError(error.toString()),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Playlist playlist,
    AsyncValue<PaginatedSongsState> songsAsync,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 顶栏：使用主题色，不受封面影响
        SliverAppBar(
          pinned: true,
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          title: Text(playlist.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/playlists');
              }
            },
          ),
          actions: _buildAppBarActions(
            context,
            playlist,
            songsAsync,
            colorScheme,
          ),
        ),

        // 封面 header 区域（独立于顶栏）
        SliverToBoxAdapter(
          child: _buildCoverHeader(context, playlist),
        ),

        // 歌单信息
        SliverToBoxAdapter(
          child: _buildPlaylistInfo(context, playlist, songsAsync),
        ),

        // 操作按钮
        SliverToBoxAdapter(
          child: _buildActionButtons(context, playlist, songsAsync),
        ),

        // 歌曲列表
        songsAsync.when(
          data: (state) => _buildSongList(context, playlist, state.items),
          loading:
              () => SliverToBoxAdapter(
                child: Column(
                  children: [
                    for (int i = 0; i < 5; i++) SkeletonLoader.listTile(),
                  ],
                ),
              ),
          error:
              (error, stack) =>
                  SliverToBoxAdapter(child: _buildError(error.toString())),
        ),

        // 加载更多指示器
        if (songsAsync.value != null)
          SliverToBoxAdapter(
            child: _buildSongsLoadMoreIndicator(songsAsync.value!),
          ),

        // 底部安全区域
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
        ),
      ],
    );
  }

  /// 构建歌曲分页加载更多指示器
  Widget _buildSongsLoadMoreIndicator(PaginatedSongsState state) {
    // 排序模式 / 多选模式下不显示加载更多（避免影响交互）
    if (_isSortMode || _isSelectMode) return const SizedBox.shrink();

    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed:
                () =>
                    ref
                        .read(playlistSongsProvider(_playlistIdInt).notifier)
                        .loadMore(),
            icon: const Icon(Icons.refresh),
            label: const Text('加载更多失败，点击重试'),
          ),
        ),
      );
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty && state.total > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '— 已全部加载（${state.total}） —',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 构建封面 header 区域（位于顶栏下方，不会覆盖顶栏）
  Widget _buildCoverHeader(BuildContext context, Playlist playlist) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWide = context.isWideScreen;
    final coverUrl = playlist.coverUrl;
    final paletteAsync = ref.watch(coverColorsProvider(coverUrl));
    final palette = paletteAsync.value;

    final coverSize = isWide ? 180.0 : 140.0;
    final bgColor = palette?.darkMutedColor ?? colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bgColor.withValues(alpha: 0.6),
            colorScheme.surface,
          ],
        ),
      ),
      padding: EdgeInsets.symmetric(
        vertical: isWide ? AppSpacing.lg : AppSpacing.md,
      ),
      child: Center(
        child: Container(
          width: coverSize,
          height: coverSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.medium,
          ),
          clipBehavior: Clip.antiAlias,
          child: coverUrl != null
              ? CachedNetworkImage(
                  imageUrl: UrlHelper.buildCoverUrl(coverUrl),
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: colorScheme.surfaceContainerHighest),
                  errorWidget: (context, url, error) =>
                      _buildCoverPlaceholder(colorScheme, playlist),
                )
              : _buildCoverPlaceholder(colorScheme, playlist),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colorScheme, Playlist playlist) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          playlist.type == 'radio' ? Icons.radio : Icons.queue_music,
          size: 64,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildPlaylistInfo(
    BuildContext context,
    Playlist playlist,
    AsyncValue<PaginatedSongsState> songsAsync,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final songCount = songsAsync.value?.total ?? 0;

    // 构建信息片段
    final infoParts = <String>[];
    if (playlist.type == 'radio') infoParts.add('电台');
    for (final label in playlist.labels) {
      infoParts.add(_getLabelName(label));
    }
    infoParts.add('$songCount 首歌曲');
    final subtitle = infoParts.join(' · ');

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 描述（如果有）
          if (playlist.description?.isNotEmpty == true) ...[
            Text(
              playlist.description!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // 聚合副标题
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          // 转换进度 banner（仅在转换中或刚结束未关闭时显示）
          if (_convertProgress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildConvertBanner(context, _convertProgress!),
          ],
        ],
      ),
    );
  }

  /// 转换进度 banner
  Widget _buildConvertBanner(BuildContext context, ConvertProgress progress) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = progress.totalSongs;
    final processed = progress.processedSongs;
    final ratio = total > 0 ? processed / total : 0.0;
    final isRunning = progress.isRunning;

    String title;
    if (isRunning) {
      if (progress.waiting) {
        title = '等待中（防风控限速）...  $processed / $total';
      } else {
        title = '正在转换  $processed / $total: ${progress.currentSong}';
      }
    } else if (progress.status == 'completed') {
      title =
          '转换完成: 成功 ${progress.convertedSongs}, 跳过 ${progress.skippedSongs}, 失败 ${progress.failedSongs}';
    } else if (progress.status == 'cancelled') {
      title = '已取消（已处理 $processed / $total）';
    } else if (progress.status == 'failed') {
      title = '转换失败: ${progress.error ?? '未知错误'}';
    } else {
      title = '转换 $processed / $total';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: isRunning && total > 0 ? ratio : null,
                  minHeight: 4,
                ),
              ],
            ),
          ),
          if (isRunning)
            IconButton(
              tooltip: '取消转换',
              icon: const Icon(Icons.close),
              onPressed: _cancelConvertToLocal,
            )
          else
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.check),
              onPressed: () => setState(() => _convertProgress = null),
            ),
        ],
      ),
    );
  }

  /// 构建 AppBar 操作按钮（使用主题色，不依赖封面调色板）
  List<Widget> _buildAppBarActions(
    BuildContext context,
    Playlist playlist,
    AsyncValue<PaginatedSongsState> songsAsync,
    ColorScheme colorScheme,
  ) {
    final songs = songsAsync.value?.items ?? [];
    final totalSongs = songsAsync.value?.total ?? songs.length;
    final isBuiltIn = playlist.isBuiltIn;

    // 排序模式
    if (_isSortMode) {
      return [
        TextButton(
          onPressed: _cancelSortMode,
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _exitSortMode,
          child: const Text('完成'),
        ),
      ];
    }

    // 多选模式
    if (_isSelectMode) {
      return [
        TextButton(
          onPressed: () async {
            await ref
                .read(playlistSongsProvider(_playlistIdInt).notifier)
                .loadAll();
            if (!mounted) return;
            final fullSongs =
                ref.read(playlistSongsProvider(_playlistIdInt)).value?.items ??
                songs;
            _toggleSelectAll(fullSongs);
          },
          child: Text(_selectedSongIds.length == totalSongs ? '取消全选' : '全选'),
        ),
        TextButton(
          onPressed:
              _selectedSongIds.isEmpty ? null : _batchRemoveSelectedSongs,
          style: TextButton.styleFrom(
            foregroundColor:
                _selectedSongIds.isEmpty ? null : colorScheme.error,
          ),
          child: Text('删除(${_selectedSongIds.length})'),
        ),
        TextButton(
          onPressed: _exitSelectMode,
          child: const Text('取消'),
        ),
      ];
    }

    // 正常模式
    return [
      if (totalSongs > 1)
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: '排序',
          onSelected: (value) {
            switch (value) {
              case 'name_asc':
                _autoSortByName(songs, ascending: true);
                break;
              case 'name_desc':
                _autoSortByName(songs, ascending: false);
                break;
              case 'number_asc':
                _autoSortByNumberPrefix(songs);
                break;
              case 'manual':
                _enterSortMode(songs);
                break;
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(
                  value: 'name_asc',
                  child: ListTile(
                    leading: Icon(Icons.sort_by_alpha),
                    title: Text('按名称排序 A→Z'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'name_desc',
                  child: ListTile(
                    leading: Icon(Icons.sort_by_alpha),
                    title: Text('按名称排序 Z→A'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'number_asc',
                  child: ListTile(
                    leading: Icon(Icons.format_list_numbered),
                    title: Text('按数字前缀排序'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'manual',
                  child: ListTile(
                    leading: Icon(Icons.drag_handle),
                    title: Text('手动排序'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
        ),
      if (songs.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.checklist),
          tooltip: '多选',
          onPressed: _enterSelectMode,
        ),
      IconButton(
        icon: const Icon(Icons.edit),
        tooltip: isBuiltIn ? '修改封面' : '编辑歌单',
        onPressed: () => _showEditDialog(playlist),
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          switch (value) {
            case 'add_songs':
              _addSongs();
              break;
            case 'convert_to_local':
              _startConvertToLocal();
              break;
            case 'delete':
              _confirmDelete(playlist);
              break;
          }
        },
        itemBuilder:
            (context) => [
              const PopupMenuItem(
                value: 'add_songs',
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('添加歌曲'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (playlist.type != 'radio')
                const PopupMenuItem(
                  value: 'convert_to_local',
                  child: ListTile(
                    leading: Icon(Icons.download_done),
                    title: Text('转换为本地歌曲'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!isBuiltIn)
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: colorScheme.error),
                    title: Text(
                      '删除歌单',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
      ),
    ];
  }

  Widget _buildActionButtons(
    BuildContext context,
    Playlist playlist,
    AsyncValue<PaginatedSongsState> songsAsync,
  ) {
    final songs = songsAsync.value?.items ?? [];

    // 排序模式和多选模式下隐藏操作按钮
    if (_isSortMode || _isSelectMode) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          // 播放全部按钮：限制最大宽度，但允许自适应
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: context.responsive<double>(
                  mobile: 200,
                  tablet: 240,
                  desktop: 280,
                  tv: 320,
                ),
              ),
              child: FilledButton.icon(
                onPressed:
                    songs.isEmpty ? null : () => _playAll(playlist, songs),
                icon: const Icon(Icons.play_arrow),
                label: const Text('播放全部'),
                style: FilledButton.styleFrom(
                  minimumSize: context.responsiveButtonMinSize,
                ),
              ),
            ),
          ),
          // 添加歌曲按钮
          ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _addSongs,
              icon: const Icon(Icons.add),
              label: const Text('添加歌曲'),
              style: OutlinedButton.styleFrom(
                minimumSize: context.responsiveButtonMinSize,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSongList(
    BuildContext context,
    Playlist playlist,
    List<Song> songs,
  ) {
    final isBuiltIn = playlist.isBuiltIn;

    if (songs.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptySongs(context, isBuiltIn));
    }

    // 排序模式：使用 ReorderableListView
    if (_isSortMode) {
      return SliverToBoxAdapter(
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _sortableSongs.length,
          onReorder: _onReorder,
          itemBuilder: (context, index) {
            final song = _sortableSongs[index];
            return _SongListTile(
              key: ValueKey(song.id),
              song: song,
              index: index + 1,
              onTap: () {},
              onRemove: () {},
              showDragHandle: true,
              showTrailing: false,
            );
          },
        ),
      );
    }

    // 多选模式：显示 Checkbox
    if (_isSelectMode) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final song = songs[index];
          final isSelected = _selectedSongIds.contains(song.id);
          return _SongListTile(
            song: song,
            index: index + 1,
            onTap: () => _toggleSongSelection(song.id),
            onRemove: () {},
            showCheckbox: true,
            isChecked: isSelected,
            onCheckChanged: (checked) => _toggleSongSelection(song.id),
            showTrailing: false,
          );
        }, childCount: songs.length),
      );
    }

    // 正常模式
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final song = songs[index];
        return _SongListTile(
          song: song,
          index: index + 1,
          onTap: () => _playSong(song, songs, index),
          onRemove: () => _removeSong(playlist.id, song),
        );
      }, childCount: songs.length),
    );
  }

  Widget _buildEmptySongs(BuildContext context, bool isBuiltIn) {
    return EmptyState(
      icon: Icons.music_off_outlined,
      title: '歌单暂无歌曲',
      subtitle: '添加一些喜欢的音乐吧',
      action: FilledButton.tonal(
        onPressed: _addSongs,
        child: const Text('添加歌曲'),
      ),
    );
  }

  Widget _buildError(String error) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ref.invalidate(playlistDetailProvider(_playlistIdInt));
                ref.invalidate(playlistSongsProvider(_playlistIdInt));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _getLabelName(String label) {
    switch (label) {
      case 'built_in':
        return '内置';
      case 'auto_created':
        return '自动创建';
      default:
        return label;
    }
  }

  /// 显示编辑对话框
  Future<void> _showEditDialog(Playlist playlist) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => _PlaylistEditDialog(
            playlist: playlist,
            playlistId: _playlistIdInt,
          ),
    );

    if (result == true && mounted) {
      // 刷新歌单详情
      ref.invalidate(playlistDetailProvider(_playlistIdInt));
    }
  }

  /// 添加歌曲
  Future<void> _addSongs() async {
    // 先确保已加载全部歌曲，得到完整的 excludeIds 防止重复添加
    await ref.read(playlistSongsProvider(_playlistIdInt).notifier).loadAll();
    if (!mounted) return;
    final currentSongs = ref.read(playlistSongsProvider(_playlistIdInt));
    final excludeIds =
        currentSongs.value?.items.map((s) => s.id).toSet() ?? <int>{};

    // 获取歌单类型，决定歌曲过滤：
    // - 电台歌单：只显示 radio 类型歌曲
    // - 非电台歌单：排除 radio 类型歌曲
    final playlist = ref.read(playlistDetailProvider(_playlistIdInt)).value;
    final isRadioPlaylist = playlist?.type == 'radio';

    // 打开歌曲选择器
    final selectedIds = await SongPickerModal.show(
      context,
      excludeIds: excludeIds,
      songType: isRadioPlaylist ? 'radio' : null,
      excludeType: isRadioPlaylist ? null : 'radio',
    );

    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;

    // 添加歌曲到歌单
    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.addSongsToPlaylist(
      _playlistIdInt,
      selectedIds,
    );

    if (success && mounted) {
      ResponsiveSnackBar.showSuccess(
        context,
        message: '已添加 ${selectedIds.length} 首歌曲',
      );
    } else if (mounted) {
      ResponsiveSnackBar.showError(context, message: '添加歌曲失败');
    }
  }

  /// 确认删除歌单
  Future<void> _confirmDelete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要删除歌单「${playlist.name}」吗？此操作不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      final notifier = ref.read(playlistNotifierProvider.notifier);
      final success = await notifier.deletePlaylist(playlist.id);

      if (success && mounted) {
        // 安全返回：检查是否有可弹出的路由
        if (context.canPop()) {
          context.pop();
        } else {
          // 没有返回栈时，跳转到歌单列表页
          context.go('/playlists');
        }
        ResponsiveSnackBar.showSuccess(context, message: '歌单已删除');
      }
    }
  }

  /// 播放全部（委托给 PlayerNotifier.playPlaylistById）
  Future<void> _playAll(Playlist playlist, List<Song> songs) async {
    if (songs.isEmpty) {
      ResponsiveSnackBar.show(context, message: '歌单为空');
      return;
    }
    final total = await ref
        .read(playerStateProvider.notifier)
        .playPlaylistById(playlist.id);
    if (!mounted) return;
    if (total < 0) {
      ResponsiveSnackBar.showError(context, message: '播放失败');
    } else if (total == 0) {
      ResponsiveSnackBar.show(context, message: '歌单为空');
    } else {
      ResponsiveSnackBar.show(context, message: '播放全部 $total 首歌曲');
    }
  }

  /// 播放单曲
  void _playSong(Song song, List<Song> songs, int index) {
    debugPrint('[Player] Play song: ${song.title} at index $index');
    ref
        .read(playerStateProvider.notifier)
        .playPlaylist(songs, startIndex: index);
    ResponsiveSnackBar.show(context, message: '播放：${song.title}');
  }

  /// 启动网络歌曲→本地歌曲转换
  Future<void> _startConvertToLocal() async {
    final api = ref.read(playlistApiProvider);
    try {
      await api.convertPlaylistToLocal(_playlistIdInt);
      if (!mounted) return;
      ResponsiveSnackBar.show(context, message: '转换任务已启动，请耐心等待');
      _pollConvertProgress(api);
    } on DioException catch (e) {
      if (!mounted) return;
      // 优先显示后端返回的友好提示(如"该歌单没有需要转换的网络歌曲")
      final data = e.response?.data;
      final backendMsg = data is Map ? data['error']?.toString() : null;
      final status = e.response?.statusCode ?? 0;
      if (backendMsg != null &&
          backendMsg.isNotEmpty &&
          status >= 400 &&
          status < 500) {
        ResponsiveSnackBar.show(context, message: backendMsg);
      } else {
        ResponsiveSnackBar.showError(
          context,
          message: '启动转换失败: ${e.message ?? e}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ResponsiveSnackBar.showError(context, message: '启动转换失败: $e');
    }
  }

  /// 轮询转换进度
  void _pollConvertProgress(PlaylistApi api) {
    _convertTimer?.cancel();
    Future<void> fetchOnce() async {
      try {
        final progress = await api.getConvertProgress(_playlistIdInt);
        if (!mounted) return;
        setState(() => _convertProgress = progress);
        if (progress.isFinished) {
          _convertTimer?.cancel();
          _convertTimer = null;
          // 转换完成后刷新歌曲列表
          ref.invalidate(playlistSongsProvider(_playlistIdInt));
        }
      } catch (e) {
        // 轮询失败保留 timer 继续重试,避免短暂网络抖动中断
      }
    }

    fetchOnce();
    _convertTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      fetchOnce();
    });
  }

  /// 取消转换
  Future<void> _cancelConvertToLocal() async {
    final api = ref.read(playlistApiProvider);
    try {
      await api.cancelConvert(_playlistIdInt);
      if (!mounted) return;
      ResponsiveSnackBar.show(context, message: '已请求取消');
    } catch (e) {
      if (!mounted) return;
      ResponsiveSnackBar.showError(context, message: '取消失败: $e');
    }
  }

  /// 从歌单移除歌曲
  Future<void> _removeSong(int playlistId, Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('移除歌曲'),
            content: Text('确定要从歌单中移除「${song.title}」吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('移除'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      final notifier = ref.read(playlistNotifierProvider.notifier);
      final success = await notifier.removeSongFromPlaylist(
        playlistId,
        song.id,
      );

      if (success && mounted) {
        ResponsiveSnackBar.showSuccess(context, message: '歌曲已移除');
      }
    }
  }
}

/// 歌曲列表项组件
class _SongListTile extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// 是否显示拖拽手柄（排序模式）
  final bool showDragHandle;

  /// 是否显示复选框（多选模式）
  final bool showCheckbox;

  /// 复选框是否选中
  final bool isChecked;

  /// 复选框状态变化回调
  final ValueChanged<bool?>? onCheckChanged;

  /// 是否显示尾部操作按钮（时长 + 更多菜单）
  final bool showTrailing;

  const _SongListTile({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
    required this.onRemove,
    this.showDragHandle = false,
    this.showCheckbox = false,
    this.isChecked = false,
    this.onCheckChanged,
    this.showTrailing = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final coverUrl = song.coverUrl;

    return ListTile(
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄（排序模式）
          if (showDragHandle)
            ReorderableDragStartListener(
              index: index - 1,
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          // 复选框（多选模式）
          else if (showCheckbox)
            SizedBox(
              width: 32,
              child: Checkbox(value: isChecked, onChanged: onCheckChanged),
            )
          // 序号（正常模式）
          else
            SizedBox(
              width: 32,
              child: Text(
                '$index',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(width: 8),
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 48,
              height: 48,
              child:
                  coverUrl != null
                      ? CachedNetworkImage(
                        imageUrl: UrlHelper.buildCoverUrl(coverUrl),
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) =>
                                _buildCoverPlaceholder(colorScheme),
                        errorWidget:
                            (context, url, error) =>
                                _buildCoverPlaceholder(colorScheme),
                      )
                      : _buildCoverPlaceholder(colorScheme),
            ),
          ),
        ],
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.artist ?? '未知艺术家',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing:
          showTrailing
              ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 时长
                  Text(
                    Formatters.formatDuration(song.duration),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // 更多按钮
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      if (value == 'remove') {
                        onRemove();
                      }
                    },
                    itemBuilder:
                        (context) => [
                          PopupMenuItem(
                            value: 'remove',
                            child: ListTile(
                              leading: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              title: Text(
                                '从歌单移除',
                                style: TextStyle(color: colorScheme.error),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                  ),
                ],
              )
              : null,
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: 24,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 歌单编辑对话框
class _PlaylistEditDialog extends ConsumerStatefulWidget {
  final Playlist playlist;
  final int playlistId;

  const _PlaylistEditDialog({required this.playlist, required this.playlistId});

  @override
  ConsumerState<_PlaylistEditDialog> createState() =>
      _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends ConsumerState<_PlaylistEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  /// 封面选择模式
  /// null: 未修改
  /// 'local': 本地上传的图片
  /// 'song': 从歌曲选择的封面
  /// 'clear': 清除封面
  String? _coverMode;

  /// 本地选择的文件
  PlatformFile? _localFile;

  /// 从歌曲选择的封面路径
  String? _selectedCoverPath;
  String? _selectedCoverUrl;

  /// 是否正在保存
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
    _descController = TextEditingController(text: widget.playlist.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// 获取当前预览的封面 URL
  String? get _previewCoverUrl {
    if (_coverMode == 'clear') return null;
    if (_coverMode == 'song') {
      return _selectedCoverUrl;
    }
    if (_coverMode == 'local') {
      return _localFile?.path;
    }
    // 未修改时显示原有封面
    if (_coverMode == null) {
      return widget.playlist.coverUrl;
    }
    return null;
  }

  /// 上传本地图片
  Future<void> _pickLocalImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _localFile = result.files.first;
          _coverMode = 'local';
        });
      }
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(context, message: '选择图片失败: $e');
      }
    }
  }

  /// 从歌曲选择封面
  Future<void> _pickFromSongs() async {
    final result = await showSongCoverPicker(context, widget.playlistId);
    if (result != null) {
      setState(() {
        _selectedCoverPath = result['coverPath'];
        _selectedCoverUrl = result['coverUrl'];
        _coverMode = 'song';
        _localFile = null;
      });
    }
  }

  /// 清除封面
  void _clearCover() {
    setState(() {
      _coverMode = 'clear';
      _localFile = null;
      _selectedCoverPath = null;
      _selectedCoverUrl = null;
    });
  }

  /// 保存
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ResponsiveSnackBar.showError(context, message: '请输入歌单名称');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(playlistNotifierProvider.notifier);
      final description = _descController.text.trim();
      // 处理封面上传
      if (_coverMode == 'local' && _localFile != null) {
        final file = _localFile!;
        final uploadedPlaylist = await notifier.uploadPlaylistCover(
          widget.playlistId,
          bytes: file.bytes,
          filePath: file.path,
          fileName: file.name,
        );
        if (uploadedPlaylist == null) {
          if (mounted) {
            ResponsiveSnackBar.showError(context, message: '封面上传失败');
          }
          return;
        }
        // 上传成功后更新其他信息，同时传递封面信息防止被后端覆盖
        await notifier.updatePlaylist(
          widget.playlistId,
          name: name,
          description: description.isEmpty ? null : description,
        );
      } else if (_coverMode == 'song') {
        // 从歌曲选择的封面
        await notifier.updatePlaylist(
          widget.playlistId,
          name: name,
          description: description.isEmpty ? null : description,
          coverPath: _selectedCoverPath ?? '',
        );
      } else if (_coverMode == 'clear') {
        // 清除封面
        await notifier.updatePlaylist(
          widget.playlistId,
          name: name,
          description: description.isEmpty ? null : description,
          coverPath: '',
        );
      } else {
        // 未修改封面，只更新名称和描述
        await notifier.updatePlaylist(
          widget.playlistId,
          name: name,
          description: description.isEmpty ? null : description,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ResponsiveSnackBar.showError(context, message: '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCover =
        _coverMode != 'clear' &&
        (_coverMode == 'local' ||
            _coverMode == 'song' ||
            widget.playlist.coverUrl?.isNotEmpty == true);
    return AlertDialog(
      title: Text(widget.playlist.isBuiltIn ? '修改封面' : '编辑歌单'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 封面预览区域
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildCoverPreview(colorScheme),
              ),
              const SizedBox(height: 12),
              // 封面操作按钮
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickLocalImage,
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('上传图片'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickFromSongs,
                    icon: const Icon(Icons.music_note, size: 18),
                    label: const Text('从歌曲选择'),
                  ),
                  if (hasCover)
                    TextButton.icon(
                      onPressed: _isSaving ? null : _clearCover,
                      icon: Icon(
                        Icons.clear,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      label: Text(
                        '清除',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // 歌单名称
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '歌单名称',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isSaving && !widget.playlist.isBuiltIn,
              ),
              const SizedBox(height: 16),
              // 歌单描述
              TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: '歌单描述',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                enabled: !_isSaving && !widget.playlist.isBuiltIn,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child:
              _isSaving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildCoverPreview(ColorScheme colorScheme) {
    // 本地文件预览
    if (_coverMode == 'local' && _localFile != null) {
      if (kIsWeb && _localFile!.bytes != null) {
        return Image.memory(_localFile!.bytes!, fit: BoxFit.cover);
      } else if (!kIsWeb && _localFile!.path != null) {
        return Image.file(File(_localFile!.path!), fit: BoxFit.cover);
      }
    }

    // 网络图片预览
    final previewUrl = _previewCoverUrl;
    if (previewUrl != null) {
      return CachedNetworkImage(
        imageUrl: previewUrl,
        fit: BoxFit.cover,
        placeholder:
            (context, url) =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (context, url, error) => _buildPlaceholder(colorScheme),
      );
    }

    // 占位图
    return _buildPlaceholder(colorScheme);
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.queue_music,
        size: 48,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
