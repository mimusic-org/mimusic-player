import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_exceptions.dart';

/// 版本信息模型
class VersionInfo {
  final String version;
  final String? releaseNotes;
  final DateTime? releaseDate;

  VersionInfo({required this.version, this.releaseNotes, this.releaseDate});

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      version: json['version'] as String,
      releaseNotes: json['release_notes'] as String?,
      releaseDate:
          json['release_date'] != null
              ? DateTime.parse(json['release_date'] as String)
              : null,
    );
  }

  @override
  String toString() => 'VersionInfo(version: $version)';
}

/// 可用更新的版本信息
class UpdateVersionInfo {
  final String type; // 'stable' 或 'dev'
  final String version;
  final String? gitCommit;
  final String? buildTime;
  final String? releaseNotes;

  UpdateVersionInfo({
    required this.type,
    required this.version,
    this.gitCommit,
    this.buildTime,
    this.releaseNotes,
  });

  factory UpdateVersionInfo.fromJson(String type, Map<String, dynamic> json) {
    return UpdateVersionInfo(
      type: type,
      version: json['version'] as String? ?? '',
      gitCommit: json['git_commit'] as String?,
      buildTime: json['build_time'] as String?,
      releaseNotes: json['release_notes'] as String?,
    );
  }

  /// 显示标签
  String get label => type == 'stable' ? '稳定版' : '开发版';

  @override
  String toString() => 'UpdateVersionInfo(type: $type, version: $version)';
}

/// 更新检查结果模型
class UpgradeCheck {
  final bool hasUpdate;
  final bool isDocker;
  final String? currentVersion;

  /// 可用的更新版本列表（stable、dev）
  final List<UpdateVersionInfo> availableUpdates;

  /// GitHub Release 页面 URL（非 Docker 环境用于跳转下载）
  final String releaseUrl;

  UpgradeCheck({
    required this.hasUpdate,
    required this.isDocker,
    this.currentVersion,
    this.availableUpdates = const [],
    this.releaseUrl = 'https://github.com/songloft-org/songloft/releases/latest',
  });

  factory UpgradeCheck.fromJson(Map<String, dynamic> json) {
    final isDocker = json['is_docker'] as bool? ?? false;

    // 解析当前版本
    String? currentVersion = json['current_version'] as String?;
    if (currentVersion == null || currentVersion.isEmpty) {
      final current = json['current'] as Map<String, dynamic>?;
      currentVersion = current?['version'] as String?;
    }

    // 解析可用更新列表
    final availableUpdates = <UpdateVersionInfo>[];
    final updates = json['updates'] as Map<String, dynamic>?;
    if (updates != null) {
      for (final type in ['stable', 'dev']) {
        final versionData = updates[type] as Map<String, dynamic>?;
        if (versionData != null) {
          availableUpdates.add(UpdateVersionInfo.fromJson(type, versionData));
        }
      }
    }

    return UpgradeCheck(
      hasUpdate: json['has_update'] as bool? ?? false,
      isDocker: isDocker,
      currentVersion: currentVersion,
      availableUpdates: availableUpdates,
    );
  }

  @override
  String toString() =>
      'UpgradeCheck(hasUpdate: $hasUpdate, isDocker: $isDocker, current: $currentVersion, updates: ${availableUpdates.length})';
}

/// 升级进度模型
class UpgradeProgress {
  final String
  status; // 'idle', 'downloading', 'testing', 'replacing', 'restarting', 'completed', 'error'
  final int progress; // 0-100
  final String? message;

  UpgradeProgress({required this.status, required this.progress, this.message});

  factory UpgradeProgress.fromJson(Map<String, dynamic> json) {
    return UpgradeProgress(
      status: json['status'] as String? ?? 'idle',
      progress: json['progress'] as int? ?? 0,
      message: json['message'] as String?,
    );
  }

  /// 默认空闲状态
  static UpgradeProgress get idle =>
      UpgradeProgress(status: 'idle', progress: 0);

  /// 是否正在升级
  bool get isUpgrading =>
      status == 'downloading' || status == 'testing' || status == 'replacing';

  /// 是否完成（包括 restarting 状态，因为后端升级成功后会发送 restarting 然后进程退出）
  bool get isCompleted => status == 'completed' || status == 'restarting';

  /// 是否出错
  bool get isError => status == 'error';

  /// 是否空闲
  bool get isIdle => status == 'idle';

  /// 状态显示文本
  String get statusText {
    switch (status) {
      case 'downloading':
        return '正在下载...';
      case 'testing':
        return '正在验证...';
      case 'replacing':
        return '正在替换...';
      case 'resetting':
        return '正在回退...';
      case 'restarting':
        return '正在重启...';
      case 'completed':
        return '升级完成';
      case 'error':
        return '升级失败';
      default:
        return '空闲';
    }
  }

  @override
  String toString() => 'UpgradeProgress(status: $status, progress: $progress%)';
}

/// 升级 API 服务
class UpgradeApi {
  final Dio dio;

  UpgradeApi({required this.dio});

  /// 获取可用版本列表
  /// GET /api/v1/upgrade/versions
  Future<List<VersionInfo>> getVersions() async {
    try {
      final response = await dio.get('${AppConfig.apiPrefix}/upgrade/versions');
      final data = response.data as List<dynamic>;
      return data
          .map((e) => VersionInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 检查更新
  /// GET /api/v1/upgrade/check
  /// [githubProxy] 为 GitHub 代理前缀，为空则直连
  Future<UpgradeCheck> checkUpgrade({String? githubProxy}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (githubProxy != null && githubProxy.isNotEmpty) {
        queryParams['github_proxy'] = githubProxy;
      }
      final response = await dio.get(
        '${AppConfig.apiPrefix}/upgrade/check',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      return UpgradeCheck.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 开始升级
  /// POST /api/v1/upgrade/start
  /// [versionType] 版本类型：'stable' 或 'dev'
  /// [githubProxy] 为 GitHub 代理前缀，为空则直连
  Future<void> startUpgrade({
    required String versionType,
    String? githubProxy,
  }) async {
    try {
      final data = <String, dynamic>{'version_type': versionType};
      if (githubProxy != null && githubProxy.isNotEmpty) {
        data['github_proxy'] = githubProxy;
      }
      await dio.post('${AppConfig.apiPrefix}/upgrade/start', data: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 回退到底包版本
  /// POST /api/v1/upgrade/reset
  Future<void> resetToBaseImage() async {
    try {
      await dio.post('${AppConfig.apiPrefix}/upgrade/reset');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 获取升级进度
  /// GET /api/v1/upgrade/progress
  Future<UpgradeProgress> getProgress() async {
    try {
      final response = await dio.get('${AppConfig.apiPrefix}/upgrade/progress');
      return UpgradeProgress.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
