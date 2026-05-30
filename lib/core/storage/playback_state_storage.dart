import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/song.dart';

class PlaybackStateStorage {
  static final PlaybackStateStorage _instance = PlaybackStateStorage._();
  factory PlaybackStateStorage() => _instance;
  PlaybackStateStorage._();

  static const _webFallbackKey = 'player_queue_json';
  static const _fileName = 'playback_queue.json';

  String? _filePath;

  Future<String> _getFilePath() async {
    if (_filePath != null) return _filePath!;
    final dir = await getApplicationDocumentsDirectory();
    _filePath = '${dir.path}/$_fileName';
    return _filePath!;
  }

  Future<void> saveQueue(List<Song> playlist) async {
    try {
      final jsonStr = jsonEncode(playlist.map((s) => s.toJson()).toList());

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_webFallbackKey, jsonStr);
      } else {
        final path = await _getFilePath();
        await File(path).writeAsString(jsonStr);
      }
    } catch (e) {
      debugPrint('[PlaybackStateStorage] saveQueue failed: $e');
    }
  }

  Future<List<Song>> loadQueue() async {
    try {
      String? jsonStr;

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(_webFallbackKey);
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          jsonStr = await file.readAsString();
        }
      }

      if (jsonStr == null || jsonStr.isEmpty) return [];

      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PlaybackStateStorage] loadQueue failed: $e');
      return [];
    }
  }

  Future<void> clear() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_webFallbackKey);
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[PlaybackStateStorage] clear failed: $e');
    }
  }
}
