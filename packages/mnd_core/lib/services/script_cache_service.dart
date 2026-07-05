import 'dart:async';

import 'package:mnd_core/contracts/script_asset_store.dart';

/// Сервис кэширования скриптов: предотвращает повторные чтения с диска
/// и дедуплицирует параллельные запросы за одним и тем же ресурсом.
///
/// Получает данные через порт [ScriptAssetStore], поэтому может работать
/// с любым бэкендом (ФС, бандл, in-memory).
class ScriptCacheService {
  ScriptCacheService(this._store);

  final ScriptAssetStore _store;

  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, Completer<Map<String, dynamic>?>> _pending = {};

  /// Получить скрипт из кэша или загрузить и закэшировать.
  Future<Map<String, dynamic>?> getScript(String fullPath) async {
    final cached = _cache[fullPath];
    if (cached != null) return cached;

    final inflight = _pending[fullPath];
    if (inflight != null) return inflight.future;

    final completer = Completer<Map<String, dynamic>?>();
    _pending[fullPath] = completer;

    try {
      if (!await _store.exists(fullPath)) {
        completer.complete(null);
        return null;
      }
      final data = await _store.readJson(fullPath);
      _cache[fullPath] = data;
      completer.complete(data);
      return data;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _pending.remove(fullPath);
    }
  }

  /// Инвалидировать кэш конкретного квеста.
  void invalidateQuest(String questId) {
    _cache.removeWhere((key, _) => key.contains('quests/$questId/'));
  }

  /// Очистить весь кэш.
  void clear() {
    _cache.clear();
    _pending.clear();
  }

  /// Прездагрузка всех скриптов, на которые ссылается переданный нод-контент.
  Future<void> preloadNodeScripts(
    String questId,
    Map<String, dynamic> nodeContent,
  ) async {
    final items = nodeContent['items'] as List<dynamic>? ?? const [];
    final futures = <Future<void>>[];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;

      final triggers = item['scriptTriggers'] as Map<String, dynamic>?;
      if (triggers != null) {
        for (final scriptPath in triggers.values) {
          if (scriptPath is String && scriptPath.isNotEmpty) {
            final full = 'quests/$questId/$scriptPath';
            futures.add(getScript(full).then((_) {}).catchError((_) {}));
          }
        }
      }

      final resourcePath = item['resourcePath'] as String?;
      if (resourcePath != null && item['type'] == 'script') {
        final full = 'quests/$questId/$resourcePath';
        futures.add(getScript(full).then((_) {}).catchError((_) {}));
      }
    }

    await Future.wait(futures);
  }
}
