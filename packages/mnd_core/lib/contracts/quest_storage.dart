/// Расширенный порт для работы с хранилищем квестов:
/// чтение/запись JSON и бинарей, листинг, удаление.
///
/// Это надмножество [ScriptAssetStore] из контрактов скриптов. Сервисы
/// верхнего уровня (template_repository, save_game, cleaner) работают через
/// этот порт, поэтому могут жить в любой среде — лишь бы приложение дало
/// реализацию.
abstract class QuestStorage {
  Future<bool> exists(String path);

  Future<Map<String, dynamic>> readJson(String path);
  Future<void> writeJson(String path, Map<String, dynamic> data);

  Future<List<int>> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);

  Future<List<String>> listFiles(String path, {String? extension});
  Future<List<String>> listFolders(String path);

  Future<void> delete(String path);
  Future<void> clearDirectory(String path);

  /// Сгенерировать уникальный id (uuid v4 в дефолтной имплементации).
  String generateUniqueId();
}
