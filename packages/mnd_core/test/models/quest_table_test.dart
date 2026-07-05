import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  group('QuestTable', () {
    test('round-trip fromJson/toJson', () {
      final table = QuestTable(
        name: 'inv',
        columns: const ['item', 'qty'],
        rows: [
          {'item': 'sword', 'qty': 1},
          {'item': 'gold', 'qty': 50},
        ],
        data: const {'meta': 'starter'},
      );
      final decoded = QuestTable.fromJson(table.toJson());
      expect(decoded.name, table.name);
      expect(decoded.columns, table.columns);
      expect(decoded.rows, table.rows);
      expect(decoded.data, table.data);
    });

    test('addEmptyRow adds empty fields for every column', () {
      final table = QuestTable(
        name: 't',
        columns: ['a', 'b'],
        rows: [],
      )..addEmptyRow();
      expect(table.rows.length, 1);
      expect(table.rows.first.keys, containsAll(['a', 'b']));
    });

    test('updateColumns drops removed columns and adds new ones with empty',
        () {
      final table = QuestTable(
        name: 't',
        columns: ['a', 'b'],
        rows: [
          {'a': 1, 'b': 2},
        ],
      )..updateColumns(['a', 'c']);
      expect(table.columns, ['a', 'c']);
      expect(table.rows.first.containsKey('b'), isFalse);
      expect(table.rows.first['c'], '');
    });
  });
}
