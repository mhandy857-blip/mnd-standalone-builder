import 'package:mnd_core/models/quest_descriptor.dart';
import 'package:mnd_core/models/quest_table.dart';
import 'package:mnd_core/models/saved_node.dart';

class QuestProject {
  final Quest quest;
  final List<SavedNode> nodes;
  final Map<String, QuestTable> tables;

  const QuestProject({
    required this.quest,
    this.nodes = const [],
    this.tables = const {},
  });

  QuestProject copyWith({
    Quest? quest,
    List<SavedNode>? nodes,
    Map<String, QuestTable>? tables,
  }) {
    return QuestProject(
      quest: quest ?? this.quest,
      nodes: nodes ?? this.nodes,
      tables: tables ?? this.tables,
    );
  }
}
