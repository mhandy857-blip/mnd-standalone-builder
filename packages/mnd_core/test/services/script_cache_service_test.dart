import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

class _FakeAssetStore implements ScriptAssetStore {
  _FakeAssetStore(this._files);

  final Map<String, Map<String, dynamic>> _files;
  int readCount = 0;
  int existsCount = 0;

  @override
  Future<bool> exists(String path) async {
    existsCount++;
    return _files.containsKey(path);
  }

  @override
  Future<Map<String, dynamic>> readJson(String path) async {
    readCount++;
    final data = _files[path];
    if (data == null) throw StateError('not found: $path');
    return data;
  }
}

void main() {
  group('ScriptCacheService', () {
    test('caches consecutive reads', () async {
      final store = _FakeAssetStore({
        'quests/q1/scripts/a.json': {'x': 1},
      });
      final cache = ScriptCacheService(store);
      final r1 = await cache.getScript('quests/q1/scripts/a.json');
      final r2 = await cache.getScript('quests/q1/scripts/a.json');
      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(store.readCount, 1, reason: 'second read must hit cache');
    });

    test('deduplicates parallel in-flight requests', () async {
      final store = _FakeAssetStore({
        'quests/q1/scripts/a.json': {'x': 1},
      });
      final cache = ScriptCacheService(store);
      final results = await Future.wait([
        cache.getScript('quests/q1/scripts/a.json'),
        cache.getScript('quests/q1/scripts/a.json'),
        cache.getScript('quests/q1/scripts/a.json'),
      ]);
      expect(results.where((e) => e != null).length, 3);
      expect(store.readCount, lessThanOrEqualTo(1));
    });

    test('returns null when asset is missing', () async {
      final cache = ScriptCacheService(_FakeAssetStore({}));
      final result = await cache.getScript('missing.json');
      expect(result, isNull);
    });

    test('invalidateQuest removes cached entries for the given quest only',
        () async {
      final store = _FakeAssetStore({
        'quests/q1/scripts/a.json': {'x': 1},
        'quests/q2/scripts/a.json': {'x': 2},
      });
      final cache = ScriptCacheService(store);
      await cache.getScript('quests/q1/scripts/a.json');
      await cache.getScript('quests/q2/scripts/a.json');
      cache.invalidateQuest('q1');
      await cache.getScript('quests/q1/scripts/a.json');
      await cache.getScript('quests/q2/scripts/a.json');
      expect(store.readCount, 3);
    });
  });
}
