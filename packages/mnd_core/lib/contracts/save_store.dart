import 'package:mnd_core/models/save_slot.dart';

/// Порт хранилища сохранений (save slots) квеста.
///
/// Конкретные реализации могут писать в файловую систему, БД, удалённое
/// хранилище или память. Контракт намеренно простой и достаточный для
/// плеера квестов.
abstract class SaveStore {
  /// Вернуть все сейв-слоты конкретного квеста.
  Future<List<SaveSlot>> list(String questId);

  /// Прочитать конкретный слот, либо `null` если его нет.
  Future<SaveSlot?> read(String questId, String slotId);

  /// Сохранить слот (создаст или перезапишет существующий).
  Future<void> write(SaveSlot slot);

  /// Удалить слот.
  Future<void> delete(String questId, String slotId);

  /// Удалить все слоты квеста.
  Future<void> deleteAll(String questId);
}
