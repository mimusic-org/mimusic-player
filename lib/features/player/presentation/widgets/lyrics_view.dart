import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/storage/lyric_cache_service.dart';
import '../../../../core/utils/url_helper.dart';
import '../../domain/lyric_parser.dart';

/// 歌词显示组件
///
/// 支持自动滚动到当前歌词行，高亮显示当前行。
/// 用户手动滚动时会暂停自动滚动，几秒后自动恢复。
/// 点击歌词行可跳转到对应时间点播放。
///
/// 通过 [lyricUrl] 从网络加载歌词（后端统一端点 /api/v1/songs/{id}/lyric）。
class LyricsView extends StatefulWidget {
  /// 歌词URL（后端统一端点，相对路径）
  final String? lyricUrl;

  /// 当前播放位置
  final Duration currentPosition;

  /// 点击歌词行时的回调，传入被点击行的时间点
  final ValueChanged<Duration>? onSeek;

  const LyricsView({
    super.key,
    this.lyricUrl,
    required this.currentPosition,
    this.onSeek,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 解析后的歌词列表
  List<LyricLine> _lyrics = [];

  /// 当前高亮的歌词行索引
  int _currentLineIndex = -1;

  /// 是否正在用户手动滚动
  bool _isUserScrolling = false;

  /// 恢复自动滚动的定时器
  Timer? _resumeTimer;

  /// 每行歌词的估算高度
  static const double _lineHeight = 48.0;

  /// 用户手动滚动后恢复自动滚动的延迟时间
  static const Duration _resumeDelay = Duration(seconds: 3);

  /// 网络加载状态
  bool _isLoadingFromUrl = false;

  /// 网络加载失败
  bool _loadFailed = false;

  /// 从网络加载到的歌词文本
  String? _fetchedLyricText;

  /// 上一次加载的 URL（用于避免重复请求）
  String? _lastFetchedUrl;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initLyrics();
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 歌词URL变化时重新处理
    if (widget.lyricUrl != oldWidget.lyricUrl) {
      _initLyrics();
    }

    // 播放位置变化时更新高亮行并滚动
    if (widget.currentPosition != oldWidget.currentPosition) {
      _updateCurrentLine();
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 初始化歌词：从 lyricUrl 加载
  void _initLyrics() {
    if (widget.lyricUrl != null && widget.lyricUrl!.isNotEmpty) {
      // 有 lyricUrl，从网络加载（后端统一端点）
      if (_lastFetchedUrl == widget.lyricUrl && _fetchedLyricText != null) {
        // 同一个 URL 且已成功加载过，直接使用缓存
        _parseLyrics(_fetchedLyricText);
      } else {
        _fetchLyricFromUrl(widget.lyricUrl!);
      }
    } else {
      // 无 lyricUrl，显示空状态
      _isLoadingFromUrl = false;
      _loadFailed = false;
      _fetchedLyricText = null;
      _lastFetchedUrl = null;
      _lyrics = [];
      _currentLineIndex = -1;
    }
  }

  /// 从网络加载歌词（集成本地缓存）
  Future<void> _fetchLyricFromUrl(String lyricUrl) async {
    // 1. 先查本地缓存
    final cached = await LyricCacheService().get(lyricUrl);
    if (cached != null) {
      _fetchedLyricText = cached;
      _lastFetchedUrl = lyricUrl;
      if (mounted) {
        setState(() {
          _isLoadingFromUrl = false;
          _loadFailed = false;
        });
      }
      _parseLyrics(cached);
      return;
    }

    setState(() {
      _isLoadingFromUrl = true;
      _loadFailed = false;
      _lyrics = [];
      _currentLineIndex = -1;
    });

    try {
      // UrlHelper 自动处理：相对路径拼 baseUrl + access_token，外链原样返回
      final fullUrl = UrlHelper.buildLyricUrl(lyricUrl);
      // 后端 /api/v1/songs/{id}/lyric 直接返回 LyricPayload:
      //   {"lyric":"...","tlyric":"...","rlyric":"...","lxlyric":"..."}
      final response = await Dio().get<Map<String, dynamic>>(fullUrl);

      if (!mounted) return;

      final body = response.data;
      String lyricText = '';
      if (body is Map<String, dynamic>) {
        final main = body['lyric'];
        if (main is String) {
          lyricText = main;
        }
      }

      _fetchedLyricText = lyricText;
      _lastFetchedUrl = lyricUrl;
      setState(() {
        _isLoadingFromUrl = false;
        _loadFailed = false;
      });
      _parseLyrics(lyricText);

      if (lyricText.isNotEmpty) {
        await LyricCacheService().put(lyricUrl, lyricText);
      }
    } catch (e) {
      debugPrint('[LyricsView] Failed to load lyric from URL: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingFromUrl = false;
        _loadFailed = true;
      });
    }
  }

  /// 解析歌词
  void _parseLyrics(String? lyricText) {
    if (lyricText == null || lyricText.isEmpty) {
      _lyrics = [];
      _currentLineIndex = -1;
      if (mounted) setState(() {});
      return;
    }

    _lyrics = LyricParser.parse(lyricText);
    _currentLineIndex = -1;
    _updateCurrentLine();
    if (mounted) setState(() {});
  }

  /// 更新当前歌词行
  void _updateCurrentLine() {
    final newIndex = LyricParser.findCurrentLine(
      _lyrics,
      widget.currentPosition,
    );
    if (newIndex != _currentLineIndex) {
      setState(() {
        _currentLineIndex = newIndex;
      });

      // 如果不是用户手动滚动，自动滚动到当前行
      if (!_isUserScrolling && newIndex >= 0) {
        _scrollToLine(newIndex);
      }
    }
  }

  /// 滚动到指定歌词行
  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;

    // 计算目标偏移量（将当前行滚动到视图中央）
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset =
        (index * _lineHeight) - (viewportHeight / 2) + (_lineHeight / 2);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// 监听滚动事件
  void _onScroll() {
    // 检测用户是否正在手动滚动
    if (_scrollController.position.isScrollingNotifier.value) {
      _onUserScrollStart();
    }
  }

  /// 用户开始手动滚动
  void _onUserScrollStart() {
    _isUserScrolling = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _onResumeAutoScroll);
  }

  /// 恢复自动滚动
  void _onResumeAutoScroll() {
    _isUserScrolling = false;
    // 立即滚动到当前行
    if (_currentLineIndex >= 0) {
      _scrollToLine(_currentLineIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 正在从网络加载歌词
    if (_isLoadingFromUrl) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '正在加载歌词...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 网络加载失败
    if (_loadFailed) {
      return Center(
        child: Text(
          '歌词加载失败',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    // 无歌词时显示占位
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          // 用户开始滚动
          if (notification.dragDetails != null) {
            _onUserScrollStart();
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 24),
        itemCount: _lyrics.length,
        itemBuilder: (context, index) {
          final lyric = _lyrics[index];
          final isCurrent = index == _currentLineIndex;

          return GestureDetector(
            onTap: () {
              // 点击歌词行跳转到对应时间点
              if (widget.onSeek != null) {
                widget.onSeek!(lyric.time);
                // 恢复自动滚动状态
                _isUserScrolling = false;
                _resumeTimer?.cancel();
              }
            },
            child: Container(
              height: _lineHeight,
              alignment: Alignment.center,
              child: Text(
                lyric.text.isEmpty ? '...' : lyric.text,
                style: TextStyle(
                  fontSize: isCurrent ? 18 : 15,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color:
                      isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}
