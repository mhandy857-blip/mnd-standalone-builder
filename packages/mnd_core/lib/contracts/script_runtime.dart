/// Тип события, на которое подписан скрипт.
enum EventType { onNodeEnter, onPress, onContentAppear, function }

/// Таблица квеста (ключ-значение) видимая скриптам.
abstract class ScriptTable {
  Map<String, dynamic> get data;
}

/// Состояние выполнения скриптов: переменные и таблицы.
///
/// Контракт намеренно минимальный — конкретная реализация
/// (`InMemoryScriptRuntimeState`) лежит в `mnd_core/runtime/`.
abstract class ScriptRuntimeState {
  Map<String, dynamic> get allVariables;
  Map<String, ScriptTable> get allTables;

  void setVariable(String name, dynamic value);
  dynamic getVariable(String name);

  void setTable(String tableName, ScriptTable table);
  ScriptTable? getTable(String tableName);
}
