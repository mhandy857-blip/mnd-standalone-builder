import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/template_instance_resolver.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final templatesByIdProvider = FutureProvider.autoDispose
    .family<Map<String, TemplateItem>, String?>((ref, questId) async {
  final allTemplates = <TemplateItem>[];

  if (questId != null) {
    final questPath = 'quests/$questId/res/templates.json';
    if (await FileStorage.exists(questPath)) {
      try {
        final data = await FileStorage.readJsonFile(questPath);
        final items = data['templates'] as List<dynamic>? ?? [];
        for (final raw in items) {
          if (raw is Map<String, dynamic>) {
            try {
              allTemplates.add(TemplateItem.fromJson(raw));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
  }

  return {for (final t in allTemplates) t.id: t};
});

final templateInstanceResolverProvider = FutureProvider.autoDispose
    .family<TemplateInstanceResolver, String?>((ref, questId) async {
  final byId = await ref.watch(templatesByIdProvider(questId).future);
  return TemplateInstanceResolver(templatesById: byId);
});
