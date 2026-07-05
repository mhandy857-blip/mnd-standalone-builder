import 'dart:async';
import 'package:mnd_player/utils/file_storage.dart';

class ScriptCacheService {
  static final ScriptCacheService _instance = ScriptCacheService._internal();
  factory ScriptCacheService() => _instance;
  ScriptCacheService._internal();

  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  Future<Map<String, dynamic>?> getScript(String fullPath) async {
    if (_cache.containsKey(fullPath)) {
      return _cache[fullPath];
    }

    if (_pending.containsKey(fullPath)) {
      return await _pending[fullPath]!.future;
    }

    final completer = Completer<Map<String, dynamic>>();
    _pending[fullPath] = completer;

    try {
      if (!await FileStorage.exists(fullPath)) {
        _pending.remove(fullPath);
        completer.complete({});
        return null;
      }

      final scriptData = await FileStorage.readJsonFile(fullPath);
      _cache[fullPath] = scriptData;
      _pending.remove(fullPath);
      completer.complete(scriptData);
      return scriptData;
    } catch (e) {
      _pending.remove(fullPath);
      completer.completeError(e);
      rethrow;
    }
  }

  void invalidateQuest(String questId) {
    _cache.removeWhere((key, _) => key.contains('quests/$questId/'));
  }

  void clear() {
    _cache.clear();
    _pending.clear();
  }

  Future<void> preloadNodeScripts(
    String questId,
    Map<String, dynamic> nodeContent,
  ) async {
    final items = nodeContent['items'] as List<dynamic>? ?? [];
    final futures = <Future>[];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;

      final scriptTriggers = item['scriptTriggers'] as Map<String, dynamic>?;
      if (scriptTriggers != null) {
        for (final scriptPath in scriptTriggers.values) {
          if (scriptPath is String && scriptPath.isNotEmpty) {
            final fullPath = 'quests/$questId/$scriptPath';
            futures.add(getScript(fullPath).catchError((_) => null));
          }
        }
      }

      final resourcePath = item['resourcePath'] as String?;
      if (resourcePath != null && item['type'] == 'script') {
        final fullPath = 'quests/$questId/$resourcePath';
        futures.add(getScript(fullPath).catchError((_) => null));
      }
    }

    await Future.wait(futures);
  }
}
