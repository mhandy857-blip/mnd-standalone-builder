import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_player/utils/file_storage.dart';

class Tag {
  final String id;
  final String name;
  final String questId;
  final String? backgroundAssetId;
  final String? backgroundAudioId;
  final String folderPath;

  Tag({
    required this.id,
    required this.name,
    required this.questId,
    this.backgroundAssetId,
    this.backgroundAudioId,
    this.folderPath = '/',
  });

  static String normalizeFolderPath(String? raw) {
    final value = (raw ?? '').trim().replaceAll('\\', '/');
    if (value.isEmpty || value == '/') return '/';
    var path = value.startsWith('/') ? value : '/$value';
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    questId: json['questId'] as String? ?? '',
    backgroundAssetId: json['backgroundAssetId'] as String?,
    backgroundAudioId: json['backgroundAudioId'] as String?,
    folderPath: normalizeFolderPath(json['folderPath'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (backgroundAssetId != null) 'backgroundAssetId': backgroundAssetId,
    if (backgroundAudioId != null) 'backgroundAudioId': backgroundAudioId,
    if (folderPath != '/') 'folderPath': folderPath,
  };
}

final questTagsProvider = FutureProvider.autoDispose.family<List<Tag>, String>((
  ref,
  questId,
) async {
  return FileStorage.synchronized('config_$questId', () async {
    try {
      final configPath = 'quests/$questId/config.json';
      if (!await FileStorage.exists(configPath)) {
        return [];
      }

      final config = await FileStorage.readJsonFile(configPath);
      final tagsJson = config['tags'] as List<dynamic>? ?? [];
      final tags = tagsJson.map((json) {
        final tag = Tag.fromJson(json as Map<String, dynamic>);
        return Tag(
          id: tag.id,
          name: tag.name,
          questId: questId,
          backgroundAssetId: tag.backgroundAssetId,
          backgroundAudioId: tag.backgroundAudioId,
          folderPath: tag.folderPath,
        );
      }).toList();

      tags.sort((a, b) => a.name.compareTo(b.name));
      return tags;
    } catch (e) {
      print('Ошибка загрузки тегов: $e');
      return [];
    }
  });
});
