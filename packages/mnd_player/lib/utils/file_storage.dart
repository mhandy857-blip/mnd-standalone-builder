import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic>? _tryDecodeJson(String content, {String? path}) {
  try {
    if (content.isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  } catch (e) {
    print(
      '[FileStorage] Ошибка парсинга JSON${path != null ? ' ($path)' : ''}: $e',
    );
    return null;
  }
}

Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> source) {
  final encoded = jsonEncode(source);
  final decoded = jsonDecode(encoded);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return <String, dynamic>{};
}

class _Lock {
  Future<void>? _last;

  Future<T> synchronized<T>(FutureOr<T> Function() func) async {
    final previous = _last;
    final completer = Completer<void>();
    _last = completer.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await func();
    } finally {
      completer.complete();
    }
  }
}

class FileStorage {
  static final _uuid = const Uuid();
  static Future<Directory>? _appDirectoryFuture;
  static final Map<String, Map<String, dynamic>> _jsonCache = {};
  static const Duration _slowIoThreshold = Duration(milliseconds: 120);

  static final Map<String, _Lock> _locks = {};

  static Future<T> synchronized<T>(String key, Future<T> Function() func) {
    final lock = _locks.putIfAbsent(key, () => _Lock());
    return lock.synchronized(func);
  }

  static String generateUniqueId() {
    return _uuid.v4();
  }

  static Future<Directory> getAppDirectory() async {
    _appDirectoryFuture ??= getApplicationDocumentsDirectory();
    return _appDirectoryFuture!;
  }

  static Future<Directory> createFolder(String relativePath) async {
    final appDir = await getAppDirectory();
    final folderPath = p.join(appDir.path, relativePath);
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return folder;
  }

  static Future<String> getFilePath(String relativePath) async {
    final appDir = await getAppDirectory();
    return p.join(appDir.path, relativePath);
  }

  static Future<Map<String, dynamic>> readJsonFile(String relativePath) async {
    final cached = _jsonCache[relativePath];
    if (cached != null) {
      return _cloneJsonMap(cached);
    }

    final ioStopwatch = Stopwatch()..start();
    final filePath = await getFilePath(relativePath);
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Файл $relativePath не существует');
    }

    final content = await file.readAsString();

    final result = _tryDecodeJson(content, path: relativePath);

    if (result != null) {
      _jsonCache[relativePath] = Map<String, dynamic>.from(result);
      ioStopwatch.stop();
      if (kDebugMode && ioStopwatch.elapsed > _slowIoThreshold) {
        print(
          '🐢 [FileStorage] Медленное чтение JSON: $relativePath '
          '(${ioStopwatch.elapsedMilliseconds}ms)',
        );
      }
      return _cloneJsonMap(result);
    }

    final backupPath = '$filePath.backup';
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      print('🔄 [FileStorage] Попытка восстановления из бэкапа: $backupPath');
      try {
        final backupContent = await backupFile.readAsString();
        final backupResult = _tryDecodeJson(backupContent, path: backupPath);
        if (backupResult != null) {
          print('[FileStorage] Восстановлено из бэкапа');
          await file.writeAsString(backupContent);
          _jsonCache[relativePath] = Map<String, dynamic>.from(backupResult);
          ioStopwatch.stop();
          if (kDebugMode && ioStopwatch.elapsed > _slowIoThreshold) {
            print(
              '🐢 [FileStorage] Медленное чтение JSON (backup): $relativePath '
              '(${ioStopwatch.elapsedMilliseconds}ms)',
            );
          }
          return _cloneJsonMap(backupResult);
        }
      } catch (e) {
        print('[FileStorage] Ошибка восстановления из бэкапа: $e');
      }
    }

    throw Exception('Файл $relativePath повреждён и не может быть прочитан');
  }

  static Future<void> writeJsonFile(
    String relativePath,
    Map<String, dynamic> data,
  ) async {
    final filePath = await getFilePath(relativePath);
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final jsonString = jsonEncode(data);

    final backupPath = '$filePath.backup';
    final backupFile = File(backupPath);
    if (await file.exists()) {
      try {
        await file.copy(backupPath);
      } catch (e) {
        print('⚠️ [FileStorage] Не удалось создать бэкап: $e');
      }
    }

    final tempPath = '$filePath.tmp.${DateTime.now().millisecondsSinceEpoch}';
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsString(jsonString, flush: true);

      final writtenContent = await tempFile.readAsString();
      final decoded = jsonDecode(writtenContent);
      if (decoded == null) {
        throw Exception('Записанные данные не являются валидным JSON');
      }

      try {
        await tempFile.rename(filePath);
      } on FileSystemException catch (_) {
        if (await tempFile.exists()) {
          await tempFile.copy(filePath);
          await tempFile.delete();
        } else {
          await file.writeAsString(jsonString, flush: true);
        }
      }
      _jsonCache[relativePath] = _cloneJsonMap(data);

      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (e) {
      print('[FileStorage] Ошибка записи файла $relativePath: $e');

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (await backupFile.exists()) {
        print('🔄 [FileStorage] Попытка отката к бэкапу...');
        try {
          await backupFile.copy(filePath);
        } catch (rollbackError) {
          print('[FileStorage] Ошибка отката: $rollbackError');
        }
      }

      rethrow;
    }
  }

  static Future<List<String>> listFiles(
    String relativePath, {
    String? extension,
  }) async {
    final folderPath = await getFilePath(relativePath);
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      return [];
    }
    final entities = await folder.list().toList();
    return entities
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .where((filename) => extension == null || filename.endsWith(extension))
        .toList();
  }

  static Future<List<String>> listFolders(String relativePath) async {
    final folderPath = await getFilePath(relativePath);
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      return [];
    }
    final entities = await folder.list().toList();
    return entities
        .whereType<Directory>()
        .map((dir) => p.basename(dir.path))
        .toList();
  }

  static Future<bool> exists(String relativePath) async {
    final path = await getFilePath(relativePath);
    return await File(path).exists() || await Directory(path).exists();
  }

  static Future<void> delete(String relativePath) async {
    final path = await getFilePath(relativePath);
    final file = File(path);
    final dir = Directory(path);
    if (await file.exists()) {
      await file.delete();
      _jsonCache.remove(relativePath);
    } else if (await dir.exists()) {
      await dir.delete(recursive: true);
      _jsonCache.removeWhere(
        (key, _) => key == relativePath || key.startsWith('$relativePath/'),
      );
    }
  }

  static Future<void> copyAssetQuestToDocuments(String questId) async {
    try {
      final questDocumentPath = p.join('quests', questId);

      if (kDebugMode && await exists(questDocumentPath)) {
        print(
          '🐞 [DEBUG MODE] Квест-обучение существует. Принудительная перезапись...',
        );
        await delete(questDocumentPath);
      }

      if (await exists(questDocumentPath)) {
        print('ℹ️ Квест-обучение уже скопирован, пропуск.');
        return;
      }

      print('⚙️ Распаковка квеста-обучения из ZIP-архива...');

      final assetPath = 'assets/packed_quests/$questId.zip';
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final targetFilePath = await getFilePath(
          p.join(questDocumentPath, filename),
        );

        if (file.isFile) {
          final data = file.content as List<int>;
          final targetFile = File(targetFilePath);
          await targetFile.parent.create(recursive: true);
          await targetFile.writeAsBytes(data);
        } else {
          await Directory(targetFilePath).create(recursive: true);
        }
      }

      print('Квест-обучение распакован.');
    } catch (e) {
      print('Ошибка при распаковке квеста-обучения: $e');
    }
  }

  static Future<void> clearDirectory(String relativePath) async {
    final path = await getFilePath(relativePath);
    final dir = Directory(path);
    if (!await dir.exists()) {
      return;
    }
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
    _jsonCache.removeWhere(
      (key, _) => key == relativePath || key.startsWith('$relativePath/'),
    );
  }
}
