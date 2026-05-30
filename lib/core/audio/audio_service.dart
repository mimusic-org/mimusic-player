import 'dart:async';

// LockCachingAudioSource 是 just_audio 中标记为实验性的边播边缓存 API，
// 目前没有稳定替代方案，此处有意使用以提升播放体验。
// ignore_for_file: experimental_member_use

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../shared/models/song.dart';
import '../utils/url_helper.dart';

/// Songloft 音频处理器 - 集成 audio_service 实现通知栏控制
/// 严格遵循 audio_service 官方示例模式：使用 .pipe() 绑定 playbackState
class SongloftAudioHandler extends BaseAudioHandler with SeekHandler {
  final ja.AudioPlayer _player = ja.AudioPlayer();

  /// 通知栏回调（由 PlayerNotifier 设置）
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  VoidCallback? onSongCompleted;

  /// 初始化 Future，用于确保初始化完成
  late final Future<void> _initFuture;

  SongloftAudioHandler() {
    // ★ 关键：使用官方示例的 pipe 模式直接绑定 playbackState
    // 这比手动 listen + add 更可靠，直接管道连接，无中间状态丢失
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    debugPrint('[AudioService] ✓ playbackEventStream.pipe(playbackState) 已绑定');

    // 监听 playbackState 变化，用于排查通知栏问题
    playbackState.listen((state) {
      debugPrint(
        '[AudioService] 📢 playbackState 更新: playing=${state.playing}, '
        'processingState=${state.processingState}, '
        'position=${state.updatePosition}, '
        'controls=${state.controls.length}个',
      );
    });

    // 监听播放完成
    _player.processingStateStream.listen(
      (state) {
        debugPrint('[AudioService] processingState 变化: $state');
        if (state == ja.ProcessingState.completed) {
          try {
            onSongCompleted?.call();
          } catch (e) {
            debugPrint('[AudioService] onSongCompleted error: $e');
            // 不重新抛出，避免 stream 断裂
          }
        }
      },
      onError: (error) {
        debugPrint('[AudioService] processingStateStream error: $error');
      },
    );

    // 异步初始化 AudioSession（不影响核心功能）
    _initFuture = _initAudioSession();

    debugPrint('[AudioService] SongloftAudioHandler 初始化完成');
  }

  /// 确保初始化完成
  Future<void> ensureInitialized() async {
    await _initFuture;
  }

  /// 初始化 AudioSession（异步，失败安全）
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      debugPrint('[AudioService] AudioSession configured');
      var wasPlayingBeforeInterruption = false;
      session.interruptionEventStream.listen((event) {
        debugPrint(
          '[AudioService] Audio interruption: type=${event.type}, begin=${event.begin}',
        );
        if (event.begin) {
          // 中断开始：记录当前播放状态并暂停
          wasPlayingBeforeInterruption = _player.playing;
          if (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.unknown) {
            _player.pause();
          }
        } else {
          // 中断结束：如果之前正在播放，则恢复
          if (wasPlayingBeforeInterruption) {
            _player.play();
          }
        }
      });
    } catch (e) {
      debugPrint('[AudioService] AudioSession init failed: $e');
    }
  }

  // ★ 核心：将 just_audio PlaybackEvent 转换为 audio_service PlaybackState
  // 官方示例：每个 event 都会触发 playbackState 更新，Android 端据此构建 MediaStyle 通知
  PlaybackState _transformEvent(ja.PlaybackEvent event) {
    final state = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          const {
            ja.ProcessingState.idle: AudioProcessingState.idle,
            ja.ProcessingState.loading: AudioProcessingState.loading,
            ja.ProcessingState.buffering: AudioProcessingState.buffering,
            ja.ProcessingState.ready: AudioProcessingState.ready,
            ja.ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    );
    debugPrint(
      '[AudioService] 🔄 _transformEvent: playing=${state.playing}, '
      'processingState=${state.processingState}, '
      'position=${state.updatePosition.inSeconds}s, '
      'controls=${state.controls.length}个',
    );
    return state;
  }

  // ====================== audio_service 必需的覆写方法 ======================
  // 官方示例：audio_service Android 端通过调用这些覆写方法来响应通知栏按钮点击

  @override
  Future<void> play() {
    debugPrint('[AudioService] ▶️ play() 被调用');
    return _player.play();
  }

  @override
  Future<void> pause() {
    debugPrint('[AudioService] ⏸️ pause() 被调用');
    return _player.pause();
  }

  @override
  Future<void> stop() async {
    debugPrint('[AudioService] ⏹️ stop() 被调用');
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) {
    debugPrint('[AudioService] ⏩ seek() 被调用: ${position.inSeconds}s');
    return _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('[AudioService] ⏭️ skipToNext() 被调用');
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('[AudioService] ⏮️ skipToPrevious() 被调用');
    onSkipToPrevious?.call();
  }

  // ====================== 业务方法 ======================

  /// 播放歌曲
  /// 所有 type(local/remote/radio)统一使用 song.url —— 后端 marshal Song 时
  /// 自动把 url 填成 /api/v1/songs/{id}/play,按 type 分发到 ServeFile / Orchestrator /
  /// 直链下载 / 电台 302,客户端无需关心 type。
  /// URL 拼接（baseUrl + access_token）统一走 UrlHelper。
  Future<void> playSong(Song song) async {
    // 确保 stream listeners 已建立
    await _initFuture;

    debugPrint(
      '[Player] SongloftAudioHandler.playSong: ${song.title} (type: ${song.type})',
    );
    try {
      ja.AudioSource source;

      if (song.url == null || song.url!.isEmpty) {
        debugPrint('[Player] SongloftAudioHandler: no valid source for song');
        throw Exception('无法播放：歌曲没有有效的播放源');
      }

      // 原生平台无法携带 Authorization Header,UrlHelper 会自动拼接 baseUrl + access_token
      final songUrl = UrlHelper.buildSongUrl(song.url!);

      debugPrint('[Player] SongloftAudioHandler: song url: $songUrl');
      // Web 平台 / 电台直播流使用 AudioSource.uri（直播流无法缓存）,
      // 其他平台普通歌曲使用 LockCachingAudioSource 实现边播边缓存
      if (kIsWeb || song.isLive) {
        source = ja.AudioSource.uri(Uri.parse(songUrl));
      } else {
        source = ja.LockCachingAudioSource(Uri.parse(songUrl));
      }

      // ★ 修复自动切歌时通知栏不更新问题：
      // 先更新 mediaItem，再 setAudioSource，再 play()。
      // 原来的顺序是 setAudioSource → _updateNowPlaying → play()，
      // 但在自动切歌场景下，setAudioSource 会触发 processingState 从 completed → idle，
      // audio_service 在 idle+playing=false 时可能停止前台 Service，
      // 导致之后的 mediaItem.add() 无法刷新到通知栏。
      // 提前更新 mediaItem，确保通知栏在 Service 重建时能读取到正确的元数据。
      _updateNowPlaying(song);

      // Web 平台需要 stop() 释放 HTML5 Audio 元素；
      // 原生平台不调用 stop()，setAudioSource() 会自动替换当前源。
      // 在 iOS 后台场景下，stop() 会使音频会话变为空闲，
      // 导致系统限制后台网络访问，使下一首歌曲无法加载。
      if (kIsWeb) {
        await _player.stop();
      }

      debugPrint('[Player] SongloftAudioHandler: setting audio source');
      await _player.setAudioSource(source);

      debugPrint('[Player] SongloftAudioHandler: starting playback');
      // 注意：just_audio 的 play() Future 在播放停止时才完成，不能 await，否则会阻塞调用链
      // 使用 fire-and-forget 模式，播放状态通过 playbackEventStream.pipe() 自动同步
      unawaited(_player.play());
      debugPrint(
        '[Player] SongloftAudioHandler: playback triggered (non-blocking)',
      );
      // 不再需要手动调用 _broadcastState()，pipe() 会自动同步
    } catch (e) {
      debugPrint('[Player] SongloftAudioHandler.playSong error: $e');
      rethrow;
    }
  }

  /// 更新通知栏元数据
  void _updateNowPlaying(Song song) {
    // artUri 由 Android 系统直接拉取，必须是带 baseUrl + access_token 的完整 URL
    Uri? artUri;
    final coverUrl = song.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      artUri = Uri.parse(UrlHelper.buildCoverUrl(coverUrl));
    }

    final item = MediaItem(
      id: '${song.type}_${song.id}',
      title: song.title,
      artist: song.artist ?? '未知艺术家',
      album: song.album ?? '',
      artUri: artUri,
      duration: Duration(milliseconds: (song.duration * 1000).toInt()),
    );

    // 详细日志输出 MediaItem 的所有字段，便于确认数据正确性
    debugPrint('[AudioService] _updateNowPlaying MediaItem:');
    debugPrint('  id: ${item.id}');
    debugPrint('  title: ${item.title}');
    debugPrint('  artist: ${item.artist}');
    debugPrint('  album: ${item.album}');
    debugPrint('  artUri: ${item.artUri}');
    debugPrint('  duration: ${item.duration}');

    mediaItem.add(item);
    debugPrint('[AudioService] MediaItem added to stream');
  }

  /// 更新通知栏元数据的 duration（当获取到实际时长时调用）
  void updateDuration(Duration duration) {
    final current = mediaItem.value;
    if (current != null) {
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  // _broadcastState 方法已移除，改用官方示例的 pipe() 模式自动同步

  // ====================== 暴露 just_audio 的 streams（保持与现有代码兼容）======================

  /// 播放位置流
  Stream<Duration> get positionStream => _player.positionStream;

  /// 总时长流
  Stream<Duration?> get durationStream => _player.durationStream;

  /// 播放状态流
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;

  /// 是否正在播放流
  Stream<bool> get playingStream => _player.playingStream;

  /// 缓冲位置流
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// 获取处理状态流（用于检测歌曲结束）
  Stream<ja.ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  /// 当前是否正在播放
  bool get isPlaying => _player.playing;

  /// 当前播放位置
  Duration get position => _player.position;

  /// 当前总时长
  Duration? get duration => _player.duration;

  /// 当前音量
  double get volume => _player.volume;

  /// 当前处理状态
  ja.ProcessingState get processingState => _player.processingState;

  // ====================== 音量控制 ======================

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  // ====================== 资源释放 ======================

  /// 释放资源
  Future<void> dispose() => _player.dispose();
}
