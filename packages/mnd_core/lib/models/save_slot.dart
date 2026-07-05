import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

@immutable
class SaveSlot {
  final String id;
  final String questId;
  final String slotName;
  final DateTime savedAt;
  final String currentNodeId;
  final Map<String, dynamic> variables;
  final Map<String, dynamic> tables; // Храним таблицы как JSON

  const SaveSlot({
    required this.id,
    required this.questId,
    required this.slotName,
    required this.savedAt,
    required this.currentNodeId,
    required this.variables,
    this.tables = const {}, // Default empty
  });

  factory SaveSlot.createNew({
    required String questId,
    required String slotName,
    required String currentNodeId,
    required Map<String, dynamic> variables,
    required Map<String, dynamic> tables, // New requirement
  }) {
    return SaveSlot(
      id: const Uuid().v4(),
      questId: questId,
      slotName: slotName,
      savedAt: DateTime.now(),
      currentNodeId: currentNodeId,
      variables: variables,
      tables: tables,
    );
  }

  factory SaveSlot.fromJson(Map<String, dynamic> json) {
    return SaveSlot(
      id: json['id'] as String,
      questId: json['questId'] as String,
      slotName: json['slotName'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      currentNodeId: json['currentNodeId'] as String,
      variables: json['variables'] as Map<String, dynamic>,
      // Безопасное чтение таблиц
      tables: (json['tables'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'questId': questId,
    'slotName': slotName,
    'savedAt': savedAt.toIso8601String(),
    'currentNodeId': currentNodeId,
    'variables': variables,
    'tables': tables,
  };
}
