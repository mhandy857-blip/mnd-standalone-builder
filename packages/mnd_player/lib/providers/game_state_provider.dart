import 'package:mnd_core/mnd_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GameState {
  final Map<String, dynamic> variables;
  final Map<String, QuestTable> tables;

  GameState({this.variables = const {}, this.tables = const {}});

  GameState copyWith({
    Map<String, dynamic>? variables,
    Map<String, QuestTable>? tables,
  }) {
    return GameState(
      variables: variables ?? this.variables,
      tables: tables ?? this.tables,
    );
  }
}

class GameStateNotifier extends StateNotifier<GameState>
    implements ScriptRuntimeState {
  GameStateNotifier() : super(GameState());

  @override
  Map<String, dynamic> get allVariables => state.variables;
  @override
  Map<String, ScriptTable> get allTables =>
      Map<String, ScriptTable>.from(state.tables);

  @override
  void setVariable(String name, dynamic value) {
    final newVariables = Map<String, dynamic>.from(state.variables);
    newVariables[name] = value;
    state = state.copyWith(variables: newVariables);
  }

  @override
  dynamic getVariable(String name) {
    return state.variables[name];
  }

  @override
  void setTable(String tableName, ScriptTable table) {
    if (table is! QuestTable) {
      throw ArgumentError.value(
        table,
        'table',
        'GameStateNotifier supports only QuestTable implementations',
      );
    }
    final newTables = Map<String, QuestTable>.from(state.tables);
    newTables[tableName] = table;
    state = state.copyWith(tables: newTables);
  }

  @override
  ScriptTable? getTable(String tableName) {
    return state.tables[tableName] as ScriptTable?;
  }

  void restoreState({
    required Map<String, dynamic> variables,
    required Map<String, dynamic> tablesJson,
  }) {
    final Map<String, QuestTable> restoredTables = {};

    tablesJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        restoredTables[key] = QuestTable.fromJson(value);
      }
    });

    state = state.copyWith(
      variables: Map.from(variables),
      tables: restoredTables,
    );
  }

  void clear() {
    state = GameState();
  }
}

final gameStateProvider =
    StateNotifierProvider.autoDispose<GameStateNotifier, GameState>((ref) {
  return GameStateNotifier();
});
