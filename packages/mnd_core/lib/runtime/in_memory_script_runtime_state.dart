import 'package:mnd_core/contracts/script_runtime.dart';
import 'package:mnd_core/models/quest_table.dart';

class InMemoryScriptRuntimeState implements ScriptRuntimeState {
  final Map<String, dynamic> _variables;
  final Map<String, ScriptTable> _tables;

  InMemoryScriptRuntimeState({
    Map<String, dynamic>? variables,
    Map<String, ScriptTable>? tables,
  }) : _variables = Map<String, dynamic>.from(variables ?? const {}),
       _tables = Map<String, ScriptTable>.from(tables ?? const {});

  @override
  Map<String, dynamic> get allVariables => _variables;

  @override
  Map<String, ScriptTable> get allTables => _tables;

  @override
  dynamic getVariable(String name) => _variables[name];

  @override
  void setVariable(String name, dynamic value) {
    _variables[name] = value;
  }

  @override
  ScriptTable? getTable(String tableName) => _tables[tableName];

  @override
  void setTable(String tableName, ScriptTable table) {
    _tables[tableName] = table;
  }

  void clear() {
    _variables.clear();
    _tables.clear();
  }

  factory InMemoryScriptRuntimeState.fromJson({
    Map<String, dynamic>? variables,
    Map<String, dynamic>? tables,
  }) {
    final parsedTables = <String, ScriptTable>{};
    (tables ?? const <String, dynamic>{}).forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsedTables[key] = QuestTable.fromJson(value);
      }
    });

    return InMemoryScriptRuntimeState(
      variables: variables ?? const <String, dynamic>{},
      tables: parsedTables,
    );
  }
}
