import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/storage/secure_storage.dart';

/// 插件 WebView 页面（原生平台实现）
/// 在应用内加载插件 HTML 页面，通过 JS 注入传递 JWT token
class PluginWebViewPage extends StatefulWidget {
  final String pluginUrl;
  final String pluginName;

  const PluginWebViewPage({
    super.key,
    required this.pluginUrl,
    required this.pluginName,
  });

  @override
  State<PluginWebViewPage> createState() => _PluginWebViewPageState();
}

class _PluginWebViewPageState extends State<PluginWebViewPage> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  String? _errorMessage;

  /// 构建 token 注入脚本
  /// 将 access token 写入 localStorage['songloft-auth']，
  /// 格式与旧 Vue 前端一致，插件 JS 的 getAuthToken() 可直接读取
  String _buildTokenInjectionScript() {
    final token = SecureStorageService.cachedAccessToken ?? '';
    if (token.isEmpty) return '';
    // 转义 token 中可能的特殊字符
    final escapedToken = token
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"');
    return "localStorage.setItem('songloft-auth', JSON.stringify({accessToken: '$escapedToken'}));";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _webViewController;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pluginName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final controller = _webViewController;
              if (controller != null && await controller.canGoBack()) {
                await controller.goBack();
              } else if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            // 关闭 WebView 页面
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 在外部浏览器中打开
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: '在浏览器中打开',
              onPressed: () {
                // 附加 token 到 URL，auth-bridge 脚本会从 query parameter 读取
                final token = SecureStorageService.cachedAccessToken ?? '';
                final separator = widget.pluginUrl.contains('?') ? '&' : '?';
                final url =
                    token.isNotEmpty
                        ? '${widget.pluginUrl}${separator}access_token=$token'
                        : widget.pluginUrl;
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_errorMessage != null)
              _buildErrorView(colorScheme)
            else
              _buildWebView(),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    // 原生平台通过 initialUserScripts 在 document_start 阶段注入 token
    final tokenScript = _buildTokenInjectionScript();

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.pluginUrl)),
      initialUserScripts:
          tokenScript.isNotEmpty
              ? UnmodifiableListView([
                UserScript(
                  source: tokenScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ])
              : null,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
      onLoadStart: (controller, url) {
        if (mounted) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        }
      },
      onLoadStop: (controller, url) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
      onReceivedError: (controller, request, error) {
        // 仅处理主页面加载错误，忽略子资源错误
        if (request.isForMainFrame ?? false) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = error.description;
            });
          }
        }
      },
    );
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('页面加载失败', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? '未知错误',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isLoading = true;
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
