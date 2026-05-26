import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/constants.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/utils/url_helper.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../domain/playlist.dart';
import 'providers/playlist_provider.dart';
import 'providers/playlist_view_provider.dart';
import 'widgets/playlist_card.dart';
import 'widgets/playlist_list_item.dart';
import 'widgets/song_cover_picker_modal.dart';

/// 歌单列表页面
class PlaylistsPage extends ConsumerStatefulWidget {
  const PlaylistsPage({super.key});

  @override
  ConsumerState<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends ConsumerState<PlaylistsPage> {
  String? _selectedType;
  bool _isSelectionMode = false;
  final Set<int> _selectedPlaylistIds = {};

  /// 排序模式
  bool _isSortMode = false;
  List<Playlist> _sortablePlaylists = [];

  /// 触底加载预留距离（提前 300px 触发下一页加载）
  static const double _loadMoreThreshold = 300.0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听：接近底部时触发分页加载
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      ref.read(playlistListProvider(_selectedType).notifier).loadMore();
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedPlaylistIds.clear();
      }
    });
  }

  void _togglePlaylistSelection(Playlist playlist) {
    // 不允许选择内置歌单
    if (playlist.isBuiltIn) return;
    setState(() {
      if (_selectedPlaylistIds.contains(playlist.id)) {
        _selectedPlaylistIds.remove(playlist.id);
      } else {
        _selectedPlaylistIds.add(playlist.id);
      }
    });
  }

  void _selectAll(List<Playlist> playlists) {
    setState(() {
      final selectableIds =
          playlists.where((p) => !p.isBuiltIn).map((p) => p.id).toSet();
      if (_selectedPlaylistIds.containsAll(selectableIds)) {
        _selectedPlaylistIds.clear();
      } else {
        _selectedPlaylistIds.addAll(selectableIds);
      }
    });
  }

  /// 进入排序模式（确保所有歌单已加载）
  Future<void> _enterSortMode(List<Playlist> playlists) async {
    // 排序需要全部歌单在内存中，忽略类型筛选加载全部
    await ref.read(playlistListProvider(null).notifier).loadAll();
    if (!mounted) return;
    final fullPlaylists =
        ref.read(playlistListProvider(null)).value?.items ?? playlists;
    setState(() {
      _isSortMode = true;
      _isSelectionMode = false;
      _selectedPlaylistIds.clear();
      _sortablePlaylists = List.from(fullPlaylists);
    });
  }

  /// 退出排序模式并保存
  Future<void> _exitSortMode() async {
    final playlistIds = _sortablePlaylists.map((p) => p.id).toList();
    setState(() => _isSortMode = false);

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylists(playlistIds);

    if (mounted) {
      if (success) {
        ResponsiveSnackBar.showSuccess(context, message: '排序已保存');
      } else {
        ResponsiveSnackBar.showError(context, message: '排序保存失败');
      }
    }
  }

  /// 取消排序模式（不保存）
  void _cancelSortMode() {
    setState(() {
      _isSortMode = false;
      _sortablePlaylists = [];
    });
  }

  /// 自动按名称排序歌单
  Future<void> _autoSortByName(
    List<Playlist> playlists, {
    bool ascending = true,
  }) async {
    // 排序需要全部歌单在内存中
    await ref.read(playlistListProvider(null).notifier).loadAll();
    if (!mounted) return;
    final fullPlaylists =
        ref.read(playlistListProvider(null)).value?.items ?? playlists;

    final sorted = List<Playlist>.from(fullPlaylists);
    sorted.sort((a, b) {
      final result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return ascending ? result : -result;
    });

    final playlistIds = sorted.map((p) => p.id).toList();

    // 检查排序前后是否有变化
    final originalIds = fullPlaylists.map((p) => p.id).toList();
    if (_listEquals(playlistIds, originalIds)) {
      if (mounted) {
        ResponsiveSnackBar.show(context, message: '歌单已是该排序顺序');
      }
      return;
    }

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylists(playlistIds);

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

  /// 提取名称中第一个出现的数字
  int? _extractFirstNumber(String title) {
    final match = RegExp(r'(\d+)').firstMatch(title);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 自动按数字前缀排序歌单
  Future<void> _autoSortByNumberPrefix(List<Playlist> playlists) async {
    // 排序需要全部歌单在内存中
    await ref.read(playlistListProvider(null).notifier).loadAll();
    if (!mounted) return;
    final fullPlaylists =
        ref.read(playlistListProvider(null)).value?.items ?? playlists;

    final sorted = List<Playlist>.from(fullPlaylists);
    sorted.sort((a, b) {
      final numA = _extractFirstNumber(a.name);
      final numB = _extractFirstNumber(b.name);

      // 都有数字前缀：按数值排序
      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
        // 数值相同时按名称字母序
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      // 有数字前缀的排在前面
      if (numA != null) return -1;
      if (numB != null) return 1;
      // 都没有数字前缀：按名称字母序
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final playlistIds = sorted.map((p) => p.id).toList();

    // 检查排序前后是否有变化
    final originalIds = fullPlaylists.map((p) => p.id).toList();
    if (_listEquals(playlistIds, originalIds)) {
      if (mounted) {
        ResponsiveSnackBar.show(context, message: '歌单已是该排序顺序');
      }
      return;
    }

    final notifier = ref.read(playlistNotifierProvider.notifier);
    final success = await notifier.reorderPlaylists(playlistIds);

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

  /// 拖拽排序回调
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _sortablePlaylists.removeAt(oldIndex);
      _sortablePlaylists.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistListProvider(_selectedType));

    return Scaffold(
      appBar:
          _isSortMode
              ? _buildSortAppBar()
              : _isSelectionMode
              ? _buildSelectionAppBar(playlistsAsync)
              : _buildNormalAppBar(),
      body:
          _isSortMode
              ? _buildSortModeBody()
              : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(playlistListProvider(_selectedType));
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // 类型筛选
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SegmentedButton<String?>(
                          segments: const [
                            ButtonSegment(
                              value: null,
                              label: Text('全部'),
                              icon: Icon(Icons.list),
                            ),
                            ButtonSegment(
                              value: AppConstants.playlistTypeNormal,
                              label: Text('歌单'),
                              icon: Icon(Icons.queue_music),
                            ),
                            ButtonSegment(
                              value: AppConstants.playlistTypeRadio,
                              label: Text('电台'),
                              icon: Icon(Icons.radio),
                            ),
                          ],
                          selected: {_selectedType},
                          onSelectionChanged: (selected) {
                            setState(() {
                              _selectedType = selected.first;
                            });
                          },
                        ),
                      ),
                    ),

                    // 歌单列表
                    playlistsAsync.when(
                      data:
                          (state) =>
                              _buildPlaylistContent(context, state.items),
                      loading:
                          () => const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(64),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      error:
                          (error, stack) => SliverToBoxAdapter(
                            child: _buildErrorContent(error.toString()),
                          ),
                    ),

                    // 加载更多指示器（仅在 hasMore 或 isLoadingMore 时显示）
                    if (playlistsAsync.value != null)
                      SliverToBoxAdapter(
                        child: _buildLoadMoreIndicator(playlistsAsync.value!),
                      ),

                    // 底部安全区域
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 80,
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  /// 构建加载更多指示器（含错误重试）
  Widget _buildLoadMoreIndicator(PaginatedPlaylistsState state) {
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed:
                () =>
                    ref
                        .read(playlistListProvider(_selectedType).notifier)
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
    if (!state.hasMore && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '— 已全部加载（${state.items.length}） —',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  AppBar _buildNormalAppBar() {
    final playlistsAsync = ref.watch(playlistListProvider(_selectedType));
    final playlists = playlistsAsync.value?.items ?? [];

    return AppBar(
      title: const Text('歌单'),
      actions: [
        // 视图模式切换按钮
        IconButton(
          icon: Icon(
            ref.watch(playlistViewModeProvider) == PlaylistViewMode.grid
                ? Icons.view_list
                : Icons.grid_view,
          ),
          tooltip:
              ref.watch(playlistViewModeProvider) == PlaylistViewMode.grid
                  ? '切换到列表视图'
                  : '切换到卡片视图',
          onPressed: () {
            ref.read(playlistViewModeProvider.notifier).toggleViewMode();
          },
        ),
        // 排序按钮（含自动排序选项）
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: '排序',
          onSelected: (value) {
            switch (value) {
              case 'name_asc':
                _autoSortByName(playlists, ascending: true);
              case 'name_desc':
                _autoSortByName(playlists, ascending: false);
              case 'number_asc':
                _autoSortByNumberPrefix(playlists);
              case 'manual':
                _enterSortMode(playlists);
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
        // 多选模式按钮
        IconButton(
          icon: const Icon(Icons.checklist),
          tooltip: '多选',
          onPressed: _toggleSelectMode,
        ),
        // 更多菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多',
          onSelected: (value) {
            switch (value) {
              case 'create':
                _showCreateDialog();
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(
                  value: 'create',
                  child: ListTile(
                    leading: Icon(Icons.add),
                    title: Text('创建歌单'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
        ),
      ],
    );
  }

  AppBar _buildSortAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: '取消',
        onPressed: _cancelSortMode,
      ),
      title: const Text('排序歌单'),
      actions: [TextButton(onPressed: _exitSortMode, child: const Text('完成'))],
    );
  }

  /// 排序模式下的主体内容
  Widget _buildSortModeBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_sortablePlaylists.isEmpty) {
      return const Center(child: Text('暂无歌单'));
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _sortablePlaylists.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        final playlist = _sortablePlaylists[index];
        final coverUrl = playlist.coverUrl;
        return Card(
          key: ValueKey(playlist.id),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // 序号
                SizedBox(
                  width: 32,
                  child: Text(
                    '${index + 1}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child:
                        coverUrl != null
                            ? CachedNetworkImage(
                              imageUrl: UrlHelper.buildCoverUrl(coverUrl),
                              fit: BoxFit.cover,
                              placeholder:
                                  (context, url) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.queue_music,
                                      size: 24,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.queue_music,
                                      size: 24,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                            )
                            : Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  playlist.type == 'radio'
                                      ? Icons.radio
                                      : Icons.queue_music,
                                  size: 24,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 12),
                // 歌单信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.songCount} 首歌曲',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 拖拽手柄
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _buildSelectionAppBar(
    AsyncValue<PaginatedPlaylistsState> playlistsAsync,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _toggleSelectMode,
      ),
      title: Text('已选择 ${_selectedPlaylistIds.length} 个'),
      actions: [
        // 删除按钮
        TextButton.icon(
          icon: Icon(
            Icons.delete,
            color:
                _selectedPlaylistIds.isEmpty
                    ? null
                    : Theme.of(context).colorScheme.error,
          ),
          label: Text(
            '删除(${_selectedPlaylistIds.length})',
            style: TextStyle(
              color:
                  _selectedPlaylistIds.isEmpty
                      ? null
                      : Theme.of(context).colorScheme.error,
            ),
          ),
          onPressed: _selectedPlaylistIds.isEmpty ? null : _confirmBatchDelete,
        ),
        // 全选按钮（先确保全部歌单已加载，再全选）
        TextButton(
          onPressed: () async {
            await ref
                .read(playlistListProvider(_selectedType).notifier)
                .loadAll();
            final state = ref.read(playlistListProvider(_selectedType)).value;
            if (state != null) {
              _selectAll(state.items);
            }
          },
          child: const Text('全选'),
        ),
      ],
    );
  }

  Widget _buildPlaylistContent(BuildContext context, List<Playlist> playlists) {
    if (playlists.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyContent());
    }

    final viewMode = ref.watch(playlistViewModeProvider);

    if (viewMode == PlaylistViewMode.list) {
      return _buildListView(context, playlists);
    } else {
      return _buildGridView(context, playlists);
    }
  }

  Widget _buildGridView(BuildContext context, List<Playlist> playlists) {
    final crossAxisCount = context.responsive<int>(
      mobile: 2,
      tablet: 3,
      desktop: 4,
      tv: 5,
    );

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final playlist = playlists[index];
          return PlaylistCard(
            playlist: playlist,
            onTap: () => context.push('/playlists/${playlist.id}'),
            onEdit: () => _showEditDialog(playlist),
            onDelete:
                playlist.isBuiltIn ? null : () => _confirmDelete(playlist),
            onPlayAll: () => _playAll(playlist),
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedPlaylistIds.contains(playlist.id),
            onSelect: () => _togglePlaylistSelection(playlist),
          );
        }, childCount: playlists.length),
      ),
    );
  }

  Widget _buildListView(BuildContext context, List<Playlist> playlists) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final playlist = playlists[index];
          return PlaylistListItem(
            playlist: playlist,
            onTap: () => context.push('/playlists/${playlist.id}'),
            onEdit: () => _showEditDialog(playlist),
            onDelete:
                playlist.isBuiltIn ? null : () => _confirmDelete(playlist),
            onPlayAll: () => _playAll(playlist),
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedPlaylistIds.contains(playlist.id),
            onSelect: () => _togglePlaylistSelection(playlist),
          );
        }, childCount: playlists.length),
      ),
    );
  }

  Widget _buildEmptyContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无歌单',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角按钮创建歌单',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorContent(String error) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
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
              onPressed:
                  () => ref.invalidate(playlistListProvider(_selectedType)),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示创建歌单对话框
  Future<void> _showCreateDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _PlaylistFormDialog(title: '创建歌单'),
    );

    if (result != null && mounted) {
      final notifier = ref.read(playlistNotifierProvider.notifier);
      final playlist = await notifier.createPlaylist(
        type: result['type'] as String,
        name: result['name'] as String,
        description: result['description'] as String?,
      );

      if (playlist != null && mounted) {
        ResponsiveSnackBar.showSuccess(context, message: '歌单创建成功');
      }
    }
  }

  /// 显示编辑歌单对话框
  Future<void> _showEditDialog(Playlist playlist) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => _PlaylistFormDialog(
            title: playlist.isBuiltIn ? '修改封面' : '编辑歌单',
            initialName: playlist.name,
            initialDescription: playlist.description,
            initialType: playlist.type,

            initialCoverUrl: playlist.coverUrl,
            playlistId: playlist.id,
            isEdit: true,
            isBuiltIn: playlist.isBuiltIn,
          ),
    );

    if (result != null && mounted) {
      final notifier = ref.read(playlistNotifierProvider.notifier);

      // 处理封面
      final coverMode = result['coverMode'] as String?;
      final localFile = result['localFile'] as PlatformFile?;
      final selectedCoverPath = result['selectedCoverPath'] as String?;
      final selectedCoverUrl = result['selectedCoverUrl'] as String?;

      if (coverMode == 'local' && localFile != null) {
        // 上传本地图片
        final uploadedPlaylist = await notifier.uploadPlaylistCover(
          playlist.id,
          bytes: localFile.bytes,
          filePath: localFile.path,
          fileName: localFile.name,
        );
        if (uploadedPlaylist == null && mounted) {
          ResponsiveSnackBar.showError(context, message: '封面上传失败');
          return;
        }
        // 更新其他信息，同时传递封面信息防止被后端覆盖
        final updated = await notifier.updatePlaylist(
          playlist.id,
          name: result['name'] as String,
          description: result['description'] as String?,

          coverUrl: uploadedPlaylist?.coverUrl,
        );

        if (updated != null && mounted) {
          ResponsiveSnackBar.showSuccess(context, message: '歌单更新成功');
        }
      } else if (coverMode == 'song') {
        // 从歌曲选择的封面
        final updated = await notifier.updatePlaylist(
          playlist.id,
          name: result['name'] as String,
          description: result['description'] as String?,
          coverPath: selectedCoverPath ?? '',
          coverUrl: selectedCoverUrl ?? '',
        );

        if (updated != null && mounted) {
          ResponsiveSnackBar.showSuccess(context, message: '歌单更新成功');
        }
      } else if (coverMode == 'clear') {
        // 清除封面
        final updated = await notifier.updatePlaylist(
          playlist.id,
          name: result['name'] as String,
          description: result['description'] as String?,
          coverPath: '',
          coverUrl: '',
        );

        if (updated != null && mounted) {
          ResponsiveSnackBar.showSuccess(context, message: '歌单更新成功');
        }
      } else {
        // 未修改封面
        final updated = await notifier.updatePlaylist(
          playlist.id,
          name: result['name'] as String,
          description: result['description'] as String?,
        );

        if (updated != null && mounted) {
          ResponsiveSnackBar.showSuccess(context, message: '歌单更新成功');
        }
      }
    }
  }

  /// 批量删除确认弹窗
  Future<void> _confirmBatchDelete() async {
    final count = _selectedPlaylistIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认批量删除'),
            content: Text('确定要删除选中的 $count 个歌单吗？此操作不可恢复。'),
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
      final deleted = await notifier.batchDeletePlaylists(
        _selectedPlaylistIds.toList(),
      );

      if (mounted) {
        if (deleted > 0) {
          ResponsiveSnackBar.showSuccess(context, message: '已删除 $deleted 个歌单');
        } else {
          ResponsiveSnackBar.showError(context, message: '删除失败');
        }
        setState(() {
          _isSelectionMode = false;
          _selectedPlaylistIds.clear();
        });
      }
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
        ResponsiveSnackBar.showSuccess(context, message: '歌单已删除');
      }
    }
  }

  /// 播放歌单全部歌曲（委托给 PlayerNotifier.playPlaylistById）
  Future<void> _playAll(Playlist playlist) async {
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
}

/// 歌单表单对话框
class _PlaylistFormDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialDescription;
  final String? initialType;
  final String? initialCoverPath;
  final String? initialCoverUrl;
  final int? playlistId;
  final bool isEdit;
  final bool isBuiltIn;

  const _PlaylistFormDialog({
    required this.title,
    this.initialName,
    this.initialDescription,
    this.initialType,
    this.initialCoverPath,
    this.initialCoverUrl,
    this.playlistId,
    this.isEdit = false,
    this.isBuiltIn = false,
  });

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _type;
  final _formKey = GlobalKey<FormState>();

  /// 封面选择模式（仅编辑模式）
  String? _coverMode;
  PlatformFile? _localFile;
  String? _selectedCoverPath;
  String? _selectedCoverUrl;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _type = widget.initialType ?? AppConstants.playlistTypeNormal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 获取当前预览的封面 URL
  String? get _previewCoverUrl {
    if (_coverMode == 'clear') return null;
    if (_coverMode == 'song') {
      return _selectedCoverUrl;
    }
    // 未修改时显示原有封面
    if (_coverMode == null) {
      return widget.initialCoverUrl;
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
    if (widget.playlistId == null) return;
    final result = await showSongCoverPicker(context, widget.playlistId!);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCover =
        _coverMode != 'clear' &&
        (_coverMode == 'local' ||
            _coverMode == 'song' ||
            widget.initialCoverPath?.isNotEmpty == true ||
            widget.initialCoverUrl?.isNotEmpty == true);
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 编辑模式显示封面选择
                if (widget.isEdit) ...[
                  // 封面预览区域
                  Container(
                    width: 100,
                    height: 100,
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
                        onPressed: _pickLocalImage,
                        icon: const Icon(Icons.upload, size: 18),
                        label: const Text('上传图片'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickFromSongs,
                        icon: const Icon(Icons.music_note, size: 18),
                        label: const Text('从歌曲选择'),
                      ),
                      if (hasCover)
                        TextButton.icon(
                          onPressed: _clearCover,
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
                ],
                // 歌单名称
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '歌单名称',
                    hintText: '请输入歌单名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入歌单名称';
                    }
                    return null;
                  },
                  autofocus: !widget.isEdit,
                  enabled: !widget.isBuiltIn,
                ),
                const SizedBox(height: 16),
                // 歌单描述
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '歌单描述',
                    hintText: '请输入歌单描述（可选）',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  enabled: !widget.isBuiltIn,
                ),
                const SizedBox(height: 16),
                // 歌单类型（仅创建时可选）
                if (!widget.isEdit)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: AppConstants.playlistTypeNormal,
                        label: Text('普通歌单'),
                        icon: Icon(Icons.queue_music),
                      ),
                      ButtonSegment(
                        value: AppConstants.playlistTypeRadio,
                        label: Text('电台歌单'),
                        icon: Icon(Icons.radio),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _type = selected.first;
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
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
        imageUrl: UrlHelper.buildCoverUrl(previewUrl),
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
        size: 40,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      final Map<String, dynamic> result = {
        'name': _nameController.text.trim(),
        'description':
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        'type': _type,
      };

      // 编辑模式时添加封面信息
      if (widget.isEdit) {
        result['coverMode'] = _coverMode;
        result['localFile'] = _localFile;
        result['selectedCoverPath'] = _selectedCoverPath;
        result['selectedCoverUrl'] = _selectedCoverUrl;
      }

      Navigator.of(context).pop(result);
    }
  }
}
