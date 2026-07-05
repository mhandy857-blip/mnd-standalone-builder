import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/utils/file_storage.dart';

final allQuestNodesProvider = FutureProvider.autoDispose
    .family<List<SavedNode>, String>((ref, questId) async {
      return FileStorage.synchronized('nodes_$questId', () async {
        try {
          final nodesPath = 'quests/$questId/nodes.json';
          if (!await FileStorage.exists(nodesPath)) {
            return [];
          }

          final nodesData = await FileStorage.readJsonFile(nodesPath);
          final nodesJson = nodesData['nodes'] as List<dynamic>? ?? [];

          final validNodes = <SavedNode>[];

          for (final jsonItem in nodesJson) {
            try {
              if (jsonItem is Map<String, dynamic>) {
                validNodes.add(SavedNode.fromJson(jsonItem));
              }
            } catch (e) {
              // ignore error
            }
          }

          return validNodes;
        } catch (e) {
          return [];
        }
      });
    });
