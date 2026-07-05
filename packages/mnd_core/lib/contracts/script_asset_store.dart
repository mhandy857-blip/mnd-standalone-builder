/// Минимальный порт доступа к ассетам квеста (узлы, скрипты, ресурсы).
///
/// Контракт намеренно узкий — этого достаточно ядру скриптов. Если вашему
/// приложению нужно больше (бинарные данные, обход директорий) — реализуйте
/// дополнительно [ExtendedAssetStore].
///
/// Возможные реализации:
/// * локальная файловая система (Flutter / dart:io)
/// * память (in-memory тесты)
/// * сеть, бандл Flutter, zip-архив и т.п.
abstract class ScriptAssetStore {
  /// Существует ли ресурс по указанному относительному пути.
  Future<bool> exists(String path);

  /// Прочитать JSON-документ по [path].
  Future<Map<String, dynamic>> readJson(String path);
}

/// Расширенный порт ассетов — для приложений, которым нужны бинарные
/// чтения, текстовые ресурсы и обход директорий.
abstract class ExtendedAssetStore implements ScriptAssetStore {
  Future<List<int>> readBytes(String path);
  Future<String> readString(String path);
  Future<List<String>> listDirectory(String path);
}
