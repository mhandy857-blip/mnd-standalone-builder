import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_player/mnd_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _setupQuestAssets();
  MndPlayerBootstrap.initialize();
  runApp(const ProviderScope(child: TemplateQuestApp()));
}

Future<void> _setupQuestAssets() async {
  final appDir = await getApplicationDocumentsDirectory();
  final targetDir = p.join(appDir.path, 'quests', 'embedded');

  final configFile = File(p.join(targetDir, 'config.json'));
  if (await configFile.exists()) {
    if (kDebugMode) {
      await Directory(targetDir).delete(recursive: true);
    } else {
      return;
    }
  }

  await Directory(targetDir).create(recursive: true);

  try {
    final data = await rootBundle.load('assets/quest.mnd');
    final rawBytes = data.buffer.asUint8List();

    final header = String.fromCharCodes(rawBytes.take(8));
    Uint8List zipBytes;
    if (header == 'MND_ZIP_') {
      zipBytes = Uint8List.sublistView(rawBytes, 8);
    } else {
      zipBytes = rawBytes;
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);

    for (final file in archive) {
      final targetPath = p.join(targetDir, file.name);
      if (file.isFile) {
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(targetPath).create(recursive: true);
      }
    }
  } catch (e, st) {
    rethrow;
  }
}

class TemplateQuestApp extends ConsumerStatefulWidget {
  const TemplateQuestApp({super.key});

  @override
  ConsumerState<TemplateQuestApp> createState() => _TemplateQuestAppState();
}

class _TemplateQuestAppState extends ConsumerState<TemplateQuestApp> {
  String? _error;
  bool _loading = true;
  String? _questId;
  String? _startNodeId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      final configPath =
          p.join(appDir.path, 'quests', 'embedded', 'config.json');
      final configFile = File(configPath);

      if (!await configFile.exists()) {
        throw Exception('config.json not found in embedded quest');
      }

      final content = await configFile.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;
      final startNodeId = config['startNodeId'] as String? ?? '';

      if (mounted) {
        setState(() {
          _questId = 'embedded';
          _startNodeId = startNodeId;
          _loading = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null || _questId == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error ?? 'Error',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: GameScreen(
        questId: _questId!,
        startNodeId: _startNodeId,
        isTesting: false,
        isOnboarding: false,
      ),
    );
  }
}
