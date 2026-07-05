import 'package:mnd_core/contracts/save_store.dart';
import 'package:mnd_core/models/save_slot.dart';

/// Высокоуровневые операции над сейв-слотами квеста. Не привязан к ФС —
/// работает через порт [SaveStore].
class SaveGameService {
  SaveGameService(this._store);

  final SaveStore _store;

  /// Id специального слота автосохранения.
  static const String autosaveId = '_autosave';

  /// Список всех слотов квеста. Автосохранение всегда первым, остальные
  /// отсортированы по дате убывания.
  Future<List<SaveSlot>> getSaveSlots(String questId) async {
    final slots = (await _store.list(questId)).toList();
    slots.sort((a, b) {
      if (a.id == autosaveId) return -1;
      if (b.id == autosaveId) return 1;
      return b.savedAt.compareTo(a.savedAt);
    });
    return slots;
  }

  /// Сохранить произвольный слот.
  Future<void> saveGame(SaveSlot slot) => _store.write(slot);

  /// Записать автосохранение для квеста.
  Future<void> performAutosave({
    required String questId,
    required String currentNodeId,
    required Map<String, dynamic> variables,
    required Map<String, dynamic> tables,
  }) async {
    final slot = SaveSlot(
      id: autosaveId,
      questId: questId,
      slotName: 'Автосохранение',
      savedAt: DateTime.now(),
      currentNodeId: currentNodeId,
      variables: variables,
      tables: tables,
    );
    await _store.write(slot);
  }

  Future<void> deleteSave(String questId, String saveId) =>
      _store.delete(questId, saveId);

  Future<void> deleteAllSaves(String questId) => _store.deleteAll(questId);
}

/// Адаптер [SaveStore] на JSON-файлы поверх произвольного [QuestStorage]
/// импорта. Помещён здесь, потому что не зависит от ФС напрямую — только
/// от порта `QuestStorage` (см. `mnd_core/contracts/quest_storage.dart`).
class JsonFileSaveStore implements SaveStore {
  JsonFileSaveStore(this._readJson, this._writeJson, this._existsFn,
      this._listFilesFn, this._deleteFn,);

  // Раздельные функции а не QuestStorage целиком — чтобы пакет не тянул
  // лишний контракт в случае минималистичных приложений.
  final Future<Map<String, dynamic>> Function(String path) _readJson;
  final Future<void> Function(String path, Map<String, dynamic> data)
      _writeJson;
  final Future<bool> Function(String path) _existsFn;
  final Future<List<String>> Function(String path, {String? extension})
      _listFilesFn;
  final Future<void> Function(String path) _deleteFn;

  String _slotPath(String questId, String slotId) =>
      'quests/$questId/saves/$slotId.json';

  String _saveFolder(String questId) => 'quests/$questId/saves';

  @override
  Future<List<SaveSlot>> list(String questId) async {
    final folder = _saveFolder(questId);
    if (!await _existsFn(folder)) return const [];
    final files = await _listFilesFn(folder, extension: '.json');
    final slots = <SaveSlot>[];
    for (final name in files) {
      try {
        final data = await _readJson('$folder/$name');
        slots.add(SaveSlot.fromJson(data));
      } catch (_) {
        // skip corrupted slots
      }
    }
    return slots;
  }

  @override
  Future<SaveSlot?> read(String questId, String slotId) async {
    final path = _slotPath(questId, slotId);
    if (!await _existsFn(path)) return null;
    try {
      final data = await _readJson(path);
      return SaveSlot.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SaveSlot slot) async {
    final path = _slotPath(slot.questId, slot.id);
    await _writeJson(path, slot.toJson());
  }

  @override
  Future<void> delete(String questId, String slotId) async {
    final path = _slotPath(questId, slotId);
    if (await _existsFn(path)) await _deleteFn(path);
  }

  @override
  Future<void> deleteAll(String questId) async {
    final folder = _saveFolder(questId);
    if (await _existsFn(folder)) await _deleteFn(folder);
  }
}
