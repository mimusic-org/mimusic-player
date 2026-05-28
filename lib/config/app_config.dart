/// 部署模式，通过 --dart-define=DEPLOY_MODE=embedded 在构建时注入
/// - 'embedded' : Flutter Web 嵌入 Go 后端，同域访问，无需用户配置 API 地址
/// - 'standalone': 独立静态部署，后端地址与前端不同域，需用户手动配置
/// 默认值为 'standalone'，即未指定时保持完整功能
const String _kDeployMode =
    String.fromEnvironment('DEPLOY_MODE', defaultValue: 'standalone');

class AppConfig {
  static String baseUrl = 'http://localhost:58091';
  static const String apiPrefix = '/api/v1';
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static String get apiBaseUrl => '$baseUrl$apiPrefix';

  /// 是否为嵌入模式（Flutter Web 打包进 Go 二进制）
  /// 编译时常量，tree-shaking 会移除未使用的分支代码
  static const bool isEmbedded = _kDeployMode == 'embedded';

  /// 前端版本号，通过 --dart-define=FRONTEND_VERSION=x.y.z 在构建时注入
  /// 本地开发时默认为 'dev'
  static const String frontendVersion =
      String.fromEnvironment('FRONTEND_VERSION', defaultValue: 'dev');

  /// 前端 GitHub 仓库
  static const String frontendRepo = 'songloft-org/songloft-player';

  /// 前端最新发布地址
  static const String frontendReleasesUrl =
      'https://github.com/songloft-org/songloft-player/releases/latest';

  /// 格式化前端版本号用于显示
  /// 'dev' -> '开发版本', '1.0.14' -> 'v1.0.14'
  static String get frontendVersionDisplay =>
      frontendVersion == 'dev' ? '开发版本' : 'v$frontendVersion';
}
