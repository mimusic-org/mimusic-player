import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../shared/models/song.dart';
import '../domain/playlist.dart';

/// 歌单 API 客户端
class PlaylistApi {
  final Dio dio;

  PlaylistApi(this.dio);

  /// 获取歌单列表
  /// GET /api/v1/playlists?type=normal&limit=20&offset=0
  Future<PlaylistListResponse> getPlaylists({
    String? type,
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParams = <String, dynamic>{'limit': limit, 'offset': offset};
    if (type != null) {
      queryParams['type'] = type;
    }

    final response = await dio.get(
      '${AppConfig.apiPrefix}/playlists',
      queryParameters: queryParams,
    );
    return PlaylistListResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// 创建歌单
  /// POST /api/v1/playlists
  Future<Playlist> createPlaylist({
    required String type,
    required String name,
    String? description,
    String? coverPath,
  }) async {
    final data = <String, dynamic>{'type': type, 'name': name};
    if (description != null) {
      data['description'] = description;
    }
    if (coverPath != null) {
      data['cover_path'] = coverPath;
    }

    final response = await dio.post(
      '${AppConfig.apiPrefix}/playlists',
      data: data,
    );
    return Playlist.fromJson(response.data as Map<String, dynamic>);
  }

  /// 获取歌单详情
  /// GET /api/v1/playlists/{id}
  Future<Playlist> getPlaylist(int id) async {
    final response = await dio.get('${AppConfig.apiPrefix}/playlists/$id');
    return Playlist.fromJson(response.data as Map<String, dynamic>);
  }

  /// 更新歌单
  /// PUT /api/v1/playlists/{id}
  Future<Playlist> updatePlaylist(
    int id, {
    String? name,
    String? description,
    String? coverPath,
    String? coverUrl,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) {
      data['name'] = name;
    }
    if (description != null) {
      data['description'] = description;
    }
    if (coverPath != null) {
      data['cover_path'] = coverPath;
    }
    if (coverUrl != null) {
      data['cover_url'] = coverUrl;
    }

    final response = await dio.put(
      '${AppConfig.apiPrefix}/playlists/$id',
      data: data,
    );
    return Playlist.fromJson(response.data as Map<String, dynamic>);
  }

  /// 上传歌单封面图片
  /// Web 平台使用 bytes，原生平台使用 filePath
  /// POST /api/v1/playlists/{id}/cover
  Future<Playlist> uploadPlaylistCover(
    int playlistId, {
    Uint8List? bytes,
    String? filePath,
    required String fileName,
  }) async {
    late final MultipartFile multipartFile;
    if (bytes != null) {
      multipartFile = MultipartFile.fromBytes(bytes, filename: fileName);
    } else if (filePath != null) {
      multipartFile = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
      );
    } else {
      throw ArgumentError('Either bytes or filePath must be provided');
    }

    final formData = FormData.fromMap({'file': multipartFile});

    final response = await dio.post(
      '${AppConfig.apiPrefix}/playlists/$playlistId/cover',
      data: formData,
    );
    return Playlist.fromJson(response.data as Map<String, dynamic>);
  }

  /// 删除歌单
  /// DELETE /api/v1/playlists/{id}
  Future<void> deletePlaylist(int id) async {
    await dio.delete('${AppConfig.apiPrefix}/playlists/$id');
  }

  /// 获取歌单内歌曲
  /// GET /api/v1/playlists/{id}/songs?limit=20&offset=0
  Future<SongListResponse> getPlaylistSongs(
    int id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await dio.get(
      '${AppConfig.apiPrefix}/playlists/$id/songs',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return SongListResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// 向歌单添加歌曲
  /// POST /api/v1/playlists/{id}/songs
  Future<void> addSongsToPlaylist(int id, List<int> songIds) async {
    await dio.post(
      '${AppConfig.apiPrefix}/playlists/$id/songs',
      data: {'song_ids': songIds},
    );
  }

  /// 重新排序歌单内歌曲
  /// PUT /api/v1/playlists/{id}/songs/reorder
  Future<void> reorderPlaylistSongs(int id, List<int> songIds) async {
    await dio.put(
      '${AppConfig.apiPrefix}/playlists/$id/songs/reorder',
      data: {'song_ids': songIds},
    );
  }

  /// 重新排序歌单
  /// PUT /api/v1/playlists/reorder
  Future<void> reorderPlaylists(List<int> playlistIds) async {
    await dio.put(
      '${AppConfig.apiPrefix}/playlists/reorder',
      data: {'playlist_ids': playlistIds},
    );
  }

  /// 从歌单移除歌曲
  /// DELETE /api/v1/playlists/{id}/songs/{songId}
  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    await dio.delete(
      '${AppConfig.apiPrefix}/playlists/$playlistId/songs/$songId',
    );
  }

  /// 更新歌单最后访问时间
  /// POST /api/v1/playlists/{id}/touch
  Future<void> touchPlaylist(int id) async {
    await dio.post('${AppConfig.apiPrefix}/playlists/$id/touch');
  }

  /// 批量删除歌单
  /// POST /api/v1/playlists/batch-delete
  Future<Map<String, dynamic>> batchDeletePlaylists(List<int> ids) async {
    final response = await dio.post(
      '${AppConfig.apiPrefix}/playlists/batch-delete',
      data: {'ids': ids},
    );
    return response.data as Map<String, dynamic>;
  }

  /// 启动歌单的网络歌曲→本地歌曲转换
  /// POST /api/v1/playlists/{id}/convert-to-local
  Future<void> convertPlaylistToLocal(int playlistId) async {
    await dio.post(
      '${AppConfig.apiPrefix}/playlists/$playlistId/convert-to-local',
    );
  }

  /// 查询转换进度
  /// GET /api/v1/playlists/{id}/convert-progress
  Future<ConvertProgress> getConvertProgress(int playlistId) async {
    final response = await dio.get(
      '${AppConfig.apiPrefix}/playlists/$playlistId/convert-progress',
    );
    return ConvertProgress.fromJson(response.data as Map<String, dynamic>);
  }

  /// 取消转换
  /// POST /api/v1/playlists/{id}/convert-progress/cancel
  Future<bool> cancelConvert(int playlistId) async {
    final response = await dio.post(
      '${AppConfig.apiPrefix}/playlists/$playlistId/convert-progress/cancel',
    );
    final data = response.data as Map<String, dynamic>;
    return data['cancelled'] as bool? ?? false;
  }

  /// 获取自动转换开关
  /// GET /api/v1/settings/auto-convert
  Future<bool> getAutoConvertEnabled() async {
    final response = await dio.get(
      '${AppConfig.apiPrefix}/settings/auto-convert',
    );
    final data = response.data as Map<String, dynamic>;
    return data['enabled'] as bool? ?? false;
  }

  /// 设置自动转换开关
  /// PUT /api/v1/settings/auto-convert
  Future<bool> setAutoConvertEnabled(bool enabled) async {
    final response = await dio.put(
      '${AppConfig.apiPrefix}/settings/auto-convert',
      data: {'enabled': enabled},
    );
    final data = response.data as Map<String, dynamic>;
    return data['enabled'] as bool? ?? enabled;
  }
}

/// 转换进度
class ConvertProgress {
  final int playlistId;
  final String status;
  final int totalSongs;
  final int processedSongs;
  final int convertedSongs;
  final int skippedSongs;
  final int failedSongs;
  final String currentSong;
  final bool waiting;
  final List<String> errors;
  final String? error;

  const ConvertProgress({
    required this.playlistId,
    required this.status,
    required this.totalSongs,
    required this.processedSongs,
    required this.convertedSongs,
    required this.skippedSongs,
    required this.failedSongs,
    required this.currentSong,
    required this.waiting,
    required this.errors,
    this.error,
  });

  bool get isRunning => status == 'running';
  bool get isFinished =>
      status == 'completed' || status == 'failed' || status == 'cancelled';

  factory ConvertProgress.fromJson(Map<String, dynamic> json) {
    return ConvertProgress(
      playlistId: (json['playlist_id'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'idle',
      totalSongs: (json['total_songs'] as num?)?.toInt() ?? 0,
      processedSongs: (json['processed_songs'] as num?)?.toInt() ?? 0,
      convertedSongs: (json['converted_songs'] as num?)?.toInt() ?? 0,
      skippedSongs: (json['skipped_songs'] as num?)?.toInt() ?? 0,
      failedSongs: (json['failed_songs'] as num?)?.toInt() ?? 0,
      currentSong: json['current_song'] as String? ?? '',
      waiting: json['waiting'] as bool? ?? false,
      errors:
          (json['errors'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      error: (json['error'] as String?)?.isNotEmpty == true
          ? json['error'] as String
          : null,
    );
  }
}
