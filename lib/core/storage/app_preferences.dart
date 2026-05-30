import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用偏好设置存储
class AppPreferences {
  static const _themeModeKey = 'theme_mode';
  static const _apiBaseUrlKey = 'api_base_url';
  static const _lastUsedDeviceKey = 'last_used_device';
  static const _volumeKey = 'player_volume';
  static const _playModeKey = 'player_play_mode';
  static const _playlistViewModeKey = 'playlist_view_mode';
  static const _lastUsernameKey = 'last_username';
  static const _lastPasswordKey = 'last_password';
  static const _currentIndexKey = 'player_current_index';
  static const _positionMsKey = 'player_position_ms';

  final SharedPreferences _prefs;

  AppPreferences(this._prefs);

  /// 异步创建实例
  static Future<AppPreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(prefs);
  }

  /// 获取主题模式
  ThemeMode getThemeMode() {
    final value = _prefs.getString(_themeModeKey);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 设置主题模式
  Future<bool> setThemeMode(ThemeMode mode) {
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
      case ThemeMode.dark:
        value = 'dark';
      case ThemeMode.system:
        value = 'system';
    }
    return _prefs.setString(_themeModeKey, value);
  }

  /// 获取自定义 API 地址（独立部署模式）
  String? getApiBaseUrl() {
    return _prefs.getString(_apiBaseUrlKey);
  }

  /// 设置自定义 API 地址
  Future<bool> setApiBaseUrl(String url) {
    return _prefs.setString(_apiBaseUrlKey, url);
  }

  /// 清除自定义 API 地址
  Future<bool> clearApiBaseUrl() {
    return _prefs.remove(_apiBaseUrlKey);
  }

  /// 获取最后使用的设备 ID
  String? getLastUsedDevice() {
    return _prefs.getString(_lastUsedDeviceKey);
  }

  /// 设置最后使用的设备 ID
  Future<bool> setLastUsedDevice(String deviceId) {
    return _prefs.setString(_lastUsedDeviceKey, deviceId);
  }

  /// 清除最后使用的设备
  Future<bool> clearLastUsedDevice() {
    return _prefs.remove(_lastUsedDeviceKey);
  }

  /// 获取播放器音量 (0-100)
  /// 返回存储的音量值，默认为 50
  double getVolume() {
    return _prefs.getDouble(_volumeKey) ?? 50.0;
  }

  /// 设置播放器音量 (0-100)
  Future<bool> setVolume(double volume) {
    return _prefs.setDouble(_volumeKey, volume);
  }

  /// 获取播放模式
  /// 返回播放模式字符串，默认为 'order'
  String getPlayMode() {
    return _prefs.getString(_playModeKey) ?? 'order';
  }

  /// 设置播放模式
  Future<bool> setPlayMode(String mode) {
    return _prefs.setString(_playModeKey, mode);
  }

  /// 获取歌单视图模式 ('grid' 或 'list')
  String getPlaylistViewMode() {
    return _prefs.getString(_playlistViewModeKey) ?? 'grid';
  }

  /// 设置歌单视图模式
  Future<bool> setPlaylistViewMode(String mode) {
    return _prefs.setString(_playlistViewModeKey, mode);
  }

  /// 获取上次登录的用户名
  String? getLastUsername() {
    return _prefs.getString(_lastUsernameKey);
  }

  /// 设置上次登录的用户名
  Future<bool> setLastUsername(String username) {
    return _prefs.setString(_lastUsernameKey, username);
  }

  /// 获取上次登录的密码
  String? getLastPassword() {
    return _prefs.getString(_lastPasswordKey);
  }

  /// 设置上次登录的密码
  Future<bool> setLastPassword(String password) {
    return _prefs.setString(_lastPasswordKey, password);
  }

  /// 本地缓存大小上限 key
  static const _localCacheMaxSizeKey = 'local_cache_max_size';

  /// 获取本地缓存大小上限（字节），默认 1 GB，0 表示不限制
  int getLocalCacheMaxSize() {
    return _prefs.getInt(_localCacheMaxSizeKey) ?? (1024 * 1024 * 1024);
  }

  /// 设置本地缓存大小上限（字节），0 表示不限制
  Future<bool> setLocalCacheMaxSize(int maxSize) {
    return _prefs.setInt(_localCacheMaxSizeKey, maxSize);
  }

  int getCurrentIndex() {
    return _prefs.getInt(_currentIndexKey) ?? -1;
  }

  Future<bool> setCurrentIndex(int index) {
    return _prefs.setInt(_currentIndexKey, index);
  }

  int getPositionMs() {
    return _prefs.getInt(_positionMsKey) ?? 0;
  }

  Future<bool> setPositionMs(int ms) {
    return _prefs.setInt(_positionMsKey, ms);
  }

  Future<void> clearPlaybackState() async {
    await _prefs.remove(_currentIndexKey);
    await _prefs.remove(_positionMsKey);
  }

  /// 清除所有偏好设置
  Future<bool> clear() {
    return _prefs.clear();
  }
}
