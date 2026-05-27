import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/utils/color_extraction.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../../shared/widgets/favorite_button.dart';
import '../../domain/player_state.dart';
import '../providers/player_provider.dart';
import '../queue_page.dart';
import 'lyrics_view.dart';
import 'play_controls.dart';
import 'popup_controls.dart';
import 'progress_bar.dart';
import 'volume_control.dart';

/// Desktop/Tablet 全屏播放器（左右分栏布局）
class DesktopFullPlayer extends ConsumerStatefulWidget {
  const DesktopFullPlayer({super.key});

  /// 显示全屏播放器
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const DesktopFullPlayer(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 从下往上滑入动画
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  ConsumerState<DesktopFullPlayer> createState() => _DesktopFullPlayerState();
}

class _DesktopFullPlayerState extends ConsumerState<DesktopFullPlayer>
    with SingleTickerProviderStateMixin {
  /// 封面脉冲动画控制器
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);
    final isDesktop = context.isDesktop;

    // 播放列表被清空时，自动关闭全屏播放器
    ref.listen<PlayerState>(playerStateProvider, (previous, next) {
      if (previous?.hasSong == true && !next.hasSong) {
        debugPrint(
          '[Player] DesktopFullPlayer: playlist cleared, closing player',
        );
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
      // 控制封面脉冲动画
      if (next.isPlaying && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      } else if (!next.isPlaying && _pulseController.isAnimating) {
        _pulseController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
        );
      }
    });

    // 初始播放状态动画
    if (state.isPlaying && !_pulseController.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && state.isPlaying && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      });
    }

    if (!state.hasSong) {
      debugPrint('[Player] DesktopFullPlayer: no song, hiding');
      return const SizedBox.shrink();
    }

    final song = state.currentSong!;
    final coverUrl = song.coverUrl;

    final paletteAsync = ref.watch(coverColorsProvider(coverUrl));
    final palette = paletteAsync.value;

    final horizontalPadding = isDesktop ? 48.0 : 24.0;
    final coverSize = isDesktop ? 300.0 : 220.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 背景模糊封面
          if (coverUrl != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Image.network(
                  UrlHelper.buildCoverUrl(coverUrl),
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                ),
              ),
            ),
          // 背景遮罩 - 动态取色渐变
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (palette?.darkMutedColor ?? theme.colorScheme.surface)
                        .withValues(alpha: 0.9),
                    theme.colorScheme.surface.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          // 顶部渐变遮罩 — 保证顶部按钮在任何封面色下可见
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 100,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 主内容
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                children: [
                  // 顶部栏
                  _buildTopBar(context, notifier),
                  const SizedBox(height: 16),
                  // 左右分栏主体
                  Expanded(
                    child: Row(
                      children: [
                        // 左侧：封面 + 歌曲信息
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 封面带脉冲动画
                                ScaleTransition(
                                  scale: _pulseAnimation,
                                  child: _buildCover(
                                    context,
                                    coverUrl,
                                    coverSize,
                                    palette: palette,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // 歌曲标题
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                  ),
                                  child: Text(
                                    song.title,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // 艺术家名
                                Text(
                                  song.artist ?? '未知艺术家',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 右侧：歌词
                        Expanded(
                          flex: 5,
                          child: LyricsView(
                            lyricUrl: song.lyricUrl,
                            currentPosition: state.currentTime,
                            onSeek: notifier.seek,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 进度条
                  PlayerProgressBar(
                    position: state.currentTime,
                    duration: state.duration,
                    onSeek: notifier.seek,
                  ),
                  const SizedBox(height: 12),
                  // 主控制按钮
                  PlayControls(
                    isPlaying: state.isPlaying,
                    hasPrev: state.hasPrev,
                    hasNext: state.hasNext,
                    isBuffering: state.isBuffering,
                    onPlay: notifier.togglePlay,
                    onPause: notifier.togglePlay,
                    onPrev: notifier.playPrev,
                    onNext: notifier.playNext,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  // 底部工具栏
                  _buildBottomBar(context, state, notifier),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部栏：返回按钮 + "正在播放" + 右侧占位
  Widget _buildTopBar(BuildContext context, PlayerNotifier notifier) {
    const topBarColor = Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 返回按钮
        IconButton(
          onPressed: () {
            notifier.closeFullPlayer();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          iconSize: 32,
          color: topBarColor,
        ),
        // 中间标题
        Text(
          '正在播放',
          style: TextStyle(
            color: topBarColor.withValues(alpha: 0.9),
            fontSize: 14,
          ),
        ),
        // 占位，保持布局对称
        const SizedBox(width: 48),
      ],
    );
  }

  /// 封面构建
  Widget _buildCover(
    BuildContext context,
    String? coverUrl,
    double size, {
    CoverPalette? palette,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: (palette?.dominantColor ?? Colors.black).withValues(
              alpha: 0.2,
            ),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child:
          coverUrl != null
              ? Image.network(
                UrlHelper.buildCoverUrl(coverUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildPlaceholder(theme, size),
              )
              : _buildPlaceholder(theme, size),
    );
  }

  Widget _buildPlaceholder(ThemeData theme, double size) {
    return Icon(
      Icons.music_note_rounded,
      size: size * 0.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// 底部工具栏
  Widget _buildBottomBar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // 收藏
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: FavoriteButton(songId: state.currentSong!.id, size: 24),
          ),
        ),
        // 播放模式
        SizedBox(
          width: 48,
          height: 48,
          child: PopupPlayModeControl(
            playMode: state.playMode,
            onPlayModeChanged: notifier.setPlayMode,
          ),
        ),
        // 音量
        SizedBox(
          width: 48,
          height: 48,
          child: PopupVolumeControl(
            volume: state.volume,
            onVolumeChanged: notifier.setVolume,
          ),
        ),
        // 睡眠定时
        SizedBox(
          width: 48,
          height: 48,
          child: PopupSleepTimerControl(
            sleepTimerRemaining: state.sleepTimerRemaining,
            onSetTimer: notifier.setSleepTimer,
            onCancelTimer: notifier.cancelSleepTimer,
          ),
        ),
        // 播放队列
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: () {
              QueueBottomSheet.show(context);
            },
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: '播放队列',
          ),
        ),
      ],
    );
  }
}
