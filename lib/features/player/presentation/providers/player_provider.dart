import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:volume_controller/volume_controller.dart';

import '../../../../core/audio/audio_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../../main.dart';
import '../../../../shared/models/song.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../library/data/songs_api.dart';
import '../../../library/presentation/providers/songs_provider.dart';
import '../../../playlist/data/playlist_api.dart';
import '../../../playlist/presentation/providers/playlist_provider.dart';
import '../../domain/player_state.dart';

/// 播放器状态 Provider
final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);

/// 播放器状态管理 Notifier
class PlayerNotifier extends Notifier<PlayerState> {
  late SongloftAudioHandler _audioHandler;
  late SecureStorageService _secureStorage;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<ja.PlayerState>? _playerStateSubscription;
  StreamSubscription<double>? _systemVolumeSubscription;

  Timer? _sleepTimer;
  Timer? _sleepTimerCountdown;
  CancelToken? _prefetchCancelToken;

  final Random _random = Random();
  final Set<int> _playedIndices = {}; // 随机模式下已播放的索引
  int _loadGeneration = 0; // 后台加载代次，用于取消过期的异步加载任务
  int? _preSelectedNextIndex; // 预选的下一首歌曲索引（随机模式使用）

  // 播放失败重试配置
  static const int _maxRetryPerSong = 2; // N1: 单首歌曲最大重试次数
  static const int _maxConsecutiveSkips = 3; // N2: 连续跳过失败上限
  static const int _retryDelayMs = 1000; // 重试间隔（毫秒）

  int _consecutiveFailures = 0; // 连续跳过失败计数器

  @override
  PlayerState build() {
    _audioHandler = ref.watch(audioHandlerProvider);
    _secureStorage = ref.watch(secureStorageProvider);

    // 设置通知栏回调
    _audioHandler.onSkipToNext = () => playNext();
    _audioHandler.onSkipToPrevious = () => playPrev();
    _audioHandler.onSongCompleted = _onSongCompleted;

    _initListeners();
    ref.onDispose(() {
      _positionSubscription?.cancel();
      _durationSubscription?.cancel();
      _playerStateSubscription?.cancel();
      _systemVolumeSubscription?.cancel();
      _sleepTimer?.cancel();
      _sleepTimerCountdown?.cancel();
      _prefetchCancelToken?.cancel('disposed');
    });

    // 从本地存储加载音量和播放模式设置
    _loadPreferences();

    return PlayerState.initial;
  }

  /// 从本地存储加载播放器偏好设置
  Future<void> _loadPreferences() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      final playModeString = prefs.getPlayMode();
      final playMode = PlayMode.fromString(playModeString);

      debugPrint('[Player] Loaded preferences: playMode=$playModeString');

      // 更新播放模式
      state = state.copyWith(playMode: playMode);

      // 加载系统音量（非 Web 平台）
      if (!kIsWeb) {
        VolumeController().showSystemUI = false;
        final systemVolume = await VolumeController().getVolume();
        state = state.copyWith(volume: (systemVolume * 100).clamp(0.0, 100.0));
      }

      // 固定 just_audio 播放器音量为最大
      await _audioHandler.setVolume(1.0);
    } catch (e) {
      debugPrint('[Player] Failed to load preferences: $e');
      // 加载失败使用默认值，仍然固定 just_audio 音量
      await _audioHandler.setVolume(1.0);
    }
  }

  /// 初始化监听器
  void _initListeners() {
    // 监听播放位置
    _positionSubscription = _audioHandler.positionStream.listen((position) {
      state = state.copyWith(currentTime: position);
    });

    // 监听总时长
    _durationSubscription = _audioHandler.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);
        // 同时更新通知栏的 duration
        _audioHandler.updateDuration(duration);
      }
    });

    // 监听播放状态
    _playerStateSubscription = _audioHandler.playerStateStream.listen((
      playerState,
    ) {
      state = state.copyWith(
        isPlaying: playerState.playing,
        isBuffering:
            playerState.processingState == ja.ProcessingState.buffering ||
            playerState.processingState == ja.ProcessingState.loading,
      );
    });
    // 歌曲结束通过 _audioHandler.onSongCompleted 回调处理

    // 监听系统音量变化（非 Web 平台）
    if (!kIsWeb) {
      _systemVolumeSubscription = VolumeController().listener((volume) {
        // volume 是 0.0-1.0，转换为 0-100
        final volumePercent = (volume * 100).clamp(0.0, 100.0);
        if ((volumePercent - state.volume).abs() > 0.5) {
          state = state.copyWith(
            volume: volumePercent,
            clearPreviousVolume: true,
          );
        }
      });
    }
  }

  /// 歌曲播放完成处理
  void _onSongCompleted() {
    _consecutiveFailures = 0;
    debugPrint('[Player] Song completed, playMode: ${state.playMode}');

    if (state.playlist.isEmpty) {
      debugPrint('[Player] Playlist empty, stopping');
      _audioHandler.stop();
      return;
    }

    switch (state.playMode) {
      case PlayMode.single:
        // 单曲循环
        debugPrint('[Player] Single loop: restarting current song');
        _audioHandler.seek(Duration.zero);
        _audioHandler.play();
        break;
      case PlayMode.singlePlay:
        // 单曲播放：播完停止，不循环、不切换下一首
        debugPrint('[Player] SinglePlay mode: pausing after song completed');
        _audioHandler.pause();
        break;
      case PlayMode.order:
        if (state.currentIndex >= state.playlist.length - 1) {
          debugPrint('[Player] Order mode: reached end of playlist, stopping');
          state = state.copyWith(isPlaying: false);
          _audioHandler.stop();
          return;
        }
        // 非末尾，继续播放下一首
        debugPrint('[Player] Playing next song');
        unawaited(
          playNext().catchError((e, st) {
            debugPrint('[Player] playNext failed after song completed: $e');
            _audioHandler.stop();
          }),
        );
        break;
      case PlayMode.loop:
      case PlayMode.random:
        // 播放下一首
        debugPrint('[Player] Playing next song');
        unawaited(
          playNext().catchError((e, st) {
            debugPrint('[Player] playNext failed after song completed: $e');
            _audioHandler.stop();
          }),
        );
        break;
    }
  }

  /// 播放单曲（添加到播放列表并播放）
  Future<void> playSong(Song song) async {
    debugPrint(
      '[Player] playSong: ${song.title} (id: ${song.id}, type: ${song.type})',
    );
    _consecutiveFailures = 0;
    // 检查是否已在播放列表中
    final existingIndex = state.playlist.indexWhere(
      (s) => s.id == song.id && s.type == song.type,
    );

    if (existingIndex >= 0) {
      // 已存在，直接跳转播放
      debugPrint('[Player] Song already in playlist at index $existingIndex');
      await _playAtIndex(existingIndex);
    } else {
      // 添加到播放列表末尾并播放
      final newPlaylist = [...state.playlist, song];
      final newIndex = newPlaylist.length - 1;
      debugPrint('[Player] Adding song to playlist at index $newIndex');
      state = state.copyWith(
        playlist: newPlaylist,
        currentIndex: newIndex,
        currentSong: song,
      );
      await _playCurrent();
    }
  }

  /// 播放歌单
  Future<void> playPlaylist(List<Song> songs, {int startIndex = 0}) async {
    debugPrint(
      '[Player] playPlaylist: ${songs.length} songs, startIndex: $startIndex',
    );
    _consecutiveFailures = 0;
    if (songs.isEmpty) {
      debugPrint('[Player] playPlaylist: empty songs list, returning');
      return;
    }

    // 取消之前的预加载
    _prefetchCancelToken?.cancel('operation changed');

    // 递增代次，使正在进行的后台加载自动取消
    _loadGeneration++;

    final safeIndex = startIndex.clamp(0, songs.length - 1);
    debugPrint(
      '[Player] playPlaylist: starting with song: ${songs[safeIndex].title}',
    );
    _playedIndices.clear();
    _preSelectedNextIndex = null;

    state = state.copyWith(
      playlist: List.from(songs),
      currentIndex: safeIndex,
      currentSong: songs[safeIndex],
    );

    await _playCurrent();
  }

  /// 添加到当前播放列表
  void addToPlaylist(List<Song> songs) {
    if (songs.isEmpty) return;

    final newPlaylist = [...state.playlist];
    for (final song in songs) {
      final exists = newPlaylist.any(
        (s) => s.id == song.id && s.type == song.type,
      );
      if (!exists) {
        newPlaylist.add(song);
      }
    }

    state = state.copyWith(playlist: newPlaylist);
  }

  /// 将歌曲插入到播放列表的指定位置
  /// 用于撤销删除等场景，不会触发播放
  void insertToPlaylist(int index, Song song) {
    final newPlaylist = List<Song>.from(state.playlist);
    final safeIndex = index.clamp(0, newPlaylist.length);
    newPlaylist.insert(safeIndex, song);

    // 调整当前播放索引：插入位置在当前歌曲之前或等于当前位置时，索引后移
    int newCurrentIndex = state.currentIndex;
    if (state.currentIndex >= 0 && safeIndex <= state.currentIndex) {
      newCurrentIndex++;
    }

    state = state.copyWith(
      playlist: newPlaylist,
      currentIndex: newCurrentIndex,
    );
  }

  /// 暂停/播放切换
  Future<void> togglePlay() async {
    if (!state.hasSong) {
      debugPrint('[Player] togglePlay: no song to play');
      return;
    }

    if (state.isPlaying) {
      debugPrint('[Player] togglePlay: pausing');
      await _audioHandler.pause();
    } else {
      // 如果播放器处于 idle 状态（无音频源，如后台播放失败后），
      // 需要重新加载当前歌曲而不是简单调用 play()
      if (_audioHandler.processingState == ja.ProcessingState.idle) {
        debugPrint('[Player] togglePlay: player idle, re-loading current song');
        _consecutiveFailures = 0;
        await _playCurrent();
      } else {
        debugPrint('[Player] togglePlay: resuming');
        await _audioHandler.play();
      }
    }
  }

  /// 播放下一首
  Future<void> playNext() async {
    debugPrint(
      '[Player] playNext: currentIndex: ${state.currentIndex}, playlistLength: ${state.playlist.length}',
    );
    if (state.playlist.isEmpty) {
      debugPrint('[Player] playNext: playlist is empty');
      return;
    }

    int nextIndex;
    if (state.playMode == PlayMode.random) {
      nextIndex = _preSelectedNextIndex ?? _getRandomIndex();
      debugPrint('[Player] playNext: random mode, nextIndex: $nextIndex');
    } else {
      nextIndex = state.currentIndex + 1;
      if (nextIndex >= state.playlist.length) {
        if (state.playMode == PlayMode.loop) {
          nextIndex = 0;
          debugPrint('[Player] playNext: loop mode, wrapping to index 0');
        } else {
          debugPrint('[Player] playNext: order mode, reached end of playlist');
          // 顺序模式，播放完毕
          return;
        }
      }
    }

    await _playAtIndex(nextIndex);
  }

  /// 播放上一首
  Future<void> playPrev() async {
    _consecutiveFailures = 0;
    debugPrint(
      '[Player] playPrev: currentIndex: ${state.currentIndex}, currentTime: ${state.currentTime.inSeconds}s',
    );
    if (state.playlist.isEmpty) {
      debugPrint('[Player] playPrev: playlist is empty');
      return;
    }

    // 如果当前播放超过 3 秒，重新开始当前歌曲
    if (state.currentTime.inSeconds > 3) {
      debugPrint('[Player] playPrev: seeking to start of current song');
      await _audioHandler.seek(Duration.zero);
      return;
    }

    int prevIndex;
    if (state.playMode == PlayMode.random) {
      prevIndex = _getRandomIndex();
      debugPrint('[Player] playPrev: random mode, prevIndex: $prevIndex');
    } else {
      prevIndex = state.currentIndex - 1;
      if (prevIndex < 0) {
        if (state.playMode == PlayMode.loop) {
          prevIndex = state.playlist.length - 1;
          debugPrint('[Player] playPrev: loop mode, wrapping to last song');
        } else {
          debugPrint('[Player] playPrev: order mode, already at first song');
          // 顺序模式，已是第一首
          await _audioHandler.seek(Duration.zero);
          return;
        }
      }
    }

    await _playAtIndex(prevIndex);
  }

  /// 跳转进度
  Future<void> seek(Duration position) async {
    await _audioHandler.seek(position);
  }

  /// 设置音量 (0-100)
  Future<void> setVolume(double volume) async {
    final clampedVolume = volume.clamp(0.0, 100.0);
    state = state.copyWith(volume: clampedVolume, clearPreviousVolume: true);

    if (!kIsWeb) {
      // 非 Web 平台：控制系统音量
      try {
        VolumeController().setVolume(clampedVolume / 100);
        debugPrint('[Player] Set system volume: ${clampedVolume / 100}');
      } catch (e) {
        debugPrint('[Player] Failed to set system volume: $e');
      }
    } else {
      // Web 平台降级：使用 just_audio 播放器音量
      await _audioHandler.setVolume(clampedVolume / 100);
      debugPrint(
        '[Player] Set player volume (web fallback): ${clampedVolume / 100}',
      );
    }
  }

  /// 切换静音
  Future<void> toggleMute() async {
    if (state.isMuted) {
      // 恢复音量
      final restoreVolume = state.previousVolume ?? 50;
      await setVolume(restoreVolume);
    } else {
      // 静音
      state = state.copyWith(previousVolume: state.volume);
      await setVolume(0);
    }
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    _playedIndices.clear();
    _preSelectedNextIndex = null;
    state = state.copyWith(playMode: mode);

    // 保存到本地存储
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setPlayMode(mode.toStorageString());
      debugPrint('[Player] Saved playMode: ${mode.toStorageString()}');
    } catch (e) {
      debugPrint('[Player] Failed to save playMode: $e');
    }

    // 如果当前正在播放，重新预选下一首并预加载
    if (state.playlist.isNotEmpty &&
        state.currentIndex >= 0 &&
        state.isPlaying) {
      _prefetchCancelToken?.cancel('play mode changed');
      _preSelectNextIndex();
      // 副作用：刷新 SecureStorageService.cachedAccessToken,供 UrlHelper 使用
      await _secureStorage.getAccessToken();
      _prefetchNextSong();
    }
  }

  /// 从播放列表删除
  void removeFromPlaylist(int index) {
    if (index < 0 || index >= state.playlist.length) return;

    final newPlaylist = List<Song>.from(state.playlist);
    newPlaylist.removeAt(index);

    int newIndex = state.currentIndex;
    Song? newSong = state.currentSong;

    if (index == state.currentIndex) {
      // 删除的是当前播放的歌曲
      if (newPlaylist.isEmpty) {
        newIndex = -1;
        newSong = null;
        _audioHandler.stop();
      } else if (index >= newPlaylist.length) {
        newIndex = newPlaylist.length - 1;
        newSong = newPlaylist[newIndex];
      } else {
        newSong = newPlaylist[newIndex];
      }
    } else if (index < state.currentIndex) {
      // 删除的在当前之前
      newIndex--;
    }

    state = state.copyWith(
      playlist: newPlaylist,
      currentIndex: newIndex,
      currentSong: newSong,
      clearCurrentSong: newSong == null,
    );
  }

  /// 拖拽排序播放列表
  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    final newPlaylist = List<Song>.from(state.playlist);
    final song = newPlaylist.removeAt(oldIndex);

    // 如果新位置在旧位置之后，需要调整
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    newPlaylist.insert(insertIndex, song);

    // 调整当前索引
    int newCurrentIndex = state.currentIndex;
    if (oldIndex == state.currentIndex) {
      newCurrentIndex = insertIndex;
    } else {
      if (oldIndex < state.currentIndex && insertIndex >= state.currentIndex) {
        newCurrentIndex--;
      } else if (oldIndex > state.currentIndex &&
          insertIndex <= state.currentIndex) {
        newCurrentIndex++;
      }
    }

    state = state.copyWith(
      playlist: newPlaylist,
      currentIndex: newCurrentIndex,
    );
  }

  /// 清空播放列表
  void clearPlaylist() {
    // 取消之前的预加载
    _prefetchCancelToken?.cancel('operation changed');
    // 递增代次，使正在进行的后台加载自动取消
    _loadGeneration++;
    _consecutiveFailures = 0;
    _audioHandler.stop();
    _playedIndices.clear();
    _preSelectedNextIndex = null;
    state = state.copyWith(
      playlist: [],
      currentIndex: -1,
      clearCurrentSong: true,
      isPlaying: false,
      currentTime: Duration.zero,
      duration: Duration.zero,
    );
  }

  /// 通过歌单 ID 播放全部歌曲
  /// 策略：先取第一页（100首）立即开始播放，后台异步加载剩余歌曲
  /// 使用 _loadGeneration 防止竞态：用户切换歌单或清空时自动取消旧的后台加载
  /// [playlistId] 歌单 ID
  /// 返回用于展示的总歌曲数（-1 表示失败）
  Future<int> playPlaylistById(int playlistId) async {
    final playlistApi = ref.read(playlistApiProvider);
    const firstPageLimit = 100;

    debugPrint('[Player] playPlaylistById: start, playlistId=$playlistId');
    _consecutiveFailures = 0;
    try {
      final firstPageResponse = await playlistApi.getPlaylistSongs(
        playlistId,
        limit: firstPageLimit,
        offset: 0,
      );
      final firstPageSongs = firstPageResponse.songs;
      final total = firstPageResponse.total;

      debugPrint(
        '[Player] playPlaylistById: firstPage=${firstPageSongs.length}, total=$total',
      );

      if (firstPageSongs.isEmpty) {
        debugPrint('[Player] playPlaylistById: playlist is empty');
        return 0;
      }

      // playPlaylist 内部会递增 _loadGeneration，取消之前的后台加载
      await playPlaylist(firstPageSongs);

      if (total > firstPageSongs.length) {
        // 记录当前代次，传给后台加载任务用于检测是否过期
        final generation = _loadGeneration;
        debugPrint(
          '[Player] playPlaylistById: starting background load, generation=$generation, offset=${firstPageSongs.length}',
        );
        _loadRemainingSongsById(
          playlistId,
          playlistApi,
          firstPageSongs.length,
          total,
          generation,
        );
      } else {
        debugPrint('[Player] playPlaylistById: all songs loaded in first page');
        ref.read(playlistNotifierProvider.notifier).touchPlaylist(playlistId);
      }

      return total;
    } catch (e, st) {
      debugPrint('[Player] playPlaylistById error: $e\n$st');
      return -1;
    }
  }

  /// 后台异步加载剩余歌曲并追加到播放列表，完成后调用 touchPlaylist
  /// [generation] 启动时的代次快照，每次 await 后检查是否过期
  Future<void> _loadRemainingSongsById(
    int playlistId,
    PlaylistApi playlistApi,
    int startOffset,
    int total,
    int generation,
  ) async {
    const batchLimit = 100;
    const maxRetries = 3; // 单批次最大重试次数
    int offset = startOffset;
    try {
      while (offset < total) {
        // 每次网络请求前检查代次，若已过期则中止
        if (_loadGeneration != generation) {
          debugPrint(
            '[Player] _loadRemainingSongsById: cancelled before fetch'
            ' (generation: expected=$generation, current=$_loadGeneration, offset=$offset)',
          );
          return;
        }

        // 带重试的批次加载，防止网络波动导致加载中断
        SongListResponse? response;
        for (int retry = 0; retry < maxRetries; retry++) {
          try {
            debugPrint(
              '[Player] _loadRemainingSongsById: fetching offset=$offset'
              ' (retry=$retry, generation=$generation)',
            );
            response = await playlistApi.getPlaylistSongs(
              playlistId,
              limit: batchLimit,
              offset: offset,
            );
            break; // 成功则跳出重试循环
          } catch (e) {
            debugPrint(
              '[Player] _loadRemainingSongsById: fetch failed at offset=$offset,'
              ' retry=$retry/$maxRetries: $e',
            );
            if (retry == maxRetries - 1) rethrow; // 最后一次重试失败则抛出
            // 指数退避重试：500ms / 1000ms
            await Future<void>.delayed(
              Duration(milliseconds: 500 * (retry + 1)),
            );
          }
        }

        // 网络请求返回后再次检查，防止期间用户切换了歌单
        if (_loadGeneration != generation) {
          debugPrint(
            '[Player] _loadRemainingSongsById: cancelled after fetch'
            ' (generation: expected=$generation, current=$_loadGeneration, offset=$offset)',
          );
          return;
        }

        final batch = response!.songs;
        debugPrint(
          '[Player] _loadRemainingSongsById: got ${batch.length} songs at offset=$offset,'
          ' playlist size=${state.playlist.length + batch.length}',
        );
        if (batch.isEmpty) {
          debugPrint(
            '[Player] _loadRemainingSongsById: empty batch at offset=$offset, stopping',
          );
          break;
        }
        addToPlaylist(batch);
        offset += batchLimit;
      }
      debugPrint(
        '[Player] _loadRemainingSongsById: done,'
        ' loaded=${state.playlist.length}, total=$total',
      );
    } catch (e, st) {
      debugPrint(
        '[Player] _loadRemainingSongsById: failed at offset=$offset/$total'
        ' (generation=$generation): $e\n$st',
      );
    }
    // 仅当代次未变化时才执行 touchPlaylist，避免对错误的歌单更新时间
    if (_loadGeneration == generation) {
      ref.read(playlistNotifierProvider.notifier).touchPlaylist(playlistId);
    } else {
      debugPrint(
        '[Player] _loadRemainingSongsById: skip touchPlaylist'
        ' (generation: expected=$generation, current=$_loadGeneration)',
      );
    }
  }

  /// 播放全部歌曲（按筛选条件）
  /// 策略：先取第一页（100首）立即开始播放，后台异步加载剩余歌曲
  /// 使用 _loadGeneration 防止竞态：用户切换筛选或清空时自动取消旧的后台加载
  /// [keyword] 搜索关键词（可选）
  /// [type] 歌曲类型筛选（可选）
  /// 返回总歌曲数（-1 表示失败）
  Future<int> playAllSongs({String? keyword, String? type}) async {
    final songsApi = ref.read(songsApiProvider);
    const firstPageLimit = 100;

    debugPrint('[Player] playAllSongs: start, keyword=$keyword, type=$type');
    _consecutiveFailures = 0;
    try {
      final firstPageResponse = await songsApi.getSongs(
        keyword: keyword,
        type: type,
        limit: firstPageLimit,
        offset: 0,
      );
      final firstPageSongs = firstPageResponse.songs;
      final total = firstPageResponse.total;

      debugPrint(
        '[Player] playAllSongs: firstPage=${firstPageSongs.length}, total=$total',
      );

      if (firstPageSongs.isEmpty) {
        debugPrint('[Player] playAllSongs: no songs found');
        return 0;
      }

      // playPlaylist 内部会递增 _loadGeneration，取消之前的后台加载
      await playPlaylist(firstPageSongs);

      if (total > firstPageSongs.length) {
        // 记录当前代次，传给后台加载任务用于检测是否过期
        final generation = _loadGeneration;
        debugPrint(
          '[Player] playAllSongs: starting background load, generation=$generation, offset=${firstPageSongs.length}',
        );
        _loadRemainingSongsByFilter(
          songsApi,
          keyword,
          type,
          firstPageSongs.length,
          total,
          generation,
        );
      } else {
        debugPrint('[Player] playAllSongs: all songs loaded in first page');
      }

      return total;
    } catch (e, st) {
      debugPrint('[Player] playAllSongs error: $e\n$st');
      return -1;
    }
  }

  /// 后台异步加载剩余歌曲（按筛选条件）并追加到播放列表
  /// [generation] 启动时的代次快照，每次 await 后检查是否过期
  Future<void> _loadRemainingSongsByFilter(
    SongsApi songsApi,
    String? keyword,
    String? type,
    int startOffset,
    int total,
    int generation,
  ) async {
    const batchLimit = 100;
    const maxRetries = 3;
    int offset = startOffset;
    try {
      while (offset < total) {
        // 每次网络请求前检查代次，若已过期则中止
        if (_loadGeneration != generation) {
          debugPrint(
            '[Player] _loadRemainingSongsByFilter: cancelled before fetch'
            ' (generation: expected=$generation, current=$_loadGeneration, offset=$offset)',
          );
          return;
        }

        // 带重试的批次加载，防止网络波动导致加载中断
        SongListResponse? response;
        for (int retry = 0; retry < maxRetries; retry++) {
          try {
            debugPrint(
              '[Player] _loadRemainingSongsByFilter: fetching offset=$offset'
              ' (retry=$retry, generation=$generation)',
            );
            response = await songsApi.getSongs(
              keyword: keyword,
              type: type,
              limit: batchLimit,
              offset: offset,
            );
            break; // 成功则跳出重试循环
          } catch (e) {
            debugPrint(
              '[Player] _loadRemainingSongsByFilter: fetch failed at offset=$offset,'
              ' retry=$retry/$maxRetries: $e',
            );
            if (retry == maxRetries - 1) rethrow; // 最后一次重试失败则抛出
            // 指数退避重试：500ms / 1000ms
            await Future<void>.delayed(
              Duration(milliseconds: 500 * (retry + 1)),
            );
          }
        }

        // 网络请求返回后再次检查，防止期间用户切换了筛选条件
        if (_loadGeneration != generation) {
          debugPrint(
            '[Player] _loadRemainingSongsByFilter: cancelled after fetch'
            ' (generation: expected=$generation, current=$_loadGeneration, offset=$offset)',
          );
          return;
        }

        final batch = response!.songs;
        debugPrint(
          '[Player] _loadRemainingSongsByFilter: got ${batch.length} songs at offset=$offset,'
          ' playlist size=${state.playlist.length + batch.length}',
        );
        if (batch.isEmpty) {
          debugPrint(
            '[Player] _loadRemainingSongsByFilter: empty batch at offset=$offset, stopping',
          );
          break;
        }
        addToPlaylist(batch);
        offset += batchLimit;
      }
      debugPrint(
        '[Player] _loadRemainingSongsByFilter: done,'
        ' loaded=${state.playlist.length}, total=$total',
      );
    } catch (e, st) {
      debugPrint(
        '[Player] _loadRemainingSongsByFilter: failed at offset=$offset/$total'
        ' (generation=$generation): $e\n$st',
      );
    }
  }

  /// 切换全屏播放器
  void toggleFullPlayer() {
    state = state.copyWith(showFullPlayer: !state.showFullPlayer);
  }

  /// 关闭全屏播放器
  void closeFullPlayer() {
    state = state.copyWith(showFullPlayer: false);
  }

  /// 切换播放列表抽屉
  void togglePlaylistDrawer() {
    state = state.copyWith(showPlaylistDrawer: !state.showPlaylistDrawer);
  }

  /// 关闭播放列表抽屉
  void closePlaylistDrawer() {
    state = state.copyWith(showPlaylistDrawer: false);
  }

  /// 清除错误消息
  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  /// 设置睡眠定时器
  void setSleepTimer(Duration duration) {
    cancelSleepTimer();

    _sleepTimer = Timer(duration, () {
      _audioHandler.pause();
      cancelSleepTimer();
    });

    // 启动倒计时更新
    state = state.copyWith(sleepTimerRemaining: duration);
    _sleepTimerCountdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.sleepTimerRemaining;
      if (remaining != null && remaining.inSeconds > 0) {
        state = state.copyWith(
          sleepTimerRemaining: Duration(seconds: remaining.inSeconds - 1),
        );
      } else {
        timer.cancel();
        state = state.copyWith(clearSleepTimer: true);
      }
    });
  }

  /// 取消睡眠定时器
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerCountdown?.cancel();
    _sleepTimerCountdown = null;
    state = state.copyWith(clearSleepTimer: true);
  }

  /// 播放指定索引
  Future<void> _playAtIndex(int index) async {
    if (index < 0 || index >= state.playlist.length) return;

    // 取消之前的预加载
    _prefetchCancelToken?.cancel('operation changed');

    _playedIndices.add(index);
    state = state.copyWith(
      currentIndex: index,
      currentSong: state.playlist[index],
      currentTime: Duration.zero,
    );

    await _playCurrent();
  }

  /// 播放当前歌曲（带自动重试）
  Future<void> _playCurrent() async {
    final song = state.currentSong;
    if (song == null) {
      debugPrint('[Player] _playCurrent: no current song');
      return;
    }

    debugPrint(
      '[Player] _playCurrent: ${song.title} (id: ${song.id}, type: ${song.type})',
    );
    debugPrint(
      '[Player] _playCurrent: filePath: ${song.filePath}, url: ${song.url}',
    );

    for (int retry = 0; retry <= _maxRetryPerSong; retry++) {
      try {
        if (retry > 0) {
          debugPrint(
            '[Player] Retry $retry/$_maxRetryPerSong for: ${song.title}',
          );
          state = state.copyWith(isRetrying: true);
          await Future<void>.delayed(
            const Duration(milliseconds: _retryDelayMs),
          );
        }

        state = state.copyWith(isBuffering: true, clearErrorMessage: true);
        // 副作用：刷新 SecureStorageService.cachedAccessToken,供 UrlHelper 使用
        await _secureStorage.getAccessToken();
        debugPrint('[Player] _playCurrent: calling audioHandler.playSong');
        await _audioHandler.playSong(song);
        // 固定 just_audio 播放器音量为最大（音量由系统控制）
        if (kIsWeb) {
          await _audioHandler.setVolume(state.volume / 100);
        } else {
          await _audioHandler.setVolume(1.0);
        }
        debugPrint('[Player] _playCurrent: playback started successfully');

        // 播放成功 - 重置连续失败计数
        _consecutiveFailures = 0;
        state = state.copyWith(isRetrying: false);

        // 预选下一首并预加载
        _preSelectNextIndex();
        _prefetchNextSong();
        return; // 成功退出
      } catch (e) {
        debugPrint(
          '[Player] _playCurrent: play failed (retry $retry/$_maxRetryPerSong): $e',
        );
      }
    }

    // 所有重试都失败
    debugPrint(
      '[Player] _playCurrent: all retries exhausted for: ${song.title}',
    );
    state = state.copyWith(isBuffering: false, isRetrying: false);
    _handlePlayFailure();
  }

  /// 处理播放失败（重试耗尽后）
  /// 第二层：自动切歌（仅 order/loop/random 模式）
  /// 第三层：连续失败过多则停止
  void _handlePlayFailure() {
    _consecutiveFailures++;
    final failedSong = state.currentSong?.title ?? '未知歌曲';

    debugPrint(
      '[Player] Song failed after retries: $failedSong, '
      'consecutiveFailures: $_consecutiveFailures/$_maxConsecutiveSkips',
    );

    // singlePlay / single 模式：不自动切歌，直接停止
    if (state.playMode == PlayMode.singlePlay ||
        state.playMode == PlayMode.single) {
      debugPrint('[Player] Single mode, not skipping to next');
      state = state.copyWith(
        isPlaying: false,
        isBuffering: false,
        errorMessage: '"$failedSong" 播放失败',
      );
      _audioHandler.stop();
      _consecutiveFailures = 0; // 单曲模式不累计连续失败
      return;
    }

    if (_consecutiveFailures >= _maxConsecutiveSkips) {
      // 第三层：连续 N2 首都失败，停止播放
      debugPrint('[Player] Too many consecutive failures, stopping');
      state = state.copyWith(
        isPlaying: false,
        isBuffering: false,
        errorMessage: '连续 $_consecutiveFailures 首歌曲播放失败，已停止播放，请检查网络连接',
      );
      _audioHandler.stop();
      return;
    }

    // 第二层：自动切到下一首（仅 order/loop/random 模式）
    state = state.copyWith(errorMessage: '"$failedSong" 播放失败，正在尝试下一首...');
    _skipToNextOnFailure();
  }

  /// 播放失败时自动切到下一首
  /// 仅在 order/loop/random 模式下调用
  Future<void> _skipToNextOnFailure() async {
    if (state.playlist.isEmpty || state.playlist.length <= 1) {
      // 只有一首歌或空列表，无法切歌
      state = state.copyWith(errorMessage: '播放失败，无其他可播放的歌曲', isPlaying: false);
      _audioHandler.stop();
      return;
    }

    int nextIndex;
    if (state.playMode == PlayMode.random) {
      nextIndex = _getRandomIndex();
    } else {
      nextIndex = state.currentIndex + 1;
      if (nextIndex >= state.playlist.length) {
        if (state.playMode == PlayMode.order) {
          // 顺序模式已到末尾，停止
          state = state.copyWith(
            errorMessage: '播放失败，已到播放列表末尾',
            isPlaying: false,
          );
          _audioHandler.stop();
          return;
        }
        nextIndex = 0; // loop 模式回绕
      }
    }

    debugPrint('[Player] Skipping to next on failure: index $nextIndex');
    await _playAtIndex(nextIndex);
  }

  /// 预加载下一首歌曲
  void _prefetchNextSong() async {
    final nextIndex = _preSelectedNextIndex;
    if (nextIndex == null) return;
    if (nextIndex < 0 || nextIndex >= state.playlist.length) return;

    final nextSong = state.playlist[nextIndex];

    // 只预加载有相对路径 URL 的网络歌曲（插件歌曲）
    if (nextSong.type == 'local') return;
    if (nextSong.url == null || nextSong.url!.isEmpty) return;
    if (!nextSong.url!.startsWith('/')) return; // 外部 URL 无需预加载

    // 取消之前的预加载
    _prefetchCancelToken?.cancel('new prefetch');
    _prefetchCancelToken = CancelToken();

    try {
      // 构造预加载 URL：UrlHelper 已拼好 baseUrl + access_token，再附加 prefetch=true
      final songUrl = UrlHelper.buildSongUrl(nextSong.url!);
      final separator = songUrl.contains('?') ? '&' : '?';
      final prefetchUrl = '$songUrl${separator}prefetch=true';

      debugPrint('[Player] Prefetching next song: ${nextSong.title}');

      // 使用简单的 Dio 实例发起 GET 请求
      // 后端会 302 → 缓存接口检测 prefetch=true → 启动后台下载 → 202
      final dio = Dio();
      await dio.get(
        prefetchUrl,
        cancelToken: _prefetchCancelToken,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          // 允许 2xx 和 3xx 状态码
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      debugPrint('[Player] Prefetch completed for: ${nextSong.title}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('[Player] Prefetch cancelled for: ${nextSong.title}');
      } else {
        debugPrint('[Player] Prefetch failed for: ${nextSong.title}: $e');
      }
    } catch (e) {
      debugPrint('[Player] Prefetch error: $e');
    }
  }

  /// 预选下一首歌曲索引（用于预加载和随机模式播放）
  void _preSelectNextIndex() {
    if (state.playlist.isEmpty || state.currentIndex < 0) {
      _preSelectedNextIndex = null;
      return;
    }

    switch (state.playMode) {
      case PlayMode.order:
        final next = state.currentIndex + 1;
        _preSelectedNextIndex = next < state.playlist.length ? next : null;
        break;
      case PlayMode.loop:
        _preSelectedNextIndex =
            (state.currentIndex + 1) % state.playlist.length;
        break;
      case PlayMode.random:
        _preSelectedNextIndex = _getRandomIndex();
        break;
      case PlayMode.single:
      case PlayMode.singlePlay:
        _preSelectedNextIndex = null; // 不需要预选
        break;
    }

    if (_preSelectedNextIndex != null) {
      debugPrint(
        '[Player] Pre-selected next index: $_preSelectedNextIndex'
        ' (${state.playlist[_preSelectedNextIndex!].title})',
      );
    }
  }

  /// 获取随机索引（避免重复）
  int _getRandomIndex() {
    if (state.playlist.length == 1) return 0;

    // 如果所有歌曲都播放过，重置
    if (_playedIndices.length >= state.playlist.length) {
      _playedIndices.clear();
      // 保留当前索引，避免立即重复
      if (state.currentIndex >= 0) {
        _playedIndices.add(state.currentIndex);
      }
    }

    // 获取未播放的索引
    final availableIndices =
        List<int>.generate(
          state.playlist.length,
          (i) => i,
        ).where((i) => !_playedIndices.contains(i)).toList();

    if (availableIndices.isEmpty) {
      return _random.nextInt(state.playlist.length);
    }

    return availableIndices[_random.nextInt(availableIndices.length)];
  }
}

/// 便捷 Provider：当前是否有歌曲
final hasCurrentSongProvider = Provider<bool>((ref) {
  final state = ref.watch(playerStateProvider);
  return state.hasSong;
});

/// 便捷 Provider：当前是否正在播放
final isPlayingProvider = Provider<bool>((ref) {
  final state = ref.watch(playerStateProvider);
  return state.isPlaying;
});

/// 便捷 Provider：当前歌曲
final currentSongProvider = Provider<Song?>((ref) {
  final state = ref.watch(playerStateProvider);
  return state.currentSong;
});

/// 便捷 Provider：播放进度
final playerProgressProvider = Provider<double>((ref) {
  final state = ref.watch(playerStateProvider);
  return state.progress;
});
