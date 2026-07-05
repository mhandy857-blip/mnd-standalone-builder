import 'dart:async';

import 'package:mnd_core/mnd_core.dart' hide ScriptCacheService;
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/services/script_cache_service.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef OnNavigateToNode = void Function(String nodeId);
typedef OnTransition = void Function(String nodeId);

/// Виджет всплывающего модального окна на базе AlertDialog
class ModalItemWidget extends ConsumerStatefulWidget {
  final ContentItem item;
  final String questId;
  final OnNavigateToNode? onNavigateToNode;
  final OnTransition? onTransition;
  final VoidCallback? onComplete;
  final String? fontFamily;
  final String scriptEngineMode;

  const ModalItemWidget({
    super.key,
    required this.item,
    required this.questId,
    this.onNavigateToNode,
    this.onTransition,
    this.onComplete,
    this.fontFamily,
    this.scriptEngineMode = 'new',
  });

  @override
  ConsumerState<ModalItemWidget> createState() => _ModalItemWidgetState();
}

class _ModalItemWidgetState extends ConsumerState<ModalItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _hasShown = false;
  Timer? _autoCloseTimer;
  Timer? _timerUpdateTimer; // Таймер для обновления UI обратного отсчёта
  final ValueNotifier<int> _remainingSecondsNotifier = ValueNotifier<int>(0);
  bool _showTimer = false;
  int _totalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );

    // Показываем модалку только один раз
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasShown) {
        _hasShown = true;
        _showModal();
      }
    });
  }

  Future<void> _showModal() async {
    final gameStateNotifier = ref.read(gameStateProvider.notifier);

    // Проверяем, является ли окно режимом автоматического закрытия
    final isAutoClose = widget.item.targetNodeId == '_CLOSE_MODAL';

    // Проверяем, нужно ли показывать таймер
    _showTimer = widget.item.scriptTriggers?['showTimer'] == 'true';

    // Парсим заголовок с поддержкой формул
    final title = _parseTextWithVariables(
      widget.item.buttonText ?? 'Уведомление',
      gameStateNotifier,
    );

    // Содержимое хранится в поле contentMarkdown и отображается всегда
    final content = _parseTextWithVariables(
      widget.item.contentMarkdown ?? '',
      gameStateNotifier,
    );

    if (!mounted) return;

    _animationController.forward();

    // Если режим автоматического закрытия, запускаем таймер
    if (isAutoClose) {
      final delaySeconds = int.tryParse(widget.item.text ?? '2') ?? 2;
      _totalSeconds = delaySeconds;
      _remainingSecondsNotifier.value = delaySeconds;

      // Запускаем таймер обновления UI
      if (_showTimer && mounted) {
        _timerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_remainingSecondsNotifier.value > 0) {
            _remainingSecondsNotifier.value--;
          } else {
            timer.cancel();
          }
        });
      }

      _autoCloseTimer = Timer(Duration(seconds: delaySeconds), () {
        if (mounted) {
          unawaited(_closeModalAndRunDefaultAction());
        }
      });
    }

    // Используем showDialog с transparent barrier
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      useSafeArea: true,
      builder: (dialogContext) => FadeTransition(
        opacity: _scaleAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AlertDialog(
            backgroundColor: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
            ),
            title: title.isNotEmpty
                ? Row(
                    children: [
                      if (widget.item.backgroundColor != null)
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: widget.item.backgroundColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      if (widget.item.backgroundColor != null)
                        const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: widget.fontFamily,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : null,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (content.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15,
                          height: 1.5,
                          fontFamily: widget.fontFamily,
                        ),
                      ),
                    ),
                  ),
                // Визуальный таймер
                if (isAutoClose && _showTimer)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _remainingSecondsNotifier,
                      builder: (context, remainingSeconds, _) {
                        final progress = _totalSeconds > 0
                            ? remainingSeconds / _totalSeconds
                            : 0.0;
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF00C853),
                              ),
                              minHeight: 8,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Закрытие через $remainingSeconds сек.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontFamily: widget.fontFamily,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
            actions: _buildModalActions(),
            actionsPadding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );

    // После закрытия диалога
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  List<Widget> _buildModalActions() {
    final buttons = <Widget>[];

    // Если есть кнопки modalButtons, используем их
    if (widget.item.modalButtons != null &&
        widget.item.modalButtons!.isNotEmpty) {
      for (final button in widget.item.modalButtons!) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: GlassSurface(
                radius: 12,
                blurSigma: 4,
                tintColor: button.isPrimary
                    ? const Color(0xFF00C853).withOpacity(0.15)
                    : Colors.white.withOpacity(0.08),
                borderColor: button.isPrimary
                    ? const Color(0xFF00C853).withOpacity(0.5)
                    : Colors.white.withOpacity(0.18),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleButtonTap(button),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                      child: Text(
                        _parseTextWithVariables(
                          button.text,
                          ref.read(gameStateProvider.notifier),
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: button.isPrimary
                              ? const Color(0xFF00C853)
                              : Colors.white,
                          fontSize: 16,
                          fontFamily: widget.fontFamily,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } else {
      // Старая логика с одной кнопкой
      final closeButtonText = _parseTextWithVariables(
        widget.item.placeholderText ?? 'Закрыть',
        ref.read(gameStateProvider.notifier),
      );

      buttons.add(
        SizedBox(
          width: double.infinity,
          child: GlassSurface(
            radius: 12,
            blurSigma: 4,
            tintColor: Colors.white.withOpacity(0.08),
            borderColor: Colors.white.withOpacity(0.18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => unawaited(_closeModalAndRunDefaultAction()),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  child: Text(
                    closeButtonText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return buttons;
  }

  Future<void> _handleButtonTap(ModalButtonConfig button) async {
    _closeModal();

    // Небольшая задержка перед выполнением действия
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    // Выполняем переход или скрипт
    if (button.targetNodeId != null && button.targetNodeId != '_CLOSE_MODAL') {
      widget.onTransition?.call(button.targetNodeId!);
    } else if (button.scriptAssetId != null) {
      await _executeScriptForButton(button.scriptAssetId!);
    }
  }

  Future<void> _executeScriptForButton(String scriptAssetId) async {
    try {
      final relativeScriptPath = await _resolveScriptPath(scriptAssetId);
      if (relativeScriptPath == null) {
        debugPrint('Скрипт не найден: $scriptAssetId');
        return;
      }
      final scriptPath = 'quests/${widget.questId}/$relativeScriptPath';
      final scriptData = await ScriptCacheService().getScript(scriptPath);
      if (scriptData == null) {
        debugPrint('Скрипт не найден: $scriptPath');
        return;
      }

      final notifier = ref.read(gameStateProvider.notifier);
      await ScriptExecutor.execute(
        scriptData,
        notifier,
        questId: widget.questId,
        eventType: EventType.onPress,
      );
    } catch (e) {
      debugPrint('Ошибка выполнения скрипта: $e');
    }
  }

  Future<void> _closeModalAndRunDefaultAction() async {
    final targetNodeId = widget.item.targetNodeId;
    final scriptAssetId = widget.item.scriptAssetId;
    _closeModal();

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    if (targetNodeId != null &&
        targetNodeId.isNotEmpty &&
        targetNodeId != '_CLOSE_MODAL') {
      widget.onTransition?.call(targetNodeId);
      return;
    }

    if (scriptAssetId != null && scriptAssetId.isNotEmpty) {
      await _executeScriptForButton(scriptAssetId);
    }
  }

  Future<String?> _resolveScriptPath(String scriptAssetId) async {
    final normalized = scriptAssetId.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return null;

    final direct = 'quests/${widget.questId}/$normalized';
    if (await FileStorage.exists(direct)) return normalized;

    if (!normalized.endsWith('.json') && !normalized.contains('/')) {
      final inScripts = 'scripts/$normalized.json';
      if (await FileStorage.exists('quests/${widget.questId}/$inScripts')) {
        return inScripts;
      }
      final inInternal = '_internal_scripts/$normalized.json';
      if (await FileStorage.exists('quests/${widget.questId}/$inInternal')) {
        return inInternal;
      }
    }
    return null;
  }

  void _closeModal() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _timerUpdateTimer?.cancel();
    _timerUpdateTimer = null;
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _parseTextWithVariables(String text, GameStateNotifier notifier) {
    return text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
      final expression = match.group(1);
      final value = ScriptExecutor.evaluateExpression(expression, notifier);
      return value?.toString() ?? '';
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _timerUpdateTimer?.cancel();
    _remainingSecondsNotifier.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Виджет ничего не рендерит, всё показывает через showDialog
    return const SizedBox.shrink();
  }
}
