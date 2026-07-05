import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  group('InMemoryScriptRuntimeState', () {
    test('stores and reads variables', () {
      final state = InMemoryScriptRuntimeState();
      state.setVariable('hp', 5);
      state.setVariable('name', 'Frodo');

      expect(state.getVariable('hp'), 5);
      expect(state.getVariable('name'), 'Frodo');
      expect(state.allVariables, {'hp': 5, 'name': 'Frodo'});
    });

    test('returns null for unknown variables', () {
      final state = InMemoryScriptRuntimeState();
      expect(state.getVariable('nope'), isNull);
    });

    test('stores and reads tables', () {
      final state = InMemoryScriptRuntimeState();
      final table = QuestTable(name: 'inv', columns: const ['item'], rows: [
        {'item': 'sword'},
      ]);
      state.setTable('inv', table);
      expect(state.getTable('inv'), same(table));
      expect(state.allTables.containsKey('inv'), isTrue);
    });

    test('fromJson decodes tables', () {
      final state = InMemoryScriptRuntimeState.fromJson(
        variables: {'gold': 100},
        tables: {
          'inv': {
            'name': 'inv',
            'columns': ['item'],
            'rows': [
              {'item': 'sword'},
            ],
          },
        },
      );
      expect(state.getVariable('gold'), 100);
      final table = state.getTable('inv');
      expect(table, isA<QuestTable>());
      expect((table as QuestTable?)?.name, 'inv');
    });

    test('clear wipes variables and tables', () {
      final state = InMemoryScriptRuntimeState(
        variables: {'a': 1},
        tables: {
          'inv': QuestTable(name: 'inv', columns: const [], rows: const []),
        },
      )..clear();
      expect(state.allVariables, isEmpty);
      expect(state.allTables, isEmpty);
    });
  });
}
