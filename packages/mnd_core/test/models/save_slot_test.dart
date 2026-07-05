import 'package:flutter_test/flutter_test.dart';
import 'package:mnd_core/mnd_core.dart';

void main() {
  group('SaveSlot', () {
    test('round-trip fromJson/toJson preserves fields', () {
      final slot = SaveSlot(
        id: 'slot-1',
        questId: 'quest-42',
        slotName: 'Глава 1',
        savedAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
        currentNodeId: 'node-7',
        variables: {'hp': 10, 'name': 'Hero'},
        tables: {'inventory': {'sword': 1}},
      );

      final decoded = SaveSlot.fromJson(slot.toJson());

      expect(decoded.id, slot.id);
      expect(decoded.questId, slot.questId);
      expect(decoded.slotName, slot.slotName);
      expect(decoded.savedAt, slot.savedAt);
      expect(decoded.currentNodeId, slot.currentNodeId);
      expect(decoded.variables, slot.variables);
      expect(decoded.tables, slot.tables);
    });

    test('createNew generates a unique id', () {
      final a = SaveSlot.createNew(
        questId: 'q',
        slotName: 's',
        currentNodeId: 'n',
        variables: const {},
        tables: const {},
      );
      final b = SaveSlot.createNew(
        questId: 'q',
        slotName: 's',
        currentNodeId: 'n',
        variables: const {},
        tables: const {},
      );
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });
  });
}
