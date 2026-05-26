import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../shared/models/song.dart';
import '../domain/playlist.dart';
import 'playlist_api.dart';

/// 歌单仓库
/// 封装 API 调用，添加错误处理
class PlaylistRepository {
  final PlaylistApi playlistApi;

  PlaylistRepository(this.playlistApi);

  /// 获取歌单列表
  Future<PlaylistListResponse> getPlaylists({
    String? type,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      return await playlistApi.getPlaylists(
        type: type,
        limit: limit,
        offset: offset,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 创建歌单
  Future<Playlist> createPlaylist({
    required String type,
    required String name,
    String? description,
    String? coverPath,
  }) async {
    try {
      return await playlistApi.createPlaylist(
        type: type,
        name: name,
        description: description,
        coverPath: coverPath,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 获取歌单详情
  Future<Playlist> getPlaylist(int id) async {
    try {
      return await playlistApi.getPlaylist(id);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 更新歌单
  Future<Playlist> updatePlaylist(
    int id, {
    String? name,
    String? description,
    String? coverPath,
    String? coverUrl,
  }) async {
    try {
      return await playlistApi.updatePlaylist(
        id,
        name: name,
        description: description,
        coverPath: coverPath,
        coverUrl: coverUrl,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 上传歌单封面图片
  Future<Playlist> uploadPlaylistCover(
    int playlistId, {
    Uint8List? bytes,
    String? filePath,
    required String fileName,
  }) async {
    try {
      return await playlistApi.uploadPlaylistCover(
        playlistId,
        bytes: bytes,
        filePath: filePath,
        fileName: fileName,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 删除歌单
  Future<void> deletePlaylist(int id) async {
    try {
      await playlistApi.deletePlaylist(id);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 获取歌单内歌曲
  Future<SongListResponse> getPlaylistSongs(
    int id, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      return await playlistApi.getPlaylistSongs(
        id,
        limit: limit,
        offset: offset,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 向歌单添加歌曲
  Future<void> addSongsToPlaylist(int id, List<int> songIds) async {
    try {
      await playlistApi.addSongsToPlaylist(id, songIds);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 重新排序歌单内歌曲
  Future<void> reorderPlaylistSongs(int id, List<int> songIds) async {
    try {
      await playlistApi.reorderPlaylistSongs(id, songIds);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 重新排序歌单
  Future<void> reorderPlaylists(List<int> playlistIds) async {
    try {
      await playlistApi.reorderPlaylists(playlistIds);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 从歌单移除歌曲
  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    try {
      await playlistApi.removeSongFromPlaylist(playlistId, songId);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 更新歌单最后访问时间
  Future<void> touchPlaylist(int id) async {
    try {
      await playlistApi.touchPlaylist(id);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 批量删除歌单
  Future<int> batchDeletePlaylists(List<int> ids) async {
    try {
      final result = await playlistApi.batchDeletePlaylists(ids);
      return result['deleted'] as int? ?? 0;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 处理 Dio 异常
  Exception _handleError(DioException e) {
    final response = e.response;
    if (response != null) {
      final statusCode = response.statusCode;
      final data = response.data;
      String message = '请求失败';
      if (data is Map<String, dynamic> && data.containsKey('error')) {
        message = data['error'] as String;
      } else if (data is Map<String, dynamic> && data.containsKey('message')) {
        message = data['message'] as String;
      }
      return PlaylistException(message, statusCode: statusCode);
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return PlaylistException('网络连接超时');
      case DioExceptionType.connectionError:
        return PlaylistException('网络连接失败');
      case DioExceptionType.cancel:
        return PlaylistException('请求已取消');
      default:
        return PlaylistException('网络错误: ${e.message}');
    }
  }
}

/// 歌单异常
class PlaylistException implements Exception {
  final String message;
  final int? statusCode;

  PlaylistException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
