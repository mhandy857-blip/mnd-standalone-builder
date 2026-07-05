import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mnd_core/mnd_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/key_derivation_service.dart';

String? _extractTitleFromRawConfig(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      final title = decoded['title']?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
    } else if (decoded is Map) {
      final title = decoded['title']?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
    }
  } catch (_) {}
  return null;
}

Quest _buildCorruptedQuest({
  required String questId,
  String? rawConfig,
  Object? error,
}) {
  final recoveredTitle = rawConfig == null
      ? null
      : _extractTitleFromRawConfig(rawConfig);
  return Quest(
    id: questId,
    title: recoveredTitle ?? questId,
    description:
        'Конфигурация квеста повреждена.',
    isCorrupted: true,
    loadError: error?.toString(),
  );
}

final questsProvider = FutureProvider<List<Quest>>((ref) async {
  final questsDir = Directory(await FileStorage.getFilePath('quests'));
  if (!await questsDir.exists()) {
    await questsDir.create(recursive: true);
    return [];
  }

  final questFolders = await FileStorage.listFolders('quests');
  if (questFolders.isEmpty) return [];

  final appDir = await FileStorage.getAppDirectory();
  final quests = <Quest>[];

  for (final questId in questFolders) {
    try {
      final configPath = '${appDir.path}/quests/$questId/config.json';
      final configFile = File(configPath);
      if (!await configFile.exists()) {
        quests.add(
          _buildCorruptedQuest(questId: questId, error: 'config.json не найден'),
        );
        continue;
      }

      final content = await configFile.readAsString();

      Map<String, dynamic> config;
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          config = decoded;
        } else if (decoded is Map) {
          config = Map<String, dynamic>.from(decoded);
        } else {
          throw const FormatException('config.json не является JSON-объектом');
        }
      } catch (parseError) {
        print('[Quests] Повреждён config.json для квеста $questId: $parseError');
        quests.add(
          _buildCorruptedQuest(questId: questId, rawConfig: content, error: parseError),
        );
        continue;
      }

      String? localPreviewPath;
      final previewFileName = config['previewFileName']?.toString();

      if (previewFileName != null && previewFileName.isNotEmpty) {
        final fullPath = '${appDir.path}/quests/$questId/$previewFileName';
        if (await File(fullPath).exists()) {
          localPreviewPath = fullPath;
        }
      } else {
        final fallbackPath = '${appDir.path}/quests/$questId/preview.png';
        if (await File(fallbackPath).exists()) {
          localPreviewPath = fallbackPath;
        }
      }

      final isReadOnly = config['isReadOnly'] as bool? ?? false;
      if (isReadOnly) {
        final signature = config['signature']?.toString();
        if (!KeyDerivationService.verifyConfigSignature(questId, true, signature)) {
          throw Exception('Квест поврежден или модифицирован сторонним лицом (HMAC Error)');
        }
      }

      quests.add(
        Quest.fromJson(config).copyWith(id: questId, localPreviewPath: localPreviewPath),
      );
    } catch (e) {
      print('Ошибка загрузки квеста $questId: $e');
      quests.add(_buildCorruptedQuest(questId: questId, error: e));
    }
  }

  quests.sort((a, b) {
    final dateA = a.lastOpened ?? a.created ?? DateTime(1970);
    final dateB = b.lastOpened ?? b.created ?? DateTime(1970);
    return dateB.compareTo(dateA);
  });

  return quests;
});

final questProvider = FutureProvider.family<Quest?, String>((ref, questId) async {
  try {
    final configPath = 'quests/$questId/config.json';
    if (!await FileStorage.exists(configPath)) {
      return null;
    }

    Map<String, dynamic> config;
    try {
      config = await FileStorage.readJsonFile(configPath);
    } catch (readError) {
      print('[Quest] Ошибка чтения config.json для $questId: $readError');
      final backupPath = 'quests/$questId/config.json.backup';
      if (await FileStorage.exists(backupPath)) {
        try {
          print('🔄 [Quest] Попытка восстановления из бэкапа...');
          final backupFile = File(await FileStorage.getFilePath(backupPath));
          final backupContent = await backupFile.readAsString();
          final backupDecoded = jsonDecode(backupContent);
          if (backupDecoded is Map<String, dynamic>) {
            config = backupDecoded;
          } else if (backupDecoded is Map) {
            config = Map<String, dynamic>.from(backupDecoded);
          } else {
            throw const FormatException('backup config.json не является JSON-объектом');
          }
          await FileStorage.writeJsonFile(configPath, config);
          print('[Quest] Восстановлено из бэкапа');
        } catch (backupError) {
          print('[Quest] Не удалось восстановить из бэкапа: $backupError');
          return null;
        }
      } else {
        return null;
      }
    }

    final now = DateTime.now();

    String? localPreviewPath;
    final previewFileName = config['previewFileName']?.toString();

    if (previewFileName != null && previewFileName.isNotEmpty) {
      final fullPath = await FileStorage.getFilePath('quests/$questId/$previewFileName');
      if (await File(fullPath).exists()) {
        localPreviewPath = fullPath;
      }
    } else {
      final fallbackPath = await FileStorage.getFilePath('quests/$questId/preview.png');
      if (await File(fallbackPath).exists()) {
        localPreviewPath = fallbackPath;
      }
    }

    final isReadOnly = config['isReadOnly'] as bool? ?? false;
    if (isReadOnly) {
      final signature = config['signature']?.toString();
      if (!KeyDerivationService.verifyConfigSignature(questId, true, signature)) {
        throw Exception('Квест поврежден или модифицирован сторонним лицом (HMAC Error)');
      }
    }

    final updatedQuest = Quest.fromJson(config).copyWith(
      id: questId,
      lastOpened: now,
      localPreviewPath: localPreviewPath,
    );

    unawaited(
      FileStorage.writeJsonFile(configPath, {
        ...config,
        'lastOpened': now.toIso8601String(),
      }),
    );

    return updatedQuest;
  } catch (e) {
    print('[Quest] Критическая ошибка загрузки квеста $questId: $e');
    return null;
  }
});
