import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../shared/models/song.dart';
import '../../data/playlist_api.dart';
import '../../data/playlist_repository.dart';
import '../../domain/playlist.dart';

/// Playlist API Provider
final playlistApiProvider = Provider<PlaylistApi>((ref) {
  final dio = ref.watch(dioProvider);
  return PlaylistApi(dio);
});

/// Playlist Repository Provider
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final playlistApi = ref.watch(playlistApiProvider);
  return PlaylistRepository(playlistApi);
});

// ============================================================
// 分页状态
// ============================================================

/// 歌单列表分页状态
class PaginatedPlaylistsState {
  /// 已加载的全部歌单（按加载顺序拼接）
  final List<Playlist> items;

  /// 后端返回的歌单总数
  final int totalCount;

  /// 是否还有更多页可加载
  final bool hasMore;

  /// 是否正在加载下一页
  final bool isLoadingMore;

  /// 加载下一页时发生的错误（仅追加加载阶段，初次加载错误走 AsyncValue.error）
  final Object? loadMoreError;

  const PaginatedPlaylistsState({
    this.items = const [],
    this.totalCount = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  PaginatedPlaylistsState copyWith({
    List<Playlist>? items,
    int? totalCount,
    bool? hasMore,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) {
    return PaginatedPlaylistsState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// 歌单内歌曲分页状态
class PaginatedSongsState {
  final List<Song> items;
  final int total;
  final bool hasMore;
  final bool isLoadingMore;
  final Object? loadMoreError;

  const PaginatedSongsState({
    this.items = const [],
    this.total = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  PaginatedSongsState copyWith({
    List<Song>? items,
    int? total,
    bool? hasMore,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) {
    return PaginatedSongsState(
      items: items ?? this.items,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

// ============================================================
// 歌单列表 Provider（滚动分页）
// ============================================================

/// 歌单列表分页 Notifier。
///
/// - 初次进入加载首页（pageLimit 条），状态由 `AsyncValue.loading` 切换为 `AsyncValue.data`。
/// - 滚动到列表底部时调用 [loadMore] 加载下一页。
/// - 需要拿到全部歌单的场景（如全选）调用 [loadAll]。
/// - 后端 ListPlaylists 响应不返回 total，使用"页数据小于 pageLimit"判断末页。
class PaginatedPlaylistsNotifier
    extends AsyncNotifier<PaginatedPlaylistsState> {
  PaginatedPlaylistsNotifier(this._typeArg);

  /// family 参数：歌单类型过滤（null 表示全部）
  final String? _typeArg;

  /// 每页大小
  static const int pageLimit = 30;

  @override
  Future<PaginatedPlaylistsState> build() async {
    final repository = ref.watch(playlistRepositoryProvider);
    final response = await repository.getPlaylists(
      type: _typeArg,
      limit: pageLimit,
      offset: 0,
    );
    return PaginatedPlaylistsState(
      items: response.playlists,
      totalCount: response.total,
      hasMore: response.playlists.length >= pageLimit,
      isLoadingMore: false,
    );
  }

  /// 触底加载下一页
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = AsyncValue.data(
      current.copyWith(isLoadingMore: true, clearError: true),
    );

    try {
      final repository = ref.read(playlistRepositoryProvider);
      final response = await repository.getPlaylists(
        type: _typeArg,
        limit: pageLimit,
        offset: current.items.length,
      );
      final merged = [...current.items, ...response.playlists];
      state = AsyncValue.data(
        current.copyWith(
          items: merged,
          totalCount: response.total,
          hasMore: response.playlists.length >= pageLimit,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        current.copyWith(isLoadingMore: false, loadMoreError: e),
      );
    }
  }

  /// 串行加载剩余全部页（供需要全量数据的场景调用，如全选）
  Future<void> loadAll() async {
    while (true) {
      final s = state.value;
      if (s == null || !s.hasMore || s.isLoadingMore) break;
      await loadMore();
      // loadMore 失败时停止以避免死循环
      if (state.value?.loadMoreError != null) break;
    }
  }
}

/// 歌单列表 Provider（family 参数为 type 过滤）
final playlistListProvider = AsyncNotifierProvider.family<
  PaginatedPlaylistsNotifier,
  PaginatedPlaylistsState,
  String?
>(PaginatedPlaylistsNotifier.new);

// ============================================================
// 歌单详情 Provider
// ============================================================

/// 获取歌单详情 Provider
final playlistDetailProvider = FutureProvider.family<Playlist, int>((
  ref,
  id,
) async {
  final repository = ref.watch(playlistRepositoryProvider);
  return repository.getPlaylist(id);
});

// ============================================================
// 歌单内歌曲 Provider（滚动分页）
// ============================================================

/// 歌单内歌曲分页 Notifier。
///
/// - 初次加载首页（pageLimit 条）。
/// - 列表滚动到底部时 [loadMore] 加载下一页。
/// - 需要全部歌曲的场景（手动排序、获取已存在歌曲 ID 用于去重等）调用 [loadAll]。
/// - 后端响应包含 total 字段，因此通过 `items.length < total` 判断是否还有更多。
class PaginatedSongsNotifier extends AsyncNotifier<PaginatedSongsState> {
  PaginatedSongsNotifier(this._playlistId);

  /// family 参数：歌单 ID
  final int _playlistId;

  /// 每页大小
  static const int pageLimit = 100;

  @override
  Future<PaginatedSongsState> build() async {
    final repository = ref.watch(playlistRepositoryProvider);
    final response = await repository.getPlaylistSongs(
      _playlistId,
      limit: pageLimit,
      offset: 0,
    );
    return PaginatedSongsState(
      items: response.songs,
      total: response.total,
      hasMore: response.songs.length < response.total,
      isLoadingMore: false,
    );
  }

  /// 触底加载下一页
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = AsyncValue.data(
      current.copyWith(isLoadingMore: true, clearError: true),
    );

    try {
      final repository = ref.read(playlistRepositoryProvider);
      final response = await repository.getPlaylistSongs(
        _playlistId,
        limit: pageLimit,
        offset: current.items.length,
      );
      if (response.songs.isEmpty) {
        state = AsyncValue.data(
          current.copyWith(
            hasMore: false,
            isLoadingMore: false,
            clearError: true,
          ),
        );
        return;
      }
      final merged = [...current.items, ...response.songs];
      state = AsyncValue.data(
        current.copyWith(
          items: merged,
          hasMore: merged.length < current.total,
          isLoadingMore: false,
          clearError: true,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        current.copyWith(isLoadingMore: false, loadMoreError: e),
      );
    }
  }

  /// 串行加载剩余全部页
  Future<void> loadAll() async {
    while (true) {
      final s = state.value;
      if (s == null || !s.hasMore || s.isLoadingMore) break;
      await loadMore();
      if (state.value?.loadMoreError != null) break;
    }
  }
}

/// 歌单内歌曲 Provider（family 参数为 playlistId）
final playlistSongsProvider = AsyncNotifierProvider.family<
  PaginatedSongsNotifier,
  PaginatedSongsState,
  int
>(PaginatedSongsNotifier.new);

// ============================================================
// 歌单操作 Notifier
// ============================================================

/// 歌单操作 Notifier
class PlaylistNotifier extends Notifier<AsyncValue<void>> {
  late PlaylistRepository _repository;

  @override
  AsyncValue<void> build() {
    _repository = ref.watch(playlistRepositoryProvider);
    return const AsyncValue.data(null);
  }

  /// 创建歌单
  Future<Playlist?> createPlaylist({
    required String type,
    required String name,
    String? description,
    String? coverPath,
  }) async {
    state = const AsyncValue.loading();
    try {
      final playlist = await _repository.createPlaylist(
        type: type,
        name: name,
        description: description,
        coverPath: coverPath,
      );
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return playlist;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 更新歌单
  Future<Playlist?> updatePlaylist(
    int id, {
    String? name,
    String? description,
    String? coverPath,
    String? coverUrl,
  }) async {
    state = const AsyncValue.loading();
    try {
      final playlist = await _repository.updatePlaylist(
        id,
        name: name,
        description: description,
        coverPath: coverPath,
        coverUrl: coverUrl,
      );
      state = const AsyncValue.data(null);
      // 刷新歌单详情和列表
      ref.invalidate(playlistDetailProvider(id));
      ref.invalidate(playlistListProvider);
      return playlist;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 上传歌单封面图片
  Future<Playlist?> uploadPlaylistCover(
    int playlistId, {
    Uint8List? bytes,
    String? filePath,
    required String fileName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final playlist = await _repository.uploadPlaylistCover(
        playlistId,
        bytes: bytes,
        filePath: filePath,
        fileName: fileName,
      );
      state = const AsyncValue.data(null);
      // 刷新相关 Provider
      ref.invalidate(playlistDetailProvider(playlistId));
      ref.invalidate(playlistListProvider);
      return playlist;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// 删除歌单
  Future<bool> deletePlaylist(int id) async {
    state = const AsyncValue.loading();
    try {
      await _repository.deletePlaylist(id);
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 向歌单添加歌曲
  Future<bool> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      await _repository.addSongsToPlaylist(playlistId, songIds);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 从歌单移除歌曲
  Future<bool> removeSongFromPlaylist(int playlistId, int songId) async {
    state = const AsyncValue.loading();
    try {
      await _repository.removeSongFromPlaylist(playlistId, songId);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 重新排序歌单歌曲
  Future<bool> reorderPlaylistSongs(int playlistId, List<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      await _repository.reorderPlaylistSongs(playlistId, songIds);
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 重新排序歌单
  Future<bool> reorderPlaylists(List<int> playlistIds) async {
    state = const AsyncValue.loading();
    try {
      await _repository.reorderPlaylists(playlistIds);
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 批量移除歌曲
  Future<bool> batchRemoveSongs(int playlistId, Set<int> songIds) async {
    state = const AsyncValue.loading();
    try {
      for (final songId in songIds) {
        await _repository.removeSongFromPlaylist(playlistId, songId);
      }
      state = const AsyncValue.data(null);
      // 刷新歌单歌曲列表
      ref.invalidate(playlistSongsProvider(playlistId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// 批量删除歌单
  Future<int> batchDeletePlaylists(List<int> ids) async {
    state = const AsyncValue.loading();
    try {
      final deleted = await _repository.batchDeletePlaylists(ids);
      state = const AsyncValue.data(null);
      // 刷新歌单列表
      ref.invalidate(playlistListProvider);
      return deleted;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return 0;
    }
  }

  /// 更新歌单最后访问时间
  Future<void> touchPlaylist(int id) async {
    try {
      await _repository.touchPlaylist(id);
    } catch (_) {
      // 忽略错误
    }
  }
}

/// 歌单操作 Provider
final playlistNotifierProvider =
    NotifierProvider<PlaylistNotifier, AsyncValue<void>>(PlaylistNotifier.new);
