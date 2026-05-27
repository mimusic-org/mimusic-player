import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dimensions.dart';
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

/// 移动端全屏播放器
class MobilePlayer extends ConsumerStatefulWidget {
  const MobilePlayer({super.key});

  /// 显示全屏播放器
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder:
            (context, animation, secondaryAnimation) => const MobilePlayer(),
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
  ConsumerState<MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends ConsumerState<MobilePlayer>
    with SingleTickerProviderStateMixin {
  /// PageView 控制器
  final PageController _pageController = PageController();

  /// 当前页面索引（0: 封面, 1: 歌词）
  int _currentPage = 0;

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
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // 播放列表被清空时，自动关闭全屏播放器并返回上一页
    // 同时控制封面脉冲动画
    ref.listen<PlayerState>(playerStateProvider, (previous, next) {
      if (previous?.hasSong == true && !next.hasSong) {
        debugPrint('[Player] MobilePlayer: playlist cleared, closing player');
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

    // 初始播放状态动画（listen 只响应变化，初始状态需要手动处理）
    if (state.isPlaying && !_pulseController.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && state.isPlaying && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      });
    }

    if (!state.hasSong) {
      debugPrint('[Player] MobilePlayer: no song, hiding');
      return const SizedBox.shrink();
    }

    final song = state.currentSong!;
    final coverUrl = song.coverUrl;

    final paletteAsync = ref.watch(coverColorsProvider(coverUrl));
    final palette = paletteAsync.value;

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
            child: Column(
              children: [
                // 顶部工具栏
                _buildTopBar(context, notifier, state),
                const SizedBox(height: 16),
                // 封面/歌词 PageView
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          children: [
                            // 页面1：封面（带脉冲动画）
                            Center(
                              child: ScaleTransition(
                                scale: _pulseAnimation,
                                child: _buildCover(
                                  context,
                                  coverUrl,
                                  size.width * 0.75,
                                  palette: palette,
                                ),
                              ),
                            ),
                            // 页面2：歌词
                            LyricsView(
                              lyricUrl: song.lyricUrl,
                              currentPosition: state.currentTime,
                              onSeek: notifier.seek,
                            ),
                          ],
                        ),
                      ),
                      // 页面指示器
                      const SizedBox(height: 12),
                      _buildPageIndicator(theme),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 歌曲信息
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      Text(
                        song.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
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
                const SizedBox(height: 24),
                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: PlayerProgressBar(
                    position: state.currentTime,
                    duration: state.duration,
                    onSeek: notifier.seek,
                  ),
                ),
                const SizedBox(height: 16),
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
                  size: 64,
                ),
                const SizedBox(height: 24),
                // 底部工具栏
                _buildBottomBar(context, state, notifier),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建页面指示器（小圆点）
  Widget _buildPageIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final isActive = index == _currentPage;
        return Container(
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    PlayerNotifier notifier,
    PlayerState state,
  ) {
    final song = state.currentSong;
    const topBarColor = Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
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
          // 歌曲信息（专辑名）
          if (song?.album != null && song!.album!.isNotEmpty)
            Expanded(
              child: Text(
                song.album!,
                style: TextStyle(
                  color: topBarColor.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          // 占位，保持布局对称
          const SizedBox(width: 48),
        ],
      ),
    );
  }

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

  Widget _buildBottomBar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
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
          // 播放列表 - 显示播放队列浮层（直接覆盖在播放器之上）
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              onPressed: () {
                // 直接在播放器之上显示队列浮层，无需先关闭播放器
                QueueBottomSheet.show(context);
              },
              icon: const Icon(Icons.queue_music_rounded),
              tooltip: '播放队列',
            ),
          ),
        ],
      ),
    );
  }
}
