import 'dart:io';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:flutter/services.dart';

class FontService {
  static Future<String?> loadQuestFont(String questId, String fileName) async {
    try {
      final fontPath = 'quests/$questId/res/fonts/$fileName';
      final fullPath = await FileStorage.getFilePath(fontPath);
      final file = File(fullPath);

      if (!await file.exists()) {
        print('⚠️ Шрифт не найден: $fullPath');
        return null;
      }

      final safeQuestId = questId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fontFamilyName = 'Font_${safeQuestId}_$safeFileName';

      final loader = FontLoader(fontFamilyName);

      final fontData = file.readAsBytes().then((bytes) {
        return ByteData.view(bytes.buffer);
      });

      loader.addFont(fontData);
      await loader.load();

      return fontFamilyName;
    } catch (e) {
      if (!e.toString().contains('already loaded')) {
        print('Ошибка загрузки шрифта: $e');
      }
      final safeQuestId = questId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      return 'Font_${safeQuestId}_$safeFileName';
    }
  }
}
