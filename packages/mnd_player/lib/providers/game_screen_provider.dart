import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Добавлен для jsonEncode при отладке

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:mnd_core/mnd_core.dart' hide ScriptCacheService;
import 'package:mnd_player/services/script_cache_service.dart';
import 'package:mnd_player/services/template_instance_resolver.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/providers/node_provider.dart';
import 'package:mnd_player/providers/template_provider.dart';
import 'package:mnd_player/providers/quest_provider.dart';
import 'package:mnd_player/providers/tag_provider.dart';
import 'package:mnd_player/services/font_service.dart';

@immutable
class GameScreenState {
  final bool isLoading;
  final String? error;
  final SavedNode? currentNode;
  final int revealedRawItemCount;
  final List<ContentItem> revealedItems;
  final List<ContentItem> resolvedHudPanels;
  final String? backgroundImagePath;
  final double? remainingSeconds;
  final String presentationId;
  final String? fontFamily;

  const GameScreenState({
    this.isLoading = true,
    this.error,
    this.currentNode,
    this.revealedRawItemCount = 0,
    this.revealedItems = const [],
    this.resolvedHudPanels = const [],
    this.backgroundImagePath,
    this.remainingSeconds,
    this.presentationId = '',
    this.fontFamily,
  });

  GameScreenState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    SavedNode? currentNode,
    bool clearCurrentNode = false,
    int? revealedRawItemCount,
    List<ContentItem>? revealedItems,
    List<ContentItem>? resolvedHudPanels,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    double? remainingSeconds,
    bool clearRemainingSeconds = false,
    String? presentationId,
    String? fontFamily,
  }) {
    return GameScreenState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      currentNode: clearCurrentNode ? null : (currentNode ?? this.currentNode),
      revealedRawItemCount: revealedRawItemCount ?? this.revealedRawItemCount,
      revealedItems: revealedItems ?? this.revealedItems,
      resolvedHudPanels: resolvedHudPanels ?? this.resolvedHudPanels,
      backgroundImagePath: clearBackgroundImage
          ? null
          : backgroundImagePath ?? this.backgroundImagePath,
      remainingSeconds: clearRemainingSeconds
          ? null
          : remainingSeconds ?? this.remainingSeconds,
      presentationId: presentationId ?? this.presentationId,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class GameScreenNotifier extends StateNotifier<GameScreenState> {
  final Ref _ref;
  final String _questId;

  final AudioPlayer _backgroundAudioPlayer = AudioPlayer();
  final AudioPlayer _soundEffectPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _backgroundPlayerStateSub;
  StreamSubscription<PlayerState>? _soundEffectPlayerStateSub;
  ProviderSubscription<GameState>? _gameStateSub;
  String? _currentBackgroundAudioId;
  bool _isGlobalMusic = false;
  bool _isMusicPaused = false;
  String? _questVersion;
  Timer? _countdownTimer;
  String? _loadingNodeId;
  bool _isAudioBroken = false;
  // Reentrancy guard: revealNextItem может вызываться из нескольких мест
  // одновременно (postFrameCallback внутри InstantItem, рекурсивный вызов
  // для script-айтемов, ConditionalContentWrapper.onComplete и др.).
  // Раньше тело было полностью синхронным внутри Future.microtask, поэтому
  // гонок не было. После того как в reveal добавился await на
  // TemplateInstanceResolver, два параллельных reveal могли прочитать один
  // и тот же индекс и продублировать айтем (видимый баг — задвоенные
  // кнопки). Этот флаг строго сериализует reveal.
  bool _isRevealing = false;
  bool _revealRequested = false;
  Map<String, dynamic>? _questConfigCache;
  Map<String, SavedNode>? _nodesByIdCache;
  Map<String, Tag>? _tagsByIdCache;
  static const String _legacyTitleOnNodeEnter =
      '\u041f\u0440\u0438 \u0437\u0430\u043f\u0443\u0441\u043a\u0435 \u043d\u043e\u0434\u044b';
  static const String _legacyTitleOnPress =
      '\u041f\u0440\u0438 \u043d\u0430\u0436\u0430\u0442\u0438\u0438';

  GameScreenNotifier(this._ref, this._questId)
    : super(const GameScreenState()) {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    _gameStateSub = _ref.listen<GameState>(gameStateProvider, (prev, next) {
      final prevTagVol = prev?.variables['_internal_tag_volume'];
      final nextTagVol = next.variables['_internal_tag_volume'];
      if (prevTagVol != nextTagVol) {
        _applyBackgroundVolumeFromState();
      }
      _handleAudioScriptCommands(next.variables);
    });
  }

  void _log(String message) {
    if (kDebugMode) {
      print('🎮 [GameScreen] $message');
    }
  }

  void _audioLog(String message) {
    debugPrint('[QuestAudio][bg] $message');
  }

  String _normalizeBackgroundAudioId(String rawId) {
    final normalized = rawId.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return normalized;

    final fullPrefix = 'quests/$_questId/';
    if (normalized.startsWith(fullPrefix)) {
      return _normalizeBackgroundAudioId(
        normalized.substring(fullPrefix.length),
      );
    }

    if (normalized.startsWith('/')) {
      return _normalizeBackgroundAudioId(normalized.substring(1));
    }

    if (normalized.startsWith('res/audio/')) {
      return normalized;
    }

    return 'res/audio/$normalized';
  }

  Future<Map<String, dynamic>> _readQuestConfigCached() async {
    if (_questConfigCache != null) return _questConfigCache!;
    _questConfigCache = await FileStorage.readJsonFile(
      'quests/$_questId/config.json',
    );
    return _questConfigCache!;
  }

  Future<void> _ensureNodesCache() async {
    if (_nodesByIdCache != null) return;
    final allNodes = await _ref.read(allQuestNodesProvider(_questId).future);
    _nodesByIdCache = {for (final n in allNodes) n.id: n};
  }

  /// Получить актуальный резолвер шаблонов для квеста. Используется в
  /// runtime, чтобы развернуть linked-инстансы (ноды и контент-айтемы) в
  /// полноценное содержимое мастера. Если резолвер ещё не загрузился —
  /// возвращает null, и тогда исходный объект остаётся «тощим» (рендерится
  /// как есть).
  Future<TemplateInstanceResolver?> _getTemplateResolver() async {
    try {
      return await _ref.read(templateInstanceResolverProvider(_questId).future);
    } catch (e) {
      _log('⚠️ Template resolver unavailable: $e');
      return null;
    }
  }

  /// Развернуть ноду, если она linked-инстанс. Иначе вернуть как есть.
  Future<SavedNode> _resolveNodeIfLinked(SavedNode node) async {
    if (!node.isTemplateInstance) return node;
    final resolver = await _getTemplateResolver();
    if (resolver == null) return node;
    return resolver.resolveNode(node);
  }

  /// Развернуть ContentItem (вместе со всеми вложенными linked-инстансами).
  /// Используется в runtime для каждого item-а, который реально показывается
  /// в `revealNextItem`.
  Future<ContentItem> _resolveItemTreeIfLinked(ContentItem item) async {
    // Быстрый путь: дерево не содержит linked.
    if (!_treeHasLinked(item)) return item;
    final resolver = await _getTemplateResolver();
    if (resolver == null) return item;
    return resolver.resolveTree(item);
  }

  bool _treeHasLinked(ContentItem item) {
    if (item.isTemplateInstance) return true;
    final children = item.children;
    if (children == null) return false;
    for (final c in children) {
      if (_treeHasLinked(c)) return true;
    }
    return false;
  }

  Future<Map<String, SavedNode>> _readNodesByIdDirectlyFromDisk() async {
    return FileStorage.synchronized('nodes_$_questId', () async {
      final nodesPath = 'quests/$_questId/nodes.json';
      if (!await FileStorage.exists(nodesPath)) {
        return <String, SavedNode>{};
      }

      final nodesData = await FileStorage.readJsonFile(nodesPath);
      final nodesJson = nodesData['nodes'] as List<dynamic>? ?? const [];
      final byId = <String, SavedNode>{};

      for (final raw in nodesJson) {
        if (raw is Map<String, dynamic>) {
          try {
            final node = SavedNode.fromJson(raw);
            byId[node.id] = node;
          } catch (_) {
            // Skip broken entries to avoid failing full reload.
          }
        }
      }
      return byId;
    });
  }

  Future<void> _ensureTagsCache() async {
    if (_tagsByIdCache != null) return;
    final tags = await _ref.read(questTagsProvider(_questId).future);
    _tagsByIdCache = {for (final t in tags) t.id: t};
  }

  void invalidateQuestCaches() {
    _questConfigCache = null;
    _nodesByIdCache = null;
    _tagsByIdCache = null;
    ScriptCacheService().invalidateQuest(_questId);
  }

  Future<Map<String, dynamic>> _loadDefaultVariables({
    Map<String, dynamic>? config,
  }) async {
    final Map<String, dynamic> defaults = {};
    try {
      final cfg = config ?? await _readQuestConfigCached();
      _questVersion = (cfg['version']?.toString().trim().isNotEmpty ?? false)
          ? cfg['version'].toString().trim()
          : '1.0.0';
      final variablesList = cfg['variables'] as List<dynamic>? ?? [];
      for (final v in variablesList) {
        if (v is Map<String, dynamic>) {
          final name = v['name'] as String?;
          final val = v['defaultValue'];
          if (name != null) {
            defaults[name] = val;
          }
        }
      }
    } catch (e) {
      _log("⚠️ Error loading default variables: $e");
    }
    defaults['_internal_background_blur'] = 10.0;
    defaults['_internal_node_content_volume'] = 1.0;
    defaults['_internal_tag_volume'] = 1.0;
    defaults['_internal_play_sound_id'] = null;
    defaults['_internal_play_sound_volume'] = 1.0;
    defaults['_internal_stop_sound_target'] = null;
    defaults['_internal_play_music_id'] = null;
    defaults['_internal_play_music_volume'] = 1.0;
    defaults['_internal_play_music_loop'] = true;
    defaults['_internal_play_music_global'] = false;
    defaults['_internal_stop_music'] = false;
    defaults['_internal_pause_resume_target'] = 'all';
    defaults['_internal_pause_resume_action'] = 'toggle';
    defaults['_internal_crossfade_fade_out'] = null;
    defaults['_internal_crossfade_fade_in'] = null;
    defaults['ID'] = '';
    defaults['LastID'] = '';
    defaults['_SYS_QUEST_VERSION'] = _questVersion ?? '1.0.0';
    return defaults;
  }

  // Загрузка дефолтных таблиц из конфига (для новой игры)
  Future<Map<String, dynamic>> _loadDefaultTables({
    Map<String, dynamic>? config,
  }) async {
    final Map<String, dynamic> tablesMap = {};
    try {
      final cfg = config ?? await _readQuestConfigCached();
      final tablesList = cfg['tables'] as List<dynamic>? ?? [];
      for (final t in tablesList) {
        if (t is Map<String, dynamic>) {
          final name = t['name'] as String?;
          if (name != null) {
            tablesMap[name] = t;
          }
        }
      }
    } catch (e) {
      _log("⚠️ Error loading default tables: $e");
    }
    return tablesMap;
  }

  Future<void> initializeGameSession() async {
    _log("Initializing session...");
    try {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      await _backgroundAudioPlayer.setReleaseMode(ReleaseMode.loop);
      _backgroundPlayerStateSub = _backgroundAudioPlayer.onPlayerStateChanged
          .listen((state) {
            _audioLog('bg state=$state');
          });
      await _soundEffectPlayer.setReleaseMode(ReleaseMode.stop);
      _soundEffectPlayerStateSub = _soundEffectPlayer.onPlayerStateChanged
          .listen((state) {
            _audioLog('sfx state=$state');
          });
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _backgroundAudioPlayer.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              usageType: AndroidUsageType.game,
              contentType: AndroidContentType.music,
              audioFocus: AndroidAudioFocus.none,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
      }

      await _loadCustomFont();

      _log("Audio & Font initialized");
    } catch (e) {
      _log("⚠️ Init Error (Non-fatal): $e");
      _isAudioBroken = true;
    }
  }

  Future<void> _loadCustomFont() async {
    try {
      final quest = await _ref.read(questProvider(_questId).future);
      if (quest?.customFontFileName != null) {
        _log("Loading custom font: ${quest!.customFontFileName}");
        final fontFamily = await FontService.loadQuestFont(
          _questId,
          quest.customFontFileName!,
        );
        if (mounted && fontFamily != null) {
          state = state.copyWith(fontFamily: fontFamily);
        }
      }
    } catch (e) {
      _log("Font load error: $e");
    }
  }

  Future<void> loadInitialNode(
    String? startNodeId, {
    SaveSlot? saveSlot,
  }) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final config = await _readQuestConfigCached();

      final variables = await _loadDefaultVariables(config: config);
      Map<String, dynamic> tablesJson = {};

      String targetNodeId;

      if (saveSlot != null) {
        _log("Loading SAVE: '${saveSlot.slotName}'");
        variables.addAll(saveSlot.variables);
        tablesJson = saveSlot.tables; // Загружаем таблицы из сохранения
        targetNodeId = saveSlot.currentNodeId;
      } else {
        _log("Starting NEW GAME.");
        tablesJson = await _loadDefaultTables(
          config: config,
        ); // Загружаем дефолтные таблицы

        if (startNodeId == null || startNodeId.isEmpty) {
          targetNodeId = config['startNodeId'] as String? ?? '';
        } else {
          targetNodeId = startNodeId;
        }
      }

      if (targetNodeId.isEmpty) {
        throw Exception('Start node not found (empty ID).');
      }

      // ИСПРАВЛЕНИЕ ОШИБКИ: Передаем именованные параметры
      _ref
          .read(gameStateProvider.notifier)
          .restoreState(variables: variables, tablesJson: tablesJson);

      await _ensureNodesCache();
      await loadNode(targetNodeId);
    } catch (e, stack) {
      _log("Error in loadInitialNode: $e\n$stack");
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  @override
  void dispose() {
    _log("DISPOSING GAME SCREEN.");
    try {
      try {
        WakelockPlus.disable();
      } catch (_) {}
      _stopTimer();
      _gameStateSub?.close();
      _backgroundPlayerStateSub?.cancel();
      _soundEffectPlayerStateSub?.cancel();
      _backgroundAudioPlayer.stop();
      _soundEffectPlayer.stop();
      _backgroundAudioPlayer.dispose();
      _soundEffectPlayer.dispose();
      ScriptCacheService().invalidateQuest(_questId);
    } catch (e) {
      _log("⚠️ Dispose warning: $e");
    }
    super.dispose();
  }

  void setBackgroundVolume(double volume) {
    if (_isAudioBroken) return;
    try {
      _backgroundAudioPlayer.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      _log("Audio volume error: $e");
    }
  }

  void _updateSystemVariables(String currentNodeId) {
    final gameStateNotifier = _ref.read(gameStateProvider.notifier);
    final now = DateTime.now();

    final currentId = gameStateNotifier.getVariable('ID');
    if (currentId != null && currentId.toString().isNotEmpty) {
      gameStateNotifier.setVariable('LastID', currentId);
    } else {
      gameStateNotifier.setVariable('LastID', '');
    }
    gameStateNotifier.setVariable('ID', currentNodeId);

    gameStateNotifier.setVariable('_SYS_HOUR', now.hour);
    gameStateNotifier.setVariable('_SYS_MINUTE', now.minute);
    gameStateNotifier.setVariable('_SYS_WEEKDAY', now.weekday);
    gameStateNotifier.setVariable('_SYS_DAY', now.day);
    gameStateNotifier.setVariable('_SYS_MONTH', now.month);
    gameStateNotifier.setVariable('_SYS_YEAR', now.year);
    gameStateNotifier.setVariable(
      '_SYS_QUEST_VERSION',
      _questVersion ?? '1.0.0',
    );

    String platform = 'unknown';
    if (kIsWeb) {
      platform = 'web';
    } else if (Platform.isAndroid) {
      platform = 'android';
    } else if (Platform.isIOS) {
      platform = 'ios';
    } else if (Platform.isWindows) {
      platform = 'windows';
    } else if (Platform.isLinux) {
      platform = 'linux';
    } else if (Platform.isMacOS) {
      platform = 'macos';
    }
    gameStateNotifier.setVariable('_SYS_PLATFORM', platform);
  }

  String? _resolveScriptEventTypeName(Map<String, dynamic> block) {
    final rawEventType = block['eventType']?.toString().trim();
    if (rawEventType != null && rawEventType.isNotEmpty) {
      return rawEventType;
    }

    final title = block['title']?.toString().trim() ?? '';
    if (title == _legacyTitleOnNodeEnter) {
      return EventType.onNodeEnter.name;
    }
    if (title == _legacyTitleOnPress) {
      return EventType.onPress.name;
    }

    if (block['type'] == 'event' || title.isNotEmpty) {
      return EventType.onContentAppear.name;
    }
    return null;
  }

  bool _scriptHasEvent(Map<String, dynamic> scriptData, EventType eventType) {
    final blocks = scriptData['blocks'] as List<dynamic>? ?? const [];
    for (final block in blocks.whereType<Map<String, dynamic>>()) {
      if (block['type'] != 'event') continue;
      final typeName = _resolveScriptEventTypeName(block);
      if (typeName == eventType.name) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _runInlineOnNodeEnterScripts(
    SavedNode node,
    String expectedNodeId,
  ) async {
    final rawItems = node.content['items'] as List<dynamic>? ?? const [];
    for (final rawItem in rawItems.whereType<Map<String, dynamic>>()) {
      if (rawItem['type'] != 'script') continue;

      final resourcePath = rawItem['resourcePath']?.toString();
      if (resourcePath == null || resourcePath.isEmpty) continue;

      final scriptPath = 'quests/$_questId/$resourcePath';

      try {
        final scriptData = await ScriptCacheService().getScript(scriptPath);
        if (scriptData == null ||
            !_scriptHasEvent(scriptData, EventType.onNodeEnter)) {
          continue;
        }

        _log("   Running inline onNodeEnter script: $resourcePath");
        final gameStateNotifier = _ref.read(gameStateProvider.notifier);
        final nextNodeId = await ScriptExecutor.execute(
          scriptData,
          gameStateNotifier,
          questId: _questId,
          eventType: EventType.onNodeEnter,
          contentItemId: null,
        );

        if (!mounted || _loadingNodeId != expectedNodeId) return null;

        await _applyBackgroundVolumeFromState();

        if (nextNodeId != null && nextNodeId.isNotEmpty) {
          return nextNodeId;
        }
      } catch (e) {
        _log("Inline onNodeEnter script error: $e");
      }
    }

    return null;
  }

  Future<void> loadNode(String nodeId) async {
    _log(">>> START LOAD NODE: '$nodeId'");
    _loadingNodeId = nodeId;
    _isRevealing = false;
    _revealRequested = false;

    _stopTimer();

    final isInitialLoad = state.currentNode == null;
    if (mounted) {
      state = state.copyWith(
        isLoading: isInitialLoad,
        clearCurrentNode: isInitialLoad,
        revealedItems: [],
        revealedRawItemCount: 0,
        presentationId: const Uuid().v4(),
      );
    }

    try {
      await _ensureNodesCache();
      if (_nodesByIdCache?[nodeId] == null) {
        _nodesByIdCache = null;
        await _ensureNodesCache();
      }
      final rawNode = _nodesByIdCache?[nodeId];
      if (rawNode == null) {
        throw Exception('Node "$nodeId" not found.');
      }

      // Если нода — linked-инстанс шаблона, разворачиваем её через
      // TemplateInstanceResolver (контент + декоративные поля берутся
      // из мастер-шаблона, локальные только id/x/y/chapterId).
      final resolvedNode = await _resolveNodeIfLinked(rawNode);

      _log("   Node loaded: ${resolvedNode.title}");

      if (kDebugMode) {
        print("🔍 [DEBUG] Node Content RAW:");
        print(jsonEncode(resolvedNode.content));
      }

      _updateSystemVariables(nodeId);

      // Извлекаем и разворачиваем (resolve) hud_panel прямо здесь
      List<ContentItem> resolvedHuds = [];
      final rawItems = resolvedNode.content['items'] as List<dynamic>? ?? const [];
      final rawHuds = rawItems
          .whereType<Map<String, dynamic>>()
          .where((raw) => raw['type'] == 'hud_panel')
          .map((raw) => ContentItem.fromJson(raw))
          .toList();
      for (final rawHud in rawHuds) {
        resolvedHuds.add(await _resolveItemTreeIfLinked(rawHud));
      }

      if (mounted) {
        _isRevealing = false;
        _revealRequested = false;
        state = state.copyWith(
          isLoading: false,
          currentNode: resolvedNode,
          revealedItems: [],
          resolvedHudPanels: resolvedHuds,
          revealedRawItemCount: 0,
          presentationId: const Uuid().v4(),
        );
        _log("   UI State updated. Starting reveal...");
        revealNextItem();
      }

      _safeApplyScriptedVolumeChanges();

      _updateBackgrounds(resolvedNode).catchError((e) {
        _log("⚠️ Background update failed (non-fatal): $e");
      });

      ScriptCacheService()
          .preloadNodeScripts(_questId, resolvedNode.content)
          .catchError((e) {
            _log("⚠️ Script preload failed (non-fatal): $e");
          });

      String? transitionNodeId;

      if (resolvedNode.scriptAssetId != null &&
          resolvedNode.scriptAssetId!.isNotEmpty) {
        _log("   Checking Node Script: ${resolvedNode.scriptAssetId}");
        final scriptPath = 'quests/$_questId/${resolvedNode.scriptAssetId}';

        final scriptData = await ScriptCacheService().getScript(scriptPath);
        if (scriptData != null) {
          final gameStateNotifier = _ref.read(gameStateProvider.notifier);
          final result = await ScriptExecutor.execute(
            scriptData,
            gameStateNotifier,
            questId: _questId,
            eventType: EventType.onNodeEnter,
          );

          if (!mounted || _loadingNodeId != nodeId) return;

          await _applyBackgroundVolumeFromState();

          if (result != null) {
            transitionNodeId = result;
            _log("Node Asset Script triggered transition -> $result");
          }
        }
      }

      if (transitionNodeId == null) {
        final inlineTransitionNodeId = await _runInlineOnNodeEnterScripts(
          resolvedNode,
          nodeId,
        );
        if (!mounted || _loadingNodeId != nodeId) return;
        if (inlineTransitionNodeId != null) {
          transitionNodeId = inlineTransitionNodeId;
          _log(
            "Inline onNodeEnter script triggered transition -> $transitionNodeId",
          );
        }
      }

      if (transitionNodeId != null) {
        _log("Executing Transition to: $transitionNodeId");
        Future.microtask(() => loadNode(transitionNodeId!));
        return;
      }

      if (resolvedNode.timerDuration != null &&
          resolvedNode.timerDuration! > 0 &&
          resolvedNode.defaultActionNodeId != null) {
        _startTimer(
          resolvedNode.timerDuration!,
          resolvedNode.defaultActionNodeId!,
        );
      }
    } catch (e, stack) {
      _log("CRITICAL ERROR in loadNode: $e\n$stack");
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  void revealNextItem() {
    if (_isRevealing) {
      _revealRequested = true;
      return;
    }

    _isRevealing = true;
    Future.microtask(() async {
      try {
        do {
          _revealRequested = false;
          if (!mounted || state.currentNode == null) return;

          final nodeIdAtStart = state.currentNode!.id;
          final rawList =
              state.currentNode!.content['items'] as List<dynamic>? ?? [];

          final revealIndex = state.revealedRawItemCount;
          if (revealIndex >= rawList.length) {
            _log("   [Reveal] All items revealed ($revealIndex)");
            return;
          }

          // Важно: резервируем индекс синхронно ДО любого await.
          // Иначе несколько параллельных revealNextItem() могут прочитать один
          // и тот же revealedRawItemCount и добавить один айтем несколько раз.
          state = state.copyWith(revealedRawItemCount: revealIndex + 1);

          final rawItemJson = rawList[revealIndex] as Map<String, dynamic>;

          if (kDebugMode) {
            print("🔍 [DEBUG] Revealing Raw Item #$revealIndex: $rawItemJson");
          }

          ContentItem nextItem = ContentItem.fromJson(rawItemJson);

          // Обычные элементы не должны проходить через async-gap резолвера:
          // это сохраняет старое поведение и быстрее для квестов без шаблонов.
          if (_treeHasLinked(nextItem)) {
            nextItem = await _resolveItemTreeIfLinked(nextItem);
            if (!mounted || state.currentNode?.id != nodeIdAtStart) return;
          }

          _log("   [Reveal] Item $revealIndex: Type=${nextItem.type}");

          if (nextItem.type == 'script') {
            _log("⚡ Executing inline script item...");

            if (nextItem.resourcePath != null) {
              try {
                final scriptPath = 'quests/$_questId/${nextItem.resourcePath}';
                if (await FileStorage.exists(scriptPath)) {
                  final scriptData = await FileStorage.readJsonFile(scriptPath);

                  final gameStateNotifier = _ref.read(
                    gameStateProvider.notifier,
                  );

                  final nextNodeId = await ScriptExecutor.execute(
                    scriptData,
                    gameStateNotifier,
                    questId: _questId,
                    eventType: EventType.onContentAppear,
                    contentItemId: null,
                  );

                  if (!mounted || state.currentNode?.id != nodeIdAtStart) {
                    return;
                  }

                  await _applyBackgroundVolumeFromState();

                  if (nextNodeId != null && nextNodeId.isNotEmpty) {
                    loadNode(nextNodeId);
                    return;
                  }
                }
              } catch (e) {
                _log("Inline script error: $e");
              }
            }

            // script-айтем не рендерится, поэтому сразу раскрываем следующий.
            _revealRequested = true;
            continue;
          }

          if (!mounted || state.currentNode?.id != nodeIdAtStart) return;
          state = state.copyWith(
            revealedItems: [...state.revealedItems, nextItem],
          );
        } while (_revealRequested);
      } finally {
        _isRevealing = false;
        if (_revealRequested && mounted) {
          revealNextItem();
        }
      }
    });
  }

  void _startTimer(double duration, String defaultActionNodeId) {
    _stopTimer();
    if (duration < 0.1) duration = 0.1;

    if (mounted) {
      state = state.copyWith(remainingSeconds: duration);
    }

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final newTime = (state.remainingSeconds ?? 0) - 0.1;
      if (newTime > 0) {
        state = state.copyWith(remainingSeconds: newTime);
      } else {
        _log("⏰ Timer finished! Going to: $defaultActionNodeId");
        timer.cancel();
        loadNode(defaultActionNodeId);
      }
    });
  }

  void _stopTimer() {
    if (_countdownTimer?.isActive ?? false) {
      _countdownTimer?.cancel();
    }
    if (mounted && state.remainingSeconds != null) {
      state = state.copyWith(clearRemainingSeconds: true);
    }
  }

  void _safeApplyScriptedVolumeChanges() {
    _applyBackgroundVolumeFromState();
  }

  void _handleAudioScriptCommands(Map<String, dynamic> variables) {
    if (_isAudioBroken) return;

    final playSoundId = variables['_internal_play_sound_id'];
    if (playSoundId != null && playSoundId.toString().isNotEmpty) {
      final volume =
          (variables['_internal_play_sound_volume'] as num?)?.toDouble() ?? 1.0;
      _playSoundEffect(playSoundId.toString(), volume);
      variables.remove('_internal_play_sound_id');
      variables.remove('_internal_play_sound_volume');
    }

    final stopSoundTarget = variables['_internal_stop_sound_target'];
    if (stopSoundTarget != null) {
      _stopSoundEffect(stopSoundTarget.toString());
      variables.remove('_internal_stop_sound_target');
    }

    final playMusicId = variables['_internal_play_music_id'];
    if (playMusicId != null && playMusicId.toString().isNotEmpty) {
      final volume =
          (variables['_internal_play_music_volume'] as num?)?.toDouble() ?? 1.0;
      final loop = variables['_internal_play_music_loop'] as bool? ?? true;
      final global = variables['_internal_play_music_global'] as bool? ?? false;
      _playBackgroundMusic(playMusicId.toString(), volume, loop, global);
      variables.remove('_internal_play_music_id');
      variables.remove('_internal_play_music_volume');
      variables.remove('_internal_play_music_loop');
      variables.remove('_internal_play_music_global');
    }

    final stopMusic = variables['_internal_stop_music'];
    if (stopMusic == true) {
      _stopBackgroundMusic();
      variables.remove('_internal_stop_music');
    }

    final pauseAction = variables['_internal_pause_resume_action'];
    if (pauseAction != null) {
      final target = variables['_internal_pause_resume_target'] ?? 'all';
      _pauseResumeAudio(target.toString(), pauseAction.toString());
      variables.remove('_internal_pause_resume_action');
      variables.remove('_internal_pause_resume_target');
    }

    final crossfadeFadeOut = variables['_internal_crossfade_fade_out'];
    if (crossfadeFadeOut != null) {
      final durationMs = (crossfadeFadeOut as num).toInt();
      _crossfadeOut(durationMs);
      variables.remove('_internal_crossfade_fade_out');
    }

    final crossfadeIn = variables['_internal_crossfade_fade_in'];
    if (crossfadeIn != null) {
      final durationMs = (crossfadeIn as num).toInt();
      _crossfadeIn(durationMs);
      variables.remove('_internal_crossfade_fade_in');
    }
  }

  String? _currentSfxAudioId;

  Future<void> _playSoundEffect(String audioId, double volume) async {
    if (_isAudioBroken) return;
    try {
      final normalizedId = _normalizeBackgroundAudioId(audioId);
      final audioPath = 'quests/$_questId/$normalizedId';
      final fullPath = await FileStorage.getFilePath(audioPath);

      if (await File(fullPath).exists()) {
        _currentSfxAudioId = normalizedId;
        await _soundEffectPlayer.stop();
        await _soundEffectPlayer.setVolume(volume.clamp(0.0, 1.0));
        await _soundEffectPlayer.play(DeviceFileSource(fullPath));
        _log("🔊 Sound effect: $audioId (Vol: $volume)");
      }
    } catch (e) {
      _log("Sound effect error: $e");
    }
  }

  void _stopSoundEffect(String target) {
    if (_isAudioBroken) return;
    try {
      if (target == 'all') {
        _soundEffectPlayer.stop();
        _currentSfxAudioId = null;
        _backgroundAudioPlayer.stop();
        _currentBackgroundAudioId = null;
        _isGlobalMusic = false;
        _isMusicPaused = false;
        _log("⏹ All audio stopped (SFX + Music)");
      } else {
        final normalizedTarget = _normalizeBackgroundAudioId(target);
        final sfxMatches =
            _currentSfxAudioId != null &&
            (_currentSfxAudioId == normalizedTarget ||
                _currentSfxAudioId!.endsWith(normalizedTarget) ||
                normalizedTarget.endsWith(_currentSfxAudioId!));
        final musicMatches =
            _currentBackgroundAudioId != null &&
            (_currentBackgroundAudioId == normalizedTarget ||
                _currentBackgroundAudioId!.endsWith(normalizedTarget) ||
                normalizedTarget.endsWith(_currentBackgroundAudioId!));

        if (sfxMatches) {
          _soundEffectPlayer.stop();
          _currentSfxAudioId = null;
          _log("⏹ Sound effect stopped: $target");
        } else if (musicMatches) {
          _backgroundAudioPlayer.stop();
          _currentBackgroundAudioId = null;
          _isGlobalMusic = false;
          _isMusicPaused = false;
          _log("⏹ Music stopped: $target");
        } else {
          _log(
            "⏹ No audio matching: $target (SFX: $_currentSfxAudioId, Music: $_currentBackgroundAudioId)",
          );
        }
      }
    } catch (e) {
      _log("Stop sound error: $e");
    }
  }

  Future<void> _playBackgroundMusic(
    String audioId,
    double volume,
    bool loop,
    bool global,
  ) async {
    if (_isAudioBroken) return;
    try {
      await _backgroundAudioPlayer.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.stop,
      );

      _isGlobalMusic = global;

      final normalizedId = _normalizeBackgroundAudioId(audioId);
      final audioPath = 'quests/$_questId/$normalizedId';
      final fullPath = await FileStorage.getFilePath(audioPath);

      if (await File(fullPath).exists()) {
        _currentBackgroundAudioId = normalizedId;
        _isMusicPaused = false;
        await _backgroundAudioPlayer.stop();
        await _backgroundAudioPlayer.setVolume(volume.clamp(0.0, 1.0));
        await _backgroundAudioPlayer.play(DeviceFileSource(fullPath));
        _log("🎵 Background music: $audioId (Vol: $volume, Loop: $loop)");
      }
    } catch (e) {
      _log("Background music error: $e");
    }
  }

  void _stopBackgroundMusic() {
    if (_isAudioBroken) return;
    try {
      _backgroundAudioPlayer.stop();
      _currentBackgroundAudioId = null;
      _isGlobalMusic = false;
      _isMusicPaused = false;
      _log("⏹ Background music stopped");
    } catch (e) {
      _log("Stop music error: $e");
    }
  }

  void _pauseResumeAudio(String target, String action) {
    if (_isAudioBroken) return;
    try {
      final shouldPause =
          action == 'pause' || (action == 'toggle' && !_isMusicPaused);
      final shouldResume =
          action == 'resume' || (action == 'toggle' && _isMusicPaused);

      if (target == 'all' || target == 'music') {
        if (shouldPause) {
          _backgroundAudioPlayer.pause();
          _isMusicPaused = true;
          _log("⏸ Music paused");
        } else if (shouldResume) {
          _backgroundAudioPlayer.resume();
          _isMusicPaused = false;
          _log("▶ Music resumed");
        }
      }

      if (target == 'all' || target == 'sound') {
        if (shouldPause) {
          _soundEffectPlayer.pause();
        } else if (shouldResume) {
          _soundEffectPlayer.resume();
        }
      }
    } catch (e) {
      _log("Pause/resume error: $e");
    }
  }

  Future<void> _crossfadeOut(int durationMs) async {
    if (_isAudioBroken) return;
    try {
      final steps = 20;
      final stepDuration = Duration(milliseconds: (durationMs / steps).round());
      for (int i = 0; i <= steps; i++) {
        final volume = (1.0 - (i / steps)).clamp(0.0, 1.0);
        await _backgroundAudioPlayer.setVolume(volume);
        await Future.delayed(stepDuration);
      }
      _log("🎵 Crossfade fade-out complete");
    } catch (e) {
      _log("Crossfade fade-out error: $e");
    }
  }

  Future<void> _crossfadeIn(int durationMs) async {
    if (_isAudioBroken) return;
    try {
      final steps = 20;
      final stepDuration = Duration(milliseconds: (durationMs / steps).round());
      for (int i = 0; i <= steps; i++) {
        final volume = (i / steps).clamp(0.0, 1.0);
        await _backgroundAudioPlayer.setVolume(volume);
        await Future.delayed(stepDuration);
      }
      _log("🎵 Crossfade fade-in complete");
    } catch (e) {
      _log("Crossfade fade-in error: $e");
    }
  }

  Future<void> _applyBackgroundVolumeFromState() async {
    if (_isAudioBroken) return;
    final currentNode = state.currentNode;
    if (currentNode == null) return;

    final vars = _ref.read(gameStateProvider).variables;
    final tagVolume = (vars['_internal_tag_volume'] as num?)?.toDouble() ?? 1.0;

    double? newVolume;
    if (currentNode.backgroundAudioId != null &&
        currentNode.backgroundAudioId!.isNotEmpty) {
      newVolume = (currentNode.backgroundAudioVolume ?? 1.0) * tagVolume;
    } else if (currentNode.chapterId.isNotEmpty) {
      newVolume = tagVolume;
    }

    if (newVolume == null) return;
    try {
      final clamped = newVolume.clamp(0.0, 1.0);
      if (clamped <= 0.0001) {
        await _backgroundAudioPlayer.stop();
        return;
      }

      await _backgroundAudioPlayer.setVolume(clamped);

      if (_currentBackgroundAudioId != null &&
          _backgroundAudioPlayer.state == PlayerState.stopped) {
        final audioPath = 'quests/$_questId/$_currentBackgroundAudioId';
        final fullPath = await FileStorage.getFilePath(audioPath);
        if (await File(fullPath).exists()) {
          await _backgroundAudioPlayer.play(DeviceFileSource(fullPath));
        }
      }
    } catch (e) {
      _log("Audio volume error: $e");
    }
  }

  Future<void> _updateBackgrounds(SavedNode node) async {
    await Future.wait([
      _updateBackgroundAudio(node).catchError((e) => _log("Audio err: $e")),
      _loadBackgroundImage(node).catchError((e) => _log("Image err: $e")),
    ]);
  }

  Future<void> _updateBackgroundAudio(SavedNode node) async {
    if (_isAudioBroken) return;
    try {
      if (_isGlobalMusic && _currentBackgroundAudioId != null) {
        _log("   🎵 Global music playing, skipping node audio update");
        return;
      }

      String? newAudioId;
      double newVolume = 1.0;
      final tagVolume =
          (_ref.read(gameStateProvider).variables['_internal_tag_volume']
                  as num?)
              ?.toDouble() ??
          1.0;

      if (node.backgroundAudioId != null &&
          node.backgroundAudioId!.isNotEmpty) {
        newAudioId = node.backgroundAudioId;
        newVolume = (node.backgroundAudioVolume ?? 1.0) * tagVolume;
      } else if (node.chapterId.isNotEmpty) {
        await _ensureTagsCache();
        final currentTag = _tagsByIdCache?[node.chapterId];
        newAudioId = currentTag?.backgroundAudioId;
        newVolume = tagVolume;
      }

      final normalizedAudioId = (newAudioId != null && newAudioId.isNotEmpty)
          ? _normalizeBackgroundAudioId(newAudioId)
          : null;

      if (normalizedAudioId == _currentBackgroundAudioId) {
        final clamped = newVolume.clamp(0.0, 1.0);
        if (clamped <= 0.0001) {
          await _backgroundAudioPlayer.stop();
          return;
        }
        await _backgroundAudioPlayer.setVolume(clamped);
        return;
      }

      _currentBackgroundAudioId = normalizedAudioId;

      if (normalizedAudioId != null && normalizedAudioId.isNotEmpty) {
        final audioPath = 'quests/$_questId/$normalizedAudioId';
        final fullPath = await FileStorage.getFilePath(audioPath);
        _audioLog(
          'switch id=$normalizedAudioId path=$fullPath volume=${newVolume.clamp(0.0, 1.0)}',
        );

        if (await File(fullPath).exists()) {
          try {
            await _backgroundAudioPlayer.stop();
            final clamped = newVolume.clamp(0.0, 1.0);
            if (clamped <= 0.0001) {
              return;
            }
            await _backgroundAudioPlayer.setVolume(clamped);
            await _backgroundAudioPlayer.play(DeviceFileSource(fullPath));
            await Future<void>.delayed(const Duration(milliseconds: 120));
            if (_backgroundAudioPlayer.state != PlayerState.playing &&
                _currentBackgroundAudioId == normalizedAudioId) {
              _audioLog('first play did not reach playing, retrying once');
              await _backgroundAudioPlayer.stop();
              await _backgroundAudioPlayer.setVolume(clamped);
              await _backgroundAudioPlayer.play(DeviceFileSource(fullPath));
            }
            _log(
              "🔊 Background audio started: $normalizedAudioId (Vol: $newVolume)",
            );
          } catch (playerError) {
            _log("⚠️ AudioPlayer Error: $playerError");
            if (playerError.toString().contains("MissingPluginException")) {
              _isAudioBroken = true;
            }
          }
        }
      } else {
        try {
          await _backgroundAudioPlayer.stop();
        } catch (_) {}
      }
    } catch (e) {
      _log('Audio logic error: $e');
    }
  }

  Future<void> _loadBackgroundImage(SavedNode node) async {
    try {
      String? finalBackgroundId;

      if (node.backgroundAssetId != null &&
          node.backgroundAssetId!.isNotEmpty) {
        finalBackgroundId = node.backgroundAssetId;
      } else if (node.chapterId.isNotEmpty) {
        await _ensureTagsCache();
        final currentTag = _tagsByIdCache?[node.chapterId];
        if (currentTag?.backgroundAssetId != null &&
            currentTag!.backgroundAssetId!.isNotEmpty) {
          finalBackgroundId = currentTag.backgroundAssetId;
        }
      }

      if (finalBackgroundId == null) {
        final quest = await _ref.read(questProvider(_questId).future);
        if (quest?.backgroundAssetId != null &&
            quest!.backgroundAssetId!.isNotEmpty) {
          finalBackgroundId = quest.backgroundAssetId;
        }
      }

      if (finalBackgroundId != null && finalBackgroundId.isNotEmpty) {
        final imagePath = 'quests/$_questId/res/images/$finalBackgroundId';
        final fullPath = await FileStorage.getFilePath(imagePath);

        if (await File(fullPath).exists()) {
          if (mounted) state = state.copyWith(backgroundImagePath: fullPath);
          return;
        }
      }

      if (mounted) state = state.copyWith(clearBackgroundImage: true);
    } catch (e) {
      _log("Background error: $e");
      if (mounted) state = state.copyWith(clearBackgroundImage: true);
    }
  }
}

final gameScreenProvider = StateNotifierProvider.autoDispose
    .family<GameScreenNotifier, GameScreenState, String>((ref, questId) {
      return GameScreenNotifier(ref, questId);
    });
