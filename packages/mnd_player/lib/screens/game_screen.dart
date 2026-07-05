import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';

import 'package:mnd_player/screens/table_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mnd_core/mnd_core.dart' hide ScriptCacheService;
import 'package:mnd_player/services/script_cache_service.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/platform_performance.dart';
import 'package:mnd_player/utils/trigger_reference.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/providers/quest_provider.dart';
import 'package:mnd_player/widgets/game_hud_panel.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/services/save_game_provider.dart';
import 'package:mnd_player/screens/load_game_screen.dart';
import 'package:mnd_player/widgets/glass.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String questId;
  final String? startNodeId;
  final bool isOnboarding;
  final SaveSlot? saveSlot;
  final bool isTesting;
  final VoidCallback? onEditNode;
  final VoidCallback? onFinish;
  final List<Widget>? additionalAppBarActions;

  const GameScreen({
    super.key,
    required this.questId,
    this.startNodeId,
    this.isOnboarding = false,
    this.saveSlot,
    this.isTesting = false,
    this.onEditNode,
    this.onFinish,
    this.additionalAppBarActions,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _varsSearchController = TextEditingController();
  String _varsSearchQuery = '';
  

  // Флаг для предотвращения лишних вызовов stop(), которые крашат Windows

  bool _shouldHideVariable(String key) => key == '_SYS_HISTORY';

  bool _isLargeValue(dynamic value) {
    if (value is String) return value.length > 120;
    if (value is List) return value.length > 20;
    if (value is Map) return value.length > 20;
    return false;
  }

  String _formatVariableValue(dynamic value) {
    if (value is String) {
      if (value.length <= 120) return value;
      return '${value.substring(0, 120)}...';
    }
    if (value is List) return 'List(${value.length})';
    if (value is Map) return 'Map(${value.length})';
    return value.toString();
  }

  void _showVariableDetails(BuildContext context, String key, dynamic value) {
    String content;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      if (value is Map || value is List) {
        content = encoder.convert(value);
      } else {
        content = value?.toString() ?? 'null';
      }
    } catch (_) {
      content = value?.toString() ?? 'null';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(key, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: SelectableText(
            content,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('\u0417\u0430\u043a\u0440\u044b\u0442\u044c'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    
    // Ждем окончания анимации перехода, прежде чем грузить тяжелые данные
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final notifier = ref.read(gameScreenProvider(widget.questId).notifier);
      await notifier.initializeGameSession();
      if (!mounted) return;
      await notifier.loadInitialNode(
        widget.startNodeId,
        saveSlot: widget.saveSlot,
      );
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _varsSearchController.dispose();
    super.dispose();
  }

  void _onItemInteract(ContentItem item) async {
    String? triggerRefRaw;
    if (item.type == 'input') {
      triggerRefRaw = item.scriptTriggers?['onSubmit'];
    } else {
      triggerRefRaw = item.scriptTriggers?['onPress'];
    }

    if (triggerRefRaw == null &&
        item.type == 'button' &&
        item.scriptTriggers?['onAppear'] != null) {
      final appearRef = TriggerReference.parse(
        item.scriptTriggers!['onAppear']!,
      );
      final appearScriptPath = appearRef.scriptPath;
      try {
        final fullPath = 'quests/${widget.questId}/$appearScriptPath';
        if (await FileStorage.exists(fullPath)) {
          final scriptData = await FileStorage.readJsonFile(fullPath);
          final eventType = ScriptExecutor.checkScriptEventType(scriptData);
          if (eventType == EventType.onPress) {
            triggerRefRaw = item.scriptTriggers!['onAppear']!;
          }
        }
      } catch (_) {}
    }

    if (triggerRefRaw != null) {
      final nextNodeId = await _executeButtonScript(triggerRefRaw, item.id);
      if (!mounted) return;
      if (nextNodeId != null) {
        ref
            .read(gameScreenProvider(widget.questId).notifier)
            .loadNode(nextNodeId);
        return;
      }
    }

    if (!mounted) return;

    if (item.targetNodeId != null) {
      final resolvedTarget = _resolveTargetNodeId(item.targetNodeId!);
      if (resolvedTarget == null || resolvedTarget.isEmpty) {
        return;
      }
      if (widget.isOnboarding && resolvedTarget == '_FINISH_ONBOARDING') {
        _handleOnboardingFinish();
      } else {
        ref
            .read(gameScreenProvider(widget.questId).notifier)
            .loadNode(resolvedTarget);
      }
    }
  }

  String? _resolveTargetNodeId(String rawTarget) {
    if (!rawTarget.startsWith('=')) return rawTarget;
    final expression = rawTarget.substring(1).trim();
    if (expression.isEmpty) return null;
    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    final result = ScriptExecutor.evaluateExpression(
      expression,
      gameStateNotifier,
    );
    return result?.toString();
  }

  Future<String?> _executeButtonScript(
    String triggerRefRaw,
    String itemId,
  ) async {
    try {
      final triggerRef = TriggerReference.parse(triggerRefRaw);
      final scriptPath = triggerRef.scriptPath;
      if (scriptPath.isEmpty) return null;
      final fullPath = 'quests/${widget.questId}/$scriptPath';

      final scriptData = await ScriptCacheService().getScript(fullPath);
      if (scriptData == null) return null;

      final gameStateNotifier = ref.read(gameStateProvider.notifier);

      if (triggerRef.isFunctionRef) {
        if (!ScriptExecutor.hasExecutableBlocksForEvent(
          scriptData,
          EventType.function,
          functionName: triggerRef.functionEntry,
        )) {
          return null;
        }
        return await ScriptExecutor.execute(
          scriptData,
          gameStateNotifier,
          questId: widget.questId,
          eventType: EventType.function,
          functionName: triggerRef.functionEntry,
          contentItemId: itemId,
        );
      }

      final hasOnPressBlocks = ScriptExecutor.hasExecutableBlocksForEvent(
        scriptData,
        EventType.onPress,
        contentItemId: itemId,
      );

      if (hasOnPressBlocks) {
        return await ScriptExecutor.execute(
          scriptData,
          gameStateNotifier,
          questId: widget.questId,
          eventType: EventType.onPress,
          contentItemId: itemId,
        );
      }

      final fallbackEvents = <EventType>[
        ScriptExecutor.checkScriptEventType(scriptData),
        EventType.onNodeEnter,
        EventType.onContentAppear,
      ];
      final attempted = <String>{EventType.onPress.name};

      for (final eventType in fallbackEvents) {
        if (!attempted.add(eventType.name)) continue;
        if (!ScriptExecutor.hasExecutableBlocksForEvent(
          scriptData,
          eventType,
          contentItemId: itemId,
          allowTargetMismatchFallback: eventType == EventType.onContentAppear,
        )) {
          continue;
        }

        final nextNodeId = await ScriptExecutor.execute(
          scriptData,
          gameStateNotifier,
          questId: widget.questId,
          eventType: eventType,
          contentItemId: itemId,
          allowTargetMismatchFallback: eventType == EventType.onContentAppear,
        );
        if (nextNodeId != null) {
          return nextNodeId;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  void _onInputSubmitted(String variableName, String value) {
    ref.read(gameStateProvider.notifier).setVariable(variableName, value);
  }

  void _handleOnboardingFinish() async {
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_completed_onboarding', true);
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (_) {}
    }
  }

  void _showVariablesDebug() {
    final vars = ref.read(gameStateProvider).variables;
    final tables = ref.read(gameStateProvider).tables;
    _varsSearchController.text = _varsSearchQuery;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              final filteredVars = vars.entries
                  .where((e) => !_shouldHideVariable(e.key))
                  .where(
                    (e) => e.key.toLowerCase().contains(
                      _varsSearchQuery.toLowerCase(),
                    ),
                  )
                  .toList();

              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "\u041e\u0442\u043b\u0430\u0434\u0447\u0438\u043a",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _varsSearchController,
                      onChanged: (val) => setSheetState(() {
                        _varsSearchQuery = val;
                      }),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            '\u041f\u043e\u0438\u0441\u043a \u043f\u043e \u0438\u043c\u0435\u043d\u0438 \u043f\u0435\u0440\u0435\u043c\u0435\u043d\u043d\u043e\u0439...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white38,
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              "\u041f\u0415\u0420\u0415\u041c\u0415\u041d\u041d\u042b\u0415",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...filteredVars.map(
                            (e) => ListTile(
                              dense: true,
                              title: Text(
                                e.key,
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                ),
                              ),
                              trailing: Text(
                                _formatVariableValue(e.value),
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: _isLargeValue(e.value)
                                  ? () => _showVariableDetails(
                                      context,
                                      e.key,
                                      e.value,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              "\u0422\u0410\u0411\u041b\u0418\u0426\u042b",
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...tables.entries.map(
                            (e) => ListTile(
                              leading: const Icon(
                                Icons.dataset,
                                color: Colors.orangeAccent,
                              ),
                              title: Text(
                                e.key,
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TableViewerScreen(
                                      tableName: e.key,
                                      table: e.value,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _editCurrentNode() {
    widget.onEditNode?.call();
  }

  @override
  Widget build(BuildContext context) {
    final screenState = ref.watch(gameScreenProvider(widget.questId));

    ref.watch(gameStateProvider);

    ref.listen(
      gameScreenProvider(widget.questId).select((s) => s.currentNode),
      (previous, next) {
        if (next != null && next.id != previous?.id) {
          final gameStateNotifier = ref.read(gameStateProvider.notifier);
          List<dynamic> currentHistory = [];
          final rawHistory = gameStateNotifier.getVariable('_SYS_HISTORY');
          if (rawHistory is List) {
            currentHistory = List.from(rawHistory);
          }
          currentHistory.add(next.id);
          gameStateNotifier.setVariable('_SYS_HISTORY', currentHistory);

          // --- БЕЗОПАСНОЕ ОБНОВЛЕНИЕ АУДИО ---
          _updateBackgrounds(next);
        }
      },
    );

    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: screenState.fontFamily,
            color: Colors.white,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: _buildAppBar(context, screenState),
            body: _buildBody(screenState),
          ),
        ),
      ),
    );
  }

  // --- ИСПРАВЛЕННАЯ ЛОГИКА АУДИО ---
  Future<void> _updateBackgrounds(SavedNode node) async {
    // Background updates are handled in GameScreenNotifier.
  }

  AppBar _buildAppBar(BuildContext context, GameScreenState screenState) {
    final quest = ref.watch(questProvider(widget.questId)).value;
    final bool hideTitle = quest?.hideNodeTitles ?? false;
    final gameStateNotifier = ref.read(gameStateProvider.notifier);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: hideTitle
          ? null
          : Text(
              _parseTextWithVariables(
                screenState.currentNode?.title ?? '...',
                gameStateNotifier,
              ),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                fontFamily: screenState.fontFamily,
              ),
            ),
      leading: const SizedBox.shrink(),
      actions: [
        if (widget.isTesting) ...[
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.amber),
            onPressed: _showVariablesDebug,
            tooltip: 'Переменные',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (widget.onEditNode != null) ...[
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blueAccent),
            onPressed: _editCurrentNode,
            tooltip: 'Редактировать ноду',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withOpacity(0.3),
            ),
          ),
          const SizedBox(width: 8),
        ],

        IconButton(
          icon: const Icon(Icons.save_alt_rounded),
          onPressed: _showSaveDialog,
          tooltip: 'Сохранить',
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withOpacity(0.3),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: _showLoadGame,
          tooltip: 'Загрузить',
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withOpacity(0.3),
          ),
        ),
        const SizedBox(width: 8),
        ...?widget.additionalAppBarActions,
      ],
      flexibleSpace: FutureBuilder<bool>(
        future: PlatformPerformance.instance.shouldDisableBlur(),
        initialData: false,
        builder: (context, snapshot) {
          final shouldDisableBlur = snapshot.data ?? false;

          if (shouldDisableBlur) {
            // Без blur - просто полупрозрачный фон
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            );
          }

          // С blur
          return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          );
        },
      ),
    );
  }

  String _parseTextWithVariables(String text, GameStateNotifier notifier) {
    return text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
      final expression = match.group(1);
      final value = ScriptExecutor.evaluateExpression(expression, notifier);
      return value?.toString() ?? match.group(0)!;
    });
  }

  Widget _buildBody(GameScreenState screenState) {
    final gameState = ref.watch(gameStateProvider);
    final quest = ref.watch(questProvider(widget.questId)).value;
    final transitionMode = _resolveTransitionMode(quest?.nodeTransitionMode);
    final scriptEngineMode = normalizeScriptEngineMode(quest?.scriptEngineMode);

    final currentNode = screenState.currentNode;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(screenState, gameState),
        SafeArea(
          child: Builder(
            builder: (context) {
              if (screenState.error != null) {
                return Center(
                  child: Text(
                    screenState.error!,
                    style: TextStyle(color: Colors.red[300]),
                  ),
                );
              }

              if (screenState.isLoading || screenState.currentNode == null) {
                return const _NodeLoadingView();
              }

              final itemsToDisplay = screenState.revealedItems;
              // Внутренний отступ между корневыми элементами ноды.
              // null → старое поведение (24 px), 0 → стык без зазоров.
              final double? nodeSpacing = screenState.currentNode?.itemSpacing;
              final double rootBottomPad = nodeSpacing ?? 24.0;
              final listView = ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                itemCount: itemsToDisplay.length,
                key: ValueKey('game_list_${screenState.presentationId}'),
                itemBuilder: (context, index) {
                  final item = itemsToDisplay[index];
                  // Если spacing задан явно — отступ только между детьми,
                  // чтобы 0 действительно давал стык без зазоров.
                  final double effectivePad;
                  if (nodeSpacing != null) {
                    effectivePad = index == itemsToDisplay.length - 1
                        ? 0.0
                        : rootBottomPad;
                  } else {
                    effectivePad = 24.0;
                  }
                  return RepaintBoundary(
                    child: ContentDisplayFactory.build(
                      item: item,
                      questId: widget.questId,
                      onInteract: _onItemInteract,
                      onInputSubmitted: _onInputSubmitted,
                      onComplete: ref
                          .read(gameScreenProvider(widget.questId).notifier)
                          .revealNextItem,
                      onTransition: (id) => ref
                          .read(gameScreenProvider(widget.questId).notifier)
                          .loadNode(id),
                      onNavigateToNode: (id) => ref
                          .read(gameScreenProvider(widget.questId).notifier)
                          .loadNode(id),
                      audioVolume:
                          gameState.variables['_internal_node_content_volume']
                              as double?,
                      bottomPadding: effectivePad,
                      fontFamily: screenState.fontFamily,
                      scriptEngineMode: scriptEngineMode,
                      imageRoundedCornersOverride:
                          screenState.currentNode?.imageRoundedCorners,
                    ),
                  );
                },
              );

              final content = _wrapNodeTransition(
                mode: transitionMode,
                presentationId: screenState.presentationId,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: listView,
                  ),
                ),
              );

              // Bottom padding when HUD is visible at bottom position
              final hudNode = currentNode;
              final hudActive =
                  hudNode != null &&
                  (hudNode.toolbarMode == 'enabled' ||
                      hudNode.toolbarMode == 'statsOnly' ||
                      hudNode.toolbarMode == 'locked') &&
                  hudNode.toolbarPosition == 'bottom';

              return Column(
                children: [
                  if (screenState.remainingSeconds != null &&
                      screenState.currentNode!.timerDuration != null)
                    _GameTimerWidget(
                      remainingSeconds: screenState.remainingSeconds!,
                      totalSeconds: screenState.currentNode!.timerDuration!,
                    ),
                  Expanded(child: content),
                  // Reserve space at the bottom for the HUD panel
                  if (hudActive) const SizedBox(height: 56),
                ],
              );
            },
          ),
        ),
        // ---- Static HUD panel (independent of node scroll) ----
        if (currentNode != null)
          GameHudPanel(
            node: currentNode,
            questId: widget.questId,
            isTesting: widget.isTesting,
          ),
        // ---- ContentItem-based HUD panels ('hud_panel' type) ----
        ...screenState.resolvedHudPanels.map(
          (item) => GameHudContentPanel(
            key: ValueKey('hud_panel_${item.id}'),
            item: item,
            questId: widget.questId,
          ),
        ),
      ],
    );
  }

  String _resolveTransitionMode(String? rawMode) {
    final mode = (rawMode ?? '').trim().toLowerCase();
    if (mode == 'fade' || mode == 'default') return 'fade';
    if (mode == 'page' || mode == 'flip') return 'page';
    return 'none';
  }

  Widget _wrapNodeTransition({
    required String mode,
    required String presentationId,
    required Widget child,
  }) {
    final keyedChild = KeyedSubtree(
      key: ValueKey('node_$presentationId'),
      child: child,
    );

    if (mode == 'none') return keyedChild;

    return AnimatedSwitcher(
      duration: Duration(milliseconds: mode == 'page' ? 820 : 280),
      reverseDuration: Duration(milliseconds: mode == 'page' ? 520 : 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        if (mode != 'page') {
          return currentChild ?? const SizedBox.shrink();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        if (mode == 'page') {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );
          final rotate = Tween<double>(begin: 0.28, end: 0.0).animate(curved);
          final slide = Tween<Offset>(
            begin: const Offset(0.16, 0.0),
            end: Offset.zero,
          ).animate(curved);
          final shadowOpacity = Tween<double>(
            begin: 0.25,
            end: 0.0,
          ).animate(curved);

          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.9, curve: Curves.easeOut),
            reverseCurve: const Interval(0.1, 1.0, curve: Curves.easeIn),
          );

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: AnimatedBuilder(
                animation: rotate,
                child: child,
                builder: (context, child) {
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(rotate.value);
                  return Transform(
                    transform: transform,
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              shadowOpacity.value,
                            ),
                            blurRadius: 24,
                            offset: const Offset(-12, 0),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          );
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      child: keyedChild,
    );
  }

  Widget _buildBackground(GameScreenState screenState, GameState gameState) {
    final blurValue =
        gameState.variables['_internal_background_blur'] as double? ?? 10.0;
    final questAsync = ref.watch(questProvider(widget.questId));
    final bool dimBackground = questAsync.value?.dimBackground ?? true;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (screenState.backgroundImagePath == null)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0a0a0f), Color(0xFF1a1a2e)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: ImageFiltered(
              key: ValueKey(screenState.backgroundImagePath),
              imageFilter: ImageFilter.blur(
                sigmaX: blurValue,
                sigmaY: blurValue,
              ),
              child: Image.file(
                File(screenState.backgroundImagePath!),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth:
                    MediaQuery.of(context).size.width.toInt() *
                    (MediaQuery.of(context).devicePixelRatio.toInt()),
                gaplessPlayback: true,
              ),
            ),
          ),
        if (dimBackground) Container(color: Colors.black.withOpacity(0.5)),
      ],
    );
  }

  /// Извлекает ContentItem-ы типа 'hud_panel' из контента ноды.
  /// Они рендерятся сразу при загрузке ноды, независимо от reveal-очереди.
  List<ContentItem> _extractHudPanelItems(Map<String, dynamic> nodeContent) {
    try {
      final rawItems = nodeContent['items'] as List<dynamic>? ?? const [];
      return rawItems
          .whereType<Map<String, dynamic>>()
          .where((raw) => raw['type'] == 'hud_panel')
          .map((raw) => ContentItem.fromJson(raw))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _showLoadGame() async {
    final slot = await Navigator.of(context).push<SaveSlot>(
      MaterialPageRoute(
        builder: (_) => LoadGameScreen(
          questId: widget.questId,
          isTesting: false,
        ),
      ),
    );

    if (slot != null && mounted) {
      ref.read(gameScreenProvider(widget.questId).notifier).loadInitialNode(
        slot.currentNodeId,
        saveSlot: slot,
      );
    }
  }

  Future<void> _showSaveDialog() async {
    if (!mounted) return;

    final nameController = TextEditingController(text: 'Сохранение');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Сохранить игру',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Имя сохранения'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text(
              'Сохранить',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final screenState = ref.read(gameScreenProvider(widget.questId));
      if (screenState.currentNode == null) return;

      final currentState = ref.read(gameStateProvider);

      final tablesJson = currentState.tables.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

      final newSlot = SaveSlot.createNew(
        questId: widget.questId,
        slotName: result,
        currentNodeId: screenState.currentNode!.id,
        variables: currentState.variables,
        tables: tablesJson,
      );

      await ref.read(saveGameServiceProvider).saveGame(newSlot);
      ref.invalidate(saveSlotsProvider(widget.questId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сохранено!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

class _NodeLoadingView extends StatelessWidget {
  const _NodeLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          SizedBox(height: 14),
          Text(
            'Загрузка сцены...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameTimerWidget extends StatelessWidget {
  final double remainingSeconds;
  final double totalSeconds;
  const _GameTimerWidget({
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  String _format(double s) {
    final d = Duration(milliseconds: (s * 1000).toInt());
    return "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  Color _getColor() {
    if (totalSeconds == 0) return Colors.green;
    final pct = remainingSeconds / totalSeconds;
    if (pct < 0.2) return Colors.red;
    if (pct < 0.5) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds > 0 ? remainingSeconds / totalSeconds : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GlassSurface(
        radius: 24,
        blurSigma: 5,
        tintColor: Colors.black.withOpacity(0.35),
        borderColor: Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 24),
              Text(
                _format(remainingSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(
                width: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(_getColor()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
