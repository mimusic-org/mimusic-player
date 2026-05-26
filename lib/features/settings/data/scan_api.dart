import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_exceptions.dart';

/// 扫描进度模型
class ScanProgress {
  final String
  status; // 'idle', 'scanning', 'importing', 'creating_playlists', 'completed', 'failed', 'cancelling', 'cancelled'
  final String? currentFile;
  final int totalFiles;
  final int scannedFiles;
  final int importedFiles;
  final int skippedFiles;
  final int failedFiles;

  ScanProgress({
    required this.status,
    this.currentFile,
    required this.totalFiles,
    required this.scannedFiles,
    required this.importedFiles,
    required this.skippedFiles,
    required this.failedFiles,
  });

  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    return ScanProgress(
      status: json['status'] as String? ?? 'idle',
      currentFile: json['current_file'] as String?,
      totalFiles: json['total_files'] as int? ?? 0,
      scannedFiles: json['scanned_files'] as int? ?? 0,
      importedFiles: json['imported_files'] as int? ?? 0,
      skippedFiles: json['skipped_files'] as int? ?? 0,
      failedFiles: json['failed_files'] as int? ?? 0,
    );
  }

  /// 默认空闲状态
  static ScanProgress get idle => ScanProgress(
    status: 'idle',
    totalFiles: 0,
    scannedFiles: 0,
    importedFiles: 0,
    skippedFiles: 0,
    failedFiles: 0,
  );

  /// 计算进度百分比 0-100
  int get progress => totalFiles > 0 ? (scannedFiles * 100 ~/ totalFiles) : 0;

  /// 是否正在扫描（包括 scanning、importing、creating_playlists 阶段）
  bool get isScanning =>
      status == 'scanning' ||
      status == 'importing' ||
      status == 'creating_playlists' ||
      status == 'cancelling';

  /// 是否处于自动创建歌单阶段
  bool get isCreatingPlaylists => status == 'creating_playlists';

  /// 是否完成
  bool get isCompleted => status == 'completed';

  /// 是否出错
  bool get isError => status == 'failed';

  /// 是否已取消
  bool get isCancelled => status == 'cancelled';

  /// 是否空闲
  bool get isIdle => status == 'idle';

  @override
  String toString() =>
      'ScanProgress(status: $status, progress: $progress%, scanned: $scannedFiles/$totalFiles)';
}

/// 扫描 API 服务
class ScanApi {
  final Dio dio;

  ScanApi({required this.dio});

  /// 开始扫描
  /// POST /api/v1/scan
  Future<void> startScan({bool reimport = false}) async {
    try {
      await dio.post(
        '${AppConfig.apiPrefix}/scan',
        data: {'reimport': reimport},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 获取扫描进度
  /// GET /api/v1/scan/progress
  Future<ScanProgress> getProgress() async {
    try {
      final response = await dio.get('${AppConfig.apiPrefix}/scan/progress');
      return ScanProgress.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// 取消扫描
  /// POST /api/v1/scan/cancel
  Future<void> cancelScan() async {
    try {
      await dio.post('${AppConfig.apiPrefix}/scan/cancel');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
