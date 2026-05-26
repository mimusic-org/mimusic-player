import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/cache_api.dart';
import '../../data/config_api.dart';
import '../../data/directory_api.dart';
import '../../data/scan_api.dart';
import '../../data/frontend_version_api.dart';
import '../../data/upgrade_api.dart';

// ============================================================================
// API Providers
// ============================================================================

/// ConfigApi Provider
final configApiProvider = Provider<ConfigApi>((ref) {
  final dio = ref.watch(dioProvider);
  return ConfigApi(dio: dio);
});

/// ScanApi Provider
final scanApiProvider = Provider<ScanApi>((ref) {
  final dio = ref.watch(dioProvider);
  return ScanApi(dio: dio);
});

/// DirectoryApi Provider
final directoryApiProvider = Provider<DirectoryApi>((ref) {
  final dio = ref.watch(dioProvider);
  return DirectoryApi(dio: dio);
});

/// UpgradeApi Provider
final upgradeApiProvider = Provider<UpgradeApi>((ref) {
  final dio = ref.watch(dioProvider);
  return UpgradeApi(dio: dio);
});

/// FrontendVersionApi Provider（使用独立 Dio，不依赖后端认证）
final frontendVersionApiProvider = Provider<FrontendVersionApi>((ref) {
  return FrontendVersionApi();
});

/// CacheApi Provider
final cacheApiProvider = Provider<CacheApi>((ref) {
  final dio = ref.watch(dioProvider);
  return CacheApi(dio: dio);
});

/// 服务端缓存统计
final serverCacheStatsProvider = FutureProvider<CacheStats>((ref) async {
  final cacheApi = ref.watch(cacheApiProvider);
  return cacheApi.getCacheStats();
});

/// 服务端缓存配置
final serverCacheConfigProvider = FutureProvider<CacheConfig>((ref) async {
  final cacheApi = ref.watch(cacheApiProvider);
  return cacheApi.getCacheConfig();
});

/// 网络歌曲自动转本地开关
final autoConvertEnabledProvider = FutureProvider<bool>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get(
    '${AppConfig.apiPrefix}/settings/auto-convert',
  );
  final data = response.data as Map<String, dynamic>;
  return data['enabled'] as bool? ?? false;
});

// ============================================================================
// Data Providers
// ============================================================================

/// 获取所有配置
final configsProvider = FutureProvider<List<Config>>((ref) async {
  final configApi = ref.watch(configApiProvider);
  return configApi.getConfigs();
});

/// 检查服务端更新
final upgradeCheckProvider = FutureProvider<UpgradeCheck>((ref) async {
  final upgradeApi = ref.watch(upgradeApiProvider);
  return upgradeApi.checkUpgrade();
});

/// 获取服务端版本号
final serverVersionProvider = FutureProvider<String>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('${AppConfig.apiPrefix}/version');
  final data = response.data as Map<String, dynamic>;
  final version = data['version'] as String?;
  if (version != null && version.isNotEmpty) {
    return version;
  }
  return '未知';
});

/// 检查前端（客户端）更新
final frontendVersionCheckProvider =
    FutureProvider<FrontendVersionCheck>((ref) async {
  final api = ref.watch(frontendVersionApiProvider);
  return api.checkUpdate();
});

// ============================================================================
// Theme Mode Provider
// ============================================================================

/// 主题模式 Notifier
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadThemeMode();
    return ThemeMode.system;
  }

  /// 从 AppPreferences 加载主题模式
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      state = prefs.getThemeMode();
    } catch (e) {
      // 加载失败使用默认值
      state = ThemeMode.system;
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setThemeMode(mode);
    } catch (e) {
      // 保存失败忽略
    }
  }
}

/// 主题模式 Provider
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ============================================================================
// Scan Progress Provider
// ============================================================================

/// 扫描进度 Notifier
class ScanProgressNotifier extends Notifier<ScanProgress> {
  late ScanApi _scanApi;
  Timer? _pollTimer;

  @override
  ScanProgress build() {
    _scanApi = ref.watch(scanApiProvider);
    ref.onDispose(() {
      _stopPolling();
    });
    return ScanProgress.idle;
  }

  /// 开始扫描
  Future<void> startScan({bool reimport = false}) async {
    try {
      await _scanApi.startScan(reimport: reimport);
      // 开始轮询进度
      _startPolling();
    } catch (e) {
      state = ScanProgress(
        status: 'error',
        totalFiles: 0,
        scannedFiles: 0,
        importedFiles: 0,
        skippedFiles: 0,
        failedFiles: 0,
      );
      rethrow;
    }
  }

  /// 取消扫描
  Future<void> cancelScan() async {
    try {
      await _scanApi.cancelScan();
      _stopPolling();
      state = ScanProgress(
        status: 'cancelled',
        totalFiles: state.totalFiles,
        scannedFiles: state.scannedFiles,
        importedFiles: state.importedFiles,
        skippedFiles: state.skippedFiles,
        failedFiles: state.failedFiles,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 刷新进度
  Future<void> refreshProgress() async {
    try {
      state = await _scanApi.getProgress();

      // 如果扫描完成或出错，停止轮询
      if (state.isCompleted || state.isError || state.isCancelled) {
        _stopPolling();
      }
    } catch (e) {
      // 获取进度失败忽略
    }
  }

  /// 重置状态
  void reset() {
    _stopPolling();
    state = ScanProgress.idle;
  }

  /// 开始轮询
  void _startPolling() {
    _stopPolling();
    // 每 2 秒轮询一次
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      refreshProgress();
    });
    // 立即获取一次
    refreshProgress();
  }

  /// 停止轮询
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

/// 扫描进度 Provider
final scanProgressProvider =
    NotifierProvider<ScanProgressNotifier, ScanProgress>(
      ScanProgressNotifier.new,
    );

// ============================================================================
// Upgrade Progress Provider
// ============================================================================

// ============================================================================
// Auto-Create Playlists Include Subdirs Provider
// ============================================================================

/// 「扫描后自动创建歌单是否包含子目录」配置 Notifier。
/// 后端 key: scan_auto_create_include_subdirs，存 "true"/"false"。
class AutoCreateIncludeSubdirsNotifier extends AsyncNotifier<bool> {
  static const _configKey = 'scan_auto_create_include_subdirs';

  @override
  Future<bool> build() async {
    final configApi = ref.watch(configApiProvider);
    try {
      final config = await configApi.getConfig(_configKey);
      return config.value.toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 切换并持久化
  Future<void> setValue(bool value) async {
    state = AsyncValue.data(value);
    try {
      final configApi = ref.read(configApiProvider);
      await configApi.updateConfig(
        key: _configKey,
        value: value ? 'true' : 'false',
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// 「扫描后自动创建歌单是否包含子目录」Provider
final autoCreateIncludeSubdirsProvider =
    AsyncNotifierProvider<AutoCreateIncludeSubdirsNotifier, bool>(
      AutoCreateIncludeSubdirsNotifier.new,
    );

// ============================================================================
// Upgrade Progress Provider
// ============================================================================

/// 升级进度 Notifier
class UpgradeProgressNotifier extends Notifier<UpgradeProgress> {
  late UpgradeApi _upgradeApi;
  Timer? _pollTimer;

  @override
  UpgradeProgress build() {
    _upgradeApi = ref.watch(upgradeApiProvider);
    ref.onDispose(() {
      _stopPolling();
    });
    return UpgradeProgress.idle;
  }

  /// 开始升级
  /// [versionType] 版本类型：'stable' 或 'dev'
  /// [githubProxy] 为 GitHub 代理前缀，为空则直连
  Future<void> startUpgrade({
    required String versionType,
    String? githubProxy,
  }) async {
    try {
      await _upgradeApi.startUpgrade(
        versionType: versionType,
        githubProxy: githubProxy,
      );
      _startPolling();
    } catch (e) {
      state = UpgradeProgress(
        status: 'error',
        progress: 0,
        message: e.toString(),
      );
      rethrow;
    }
  }

  /// 回退到底包版本
  Future<void> resetToBaseImage() async {
    try {
      await _upgradeApi.resetToBaseImage();
      _startPolling();
    } catch (e) {
      state = UpgradeProgress(
        status: 'error',
        progress: 0,
        message: e.toString(),
      );
      rethrow;
    }
  }

  /// 刷新进度
  Future<void> refreshProgress() async {
    try {
      state = await _upgradeApi.getProgress();

      if (state.isCompleted || state.isError) {
        _stopPolling();
      }
    } catch (e) {
      // 获取进度失败忽略
    }
  }

  /// 重置状态
  void reset() {
    _stopPolling();
    state = UpgradeProgress.idle;
  }

  void _startPolling() {
    _stopPolling();
    // 每 1 秒轮询一次（升级过程较快，需要更频繁的轮询）
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      refreshProgress();
    });
    refreshProgress();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

/// 升级进度 Provider
final upgradeProgressProvider =
    NotifierProvider<UpgradeProgressNotifier, UpgradeProgress>(
      UpgradeProgressNotifier.new,
    );
