import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:mnd_core/mnd_core.dart' hide ScriptCacheService;
import 'package:mnd_player/services/script_cache_service.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/utils/trigger_reference.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/providers/quest_provider.dart';
import 'package:mnd_player/widgets/items/game_container_widget.dart';
import 'package:mnd_player/widgets/items/modal_item_widget.dart';
import 'package:mnd_player/widgets/glass.dart';
import 'package:mnd_player/widgets/shared/markdown_color.dart';
import 'package:mnd_player/widgets/shared/module_asset_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

typedef OnInputSubmitted = void Function(String variableName, String value);
typedef OnTransition = void Function(String nodeId);
typedef OnNavigateToNode = void Function(String nodeId);
typedef OnItemInteract = void Function(ContentItem item);

class ContentDisplayFactory {
  static Widget build({
    required ContentItem item,
    required String questId,
    required OnItemInteract onInteract,
    required OnInputSubmitted onInputSubmitted,
    required VoidCallback onComplete,
    required OnTransition onTransition,
    required OnNavigateToNode onNavigateToNode,
    double? audioVolume,
    bool isInsideRow = false,
    bool parentIsInteractable = false,
    String textFit = 'auto',
    String rowTextAlign = 'center',
    double bottomPadding = 0.0,
    String? fontFamily,
    String scriptEngineMode = kScriptEngineModeNew,
    bool? imageRoundedCornersOverride,
  }) {
    double effectiveBottomPadding = bottomPadding;
    if (item.type == 'audio') {
      effectiveBottomPadding = 0.0;
    }

    if (item.isHidden) {
      if (item.type == 'timer' || item.type == 'delay') {
        return TimerItemWidget(item: item, onComplete: onComplete);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => onComplete());
      return const SizedBox.shrink();
    }
    if (item.type == 'script') {
      WidgetsBinding.instance.addPostFrameCallback((_) => onComplete());
      return const SizedBox.shrink();
    }
    // hud_panel рендерится отдельно поверх Stack в GameScreen —
    // в reveal-очереди просто пропускаем его как невидимый элемент.
    if (item.type == 'hud_panel') {
      WidgetsBinding.instance.addPostFrameCallback((_) => onComplete());
      return const SizedBox.shrink();
    }
    // Spacer: фиксированный отступ, не схлопывается. Высота/ширина в padding.
    // Внутри ряда трактуем как ширину, иначе — как высоту.
    if (item.type == 'spacer') {
      WidgetsBinding.instance.addPostFrameCallback((_) => onComplete());
      final size = (item.padding ?? 16.0).clamp(0.0, 999.0);
      return isInsideRow ? SizedBox(width: size) : SizedBox(height: size);
    }

    Widget content;

    switch (item.type) {
      case 'row':
      case 'column':
        content = GameContainerWidget(
          item: item,
          questId: questId,
          onInteract: onInteract,
          onInputSubmitted: onInputSubmitted,
          onComplete: onComplete,
          onTransition: onTransition,
          onNavigateToNode: onNavigateToNode,
          audioVolume: audioVolume,
          parentIsInteractable: parentIsInteractable,
          fontFamily: fontFamily,
          scriptEngineMode: scriptEngineMode,
          imageRoundedCornersOverride: imageRoundedCornersOverride,
        );
        break;

      case 'text':
        content = TextItemWidget(
          item: item,
          questId: questId,
          onNavigateToNode: onNavigateToNode,
          isInsideRow: isInsideRow,
          suppressInteractions: parentIsInteractable,
          textFit: textFit,
          rowTextAlign: rowTextAlign,
          fontFamily: fontFamily,
        );
        break;

      case 'button':
        content = ButtonItemWidget(
          item: item,
          questId: questId,
          onPressed: onInteract,
          fontFamily: fontFamily,
        );
        break;

      case 'image':
        content = ImageItemWidget(
          item: item,
          questId: questId,
          onInteract: onInteract,
          suppressInteractions:
              parentIsInteractable ||
              (item.scriptTriggers?.containsKey('onPress') ?? false) ||
              (item.targetNodeId != null && item.targetNodeId!.isNotEmpty),
          roundedCornersOverride: imageRoundedCornersOverride,
        );
        break;

      case 'audio':
        final combinedVolume = ((audioVolume ?? 1.0) * item.volume).clamp(
          0.0,
          1.0,
        );
        content = _AudioItemPlayer(
          questId: questId,
          item: item,
          onComplete: onComplete,
          initialVolume: combinedVolume,
        );
        break;

      case 'input':
        content = InputItemWidget(
          item: item,
          questId: questId,
          onSubmitted: onInputSubmitted,
          onInteract: onInteract,
          onComplete: onComplete,
          onNavigateToNode: onNavigateToNode,
          fontFamily: fontFamily,
        );
        break;

      case 'timer':
      case 'delay':
        content = TimerItemWidget(item: item, onComplete: onComplete);
        break;

      case 'wait_input':
        content = WaitInputItemWidget(
          item: item,
          onComplete: onComplete,
          fontFamily: fontFamily,
        );
        break;

      case 'modal':
        content = ModalItemWidget(
          item: item,
          questId: questId,
          onNavigateToNode: onNavigateToNode,
          onTransition: onTransition,
          onComplete: onComplete,
          fontFamily: fontFamily,
          scriptEngineMode: scriptEngineMode,
        );
        break;

      case 'chat':
        content = ChatItemWidget(
          item: item,
          questId: questId,
          fontFamily: fontFamily,
        );
        break;

      default:
        content = Text(
          'Unknown: ${item.type}',
          style: TextStyle(color: Colors.red, fontFamily: fontFamily),
        );
    }

    if (!parentIsInteractable) {
      if (item.type != 'button' &&
          item.type != 'input' &&
          item.type != 'wait_input' &&
          ((item.scriptTriggers?.containsKey('onPress') ?? false) ||
              (item.targetNodeId != null && item.targetNodeId!.isNotEmpty) ||
              (item.scriptAssetId != null && item.scriptAssetId!.isNotEmpty))) {
        content = InkWell(
          onTap: () => onInteract(item),
          borderRadius: BorderRadius.circular(12),
          child: content,
        );
      }
    }

    bool isSelfManaging =
        item.type == 'audio' ||
        item.type == 'timer' ||
        item.type == 'delay' ||
        item.type == 'row' ||
        item.type == 'column' ||
        item.type == 'input' ||
        item.type == 'wait_input' ||
        item.type == 'modal';

    if (isInsideRow) {
      return ConditionalContentWrapper(
        key: ValueKey(item.id),
        item: item,
        questId: questId,
        bottomPadding: effectiveBottomPadding,
        onComplete: () {},
        onTransition: onTransition,
        onNavigateToNode: onNavigateToNode,
        allowTargetMismatchFallback: scriptEngineMode == kScriptEngineModeNew,
        child: content,
      );
    }

    return ConditionalContentWrapper(
      key: ValueKey(item.id),
      item: item,
      questId: questId,
      bottomPadding: effectiveBottomPadding,
      onComplete: onComplete,
      onTransition: onTransition,
      onNavigateToNode: onNavigateToNode,
      allowTargetMismatchFallback: scriptEngineMode == kScriptEngineModeNew,
      child: isSelfManaging
          ? content
          : InstantItem(onCompleted: onComplete, child: content),
    );
  }
}

class InstantItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onCompleted;
  const InstantItem({super.key, required this.child, this.onCompleted});
  @override
  State<InstantItem> createState() => _InstantItemState();
}

class _InstantItemState extends State<InstantItem> {
  @override
  void initState() {
    super.initState();
    if (widget.onCompleted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted!();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ConditionalContentWrapper extends ConsumerStatefulWidget {
  final ContentItem item;
  final String questId;
  final Widget child;
  final VoidCallback onComplete;
  final Function(String) onTransition;
  final Function(String) onNavigateToNode;
  final double bottomPadding;
  final bool allowTargetMismatchFallback;

  const ConditionalContentWrapper({
    super.key,
    required this.item,
    required this.questId,
    required this.child,
    required this.onComplete,
    required this.onTransition,
    required this.onNavigateToNode,
    required this.allowTargetMismatchFallback,
    this.bottomPadding = 0.0,
  });

  @override
  ConsumerState<ConditionalContentWrapper> createState() =>
      _ConditionalContentWrapperState();
}

class _ConditionalContentWrapperState
    extends ConsumerState<ConditionalContentWrapper>
    with AutomaticKeepAliveClientMixin {
  Future<(bool, String?)>? _processingFuture;
  bool _isTransitionScheduled = false;
  Map<String, dynamic>? _cachedOnAppearScriptData;
  TriggerReference? _cachedOnAppearTriggerRef;
  bool _preserveVisibilityAfterInitialOnAppear = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.item.scriptTriggers?['onAppear'] != null) {
      _processingFuture = _processOnAppearScript();
    }
  }

  @override
  void didUpdateWidget(covariant ConditionalContentWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.item.scriptTriggers?['onAppear'];
    final newPath = widget.item.scriptTriggers?['onAppear'];
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.questId != widget.questId ||
        oldPath != newPath) {
      _isTransitionScheduled = false;
      _cachedOnAppearScriptData = null;
      _cachedOnAppearTriggerRef = null;
      _preserveVisibilityAfterInitialOnAppear = false;
      if (newPath != null) {
        _processingFuture = _processOnAppearScript();
      } else {
        _processingFuture = null;
      }
    }
  }

  Future<(bool, String?)> _processOnAppearScript() async {
    final triggerRef = TriggerReference.parse(
      widget.item.scriptTriggers!['onAppear']!,
    );
    final scriptPath = triggerRef.scriptPath;
    if (scriptPath.isEmpty) return (true, null);
    final targetEventType = triggerRef.isFunctionRef
        ? EventType.function
        : EventType.onContentAppear;
    try {
      final fullPath = 'quests/${widget.questId}/$scriptPath';

      final scriptData = await ScriptCacheService().getScript(fullPath);
      if (scriptData == null) {
        return (true, null);
      }

      _cachedOnAppearScriptData = scriptData;
      _cachedOnAppearTriggerRef = triggerRef;
      final gameStateNotifier = ref.read(gameStateProvider.notifier);

      final bool shouldAppear = ScriptExecutor.evaluateCondition(
        scriptData,
        gameStateNotifier,
        eventType: targetEventType,
        functionName: triggerRef.functionEntry,
        contentItemId: widget.item.id,
        allowTargetMismatchFallback: widget.allowTargetMismatchFallback,
      );
      _preserveVisibilityAfterInitialOnAppear = false;

      if (!shouldAppear) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete();
        });
        return (false, null);
      }

      final String? nextNodeId = await ScriptExecutor.execute(
        scriptData,
        gameStateNotifier,
        questId: widget.questId,
        eventType: targetEventType,
        functionName: triggerRef.functionEntry,
        contentItemId: widget.item.id,
        allowTargetMismatchFallback: widget.allowTargetMismatchFallback,
      );

      final bool stillVisibleAfterOnAppear = ScriptExecutor.evaluateCondition(
        scriptData,
        gameStateNotifier,
        eventType: targetEventType,
        functionName: triggerRef.functionEntry,
        contentItemId: widget.item.id,
        allowTargetMismatchFallback: widget.allowTargetMismatchFallback,
        allowStateMutation: false,
      );
      _preserveVisibilityAfterInitialOnAppear =
          shouldAppear && !stillVisibleAfterOnAppear;

      return (true, nextNodeId);
    } catch (e) {
      return (true, null);
    }
  }

  void _scheduleImmediateTransition(String nodeId) {
    if (_isTransitionScheduled) return;
    _isTransitionScheduled = true;
    Future.microtask(() {
      if (mounted) {
        widget.onTransition(nodeId);
      }
    });
  }

  Widget _wrapWithBottomPadding(Widget child) {
    if (widget.bottomPadding <= 0) return child;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.item.scriptTriggers?['onAppear'] == null) {
      return _wrapWithBottomPadding(widget.child);
    }

    return FutureBuilder<(bool, String?)>(
      future: _processingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final (shouldShow, transitionNodeId) = snapshot.data ?? (true, null);

        if (transitionNodeId != null) {
          _scheduleImmediateTransition(transitionNodeId);
          return const SizedBox.shrink();
        }

        var currentShouldShow = shouldShow;
        if (_cachedOnAppearScriptData != null) {
          // Re-check visibility when variables change without replaying side effects.
          ref.watch(gameStateProvider);
          final triggerRef =
              _cachedOnAppearTriggerRef ??
              const TriggerReference(scriptPath: '');
          final eventType = triggerRef.isFunctionRef
              ? EventType.function
              : EventType.onContentAppear;
          final recalculatedShouldShow = ScriptExecutor.evaluateCondition(
            _cachedOnAppearScriptData!,
            ref.read(gameStateProvider.notifier),
            eventType: eventType,
            functionName: triggerRef.functionEntry,
            contentItemId: widget.item.id,
            allowTargetMismatchFallback: widget.allowTargetMismatchFallback,
            allowStateMutation: false,
          );
          if (currentShouldShow &&
              _preserveVisibilityAfterInitialOnAppear &&
              !recalculatedShouldShow) {
            currentShouldShow = true;
          } else {
            currentShouldShow = recalculatedShouldShow;
          }
        }

        return currentShouldShow
            ? _wrapWithBottomPadding(widget.child)
            : const SizedBox.shrink();
      },
    );
  }
}

class TextItemWidget extends ConsumerWidget {
  final ContentItem item;
  final String questId;
  final OnNavigateToNode onNavigateToNode;
  final bool isInsideRow;
  final bool suppressInteractions;
  final String textFit;
  final String rowTextAlign;
  final String? fontFamily;

  const TextItemWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onNavigateToNode,
    this.isInsideRow = false,
    this.suppressInteractions = false,
    this.textFit = 'auto',
    this.rowTextAlign = 'center',
    this.fontFamily,
  });

  String _extractNodeId(Uri uri) {
    String candidate = '';
    if (uri.host.isNotEmpty && uri.path.isNotEmpty) {
      candidate = '${uri.host}${uri.path}';
    } else if (uri.host.isNotEmpty) {
      candidate = uri.host;
    } else {
      candidate = uri.path;
    }
    if (candidate.startsWith('/')) {
      candidate = candidate.substring(1);
    }
    return Uri.decodeComponent(candidate);
  }

  Future<void> _handleLinkTap(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme.toLowerCase() == 'node') {
      final nodeId = _extractNodeId(uri);
      if (nodeId.isNotEmpty) {
        onNavigateToNode(nodeId);
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _parseTextWithVariables(String text, GameStateNotifier notifier) {
    return text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
      final expression = match.group(1);
      final value = ScriptExecutor.evaluateExpression(expression, notifier);
      return value?.toString() ?? '';
    });
  }

  String _normalizeMarkdownListLayout(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final out = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final bulletOnly = RegExp(r'^\s*[•\-*+]\s*$').hasMatch(line);
      if (bulletOnly) {
        int next = i + 1;
        while (next < lines.length && lines[next].trim().isEmpty) {
          next++;
        }
        if (next < lines.length) {
          final nextLine = lines[next].trim();
          final nextIsList = RegExp(
            r'^\s*(?:[•\-*+]|\d+\.)\s+',
          ).hasMatch(lines[next]);
          if (!nextIsList && nextLine.isNotEmpty) {
            out.add('- $nextLine');
            i = next;
          }
        }
        continue;
      }

      final bulletText = RegExp(r'^\s*•\s+(.+)$').firstMatch(line);
      if (bulletText != null) {
        out.add('- ${bulletText.group(1)!.trimRight()}');
      } else {
        out.add(line);
      }
    }

    return out.join('\n');
  }

  bool _looksLikeAsciiArt(String sourceTemplate, String renderedText) {
    final normalized = renderedText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 3) return false;

    final hasTemplateVariables = RegExp(r'\{[^}]+\}').hasMatch(sourceTemplate);
    final hasBacktickFence = renderedText.contains('```');
    int asciiLikeLines = 0;

    for (final line in lines) {
      final symbolCount = RegExp(
        r'''[\\/\[\]()<>{}|`~_=.\-'"^:;,]''',
      ).allMatches(line).length;
      final letterCount = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(line).length;
      if (symbolCount >= 4 && symbolCount > letterCount) {
        asciiLikeLines++;
      }
    }

    final mostlyAscii = asciiLikeLines >= (lines.length * 0.6).ceil();
    return hasBacktickFence || (hasTemplateVariables && mostlyAscii);
  }

  TextSpan _parseSimpleMarkdown(String text) {
    final RegExp colorExp = RegExp(
      r'\[color=(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})\](.*?)\[\/color\]',
      dotAll: true,
    );
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)');
    int start = 0;

    List<Match> colorMatches = colorExp.allMatches(text).toList();

    if (colorMatches.isNotEmpty) {
      int colorStart = 0;
      for (final colorMatch in colorMatches) {
        if (colorMatch.start > colorStart) {
          String segment = text.substring(colorStart, colorMatch.start);
          spans.addAll(_parseMarkdownSegment(segment, fontFamily));
        }
        String colorStr = colorMatch.group(1)!;
        String content = colorMatch.group(2)!;
        Color color = _parseColor(colorStr);
        spans.addAll(_parseMarkdownSegment(content, fontFamily, color: color));
        colorStart = colorMatch.end;
      }
      if (colorStart < text.length) {
        String segment = text.substring(colorStart);
        spans.addAll(_parseMarkdownSegment(segment, fontFamily));
      }
    } else {
      for (final match in exp.allMatches(text)) {
        if (match.start > start) {
          spans.add(
            TextSpan(
              text: text.substring(start, match.start),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: fontFamily,
              ),
            ),
          );
        }
        if (match.group(1) != null) {
          spans.add(
            TextSpan(
              text: match.group(2),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontFamily: fontFamily,
              ),
            ),
          );
        } else if (match.group(3) != null) {
          spans.add(
            TextSpan(
              text: match.group(4),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontFamily: fontFamily,
              ),
            ),
          );
        }
        start = match.end;
      }
      if (start < text.length) {
        spans.add(
          TextSpan(
            text: text.substring(start),
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: fontFamily,
            ),
          ),
        );
      }
      if (spans.isEmpty && text.isNotEmpty) {
        return TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: fontFamily,
          ),
        );
      }
    }
    return TextSpan(children: spans);
  }

  List<TextSpan> _parseMarkdownSegment(
    String segment,
    String? fontFamily, {
    Color? color,
  }) {
    List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)');
    int start = 0;
    Color defaultColor = color ?? Colors.white;

    for (final match in exp.allMatches(segment)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: segment.substring(start, match.start),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontFamily: fontFamily,
            ),
          ),
        );
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFamily: fontFamily,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(4),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              fontFamily: fontFamily,
            ),
          ),
        );
      }
      start = match.end;
    }
    if (start < segment.length) {
      spans.add(
        TextSpan(
          text: segment.substring(start),
          style: TextStyle(
            color: defaultColor,
            fontSize: 16,
            fontFamily: fontFamily,
          ),
        ),
      );
    }
    if (spans.isEmpty && segment.isNotEmpty) {
      return [
        TextSpan(
          text: segment,
          style: TextStyle(
            color: defaultColor,
            fontSize: 16,
            fontFamily: fontFamily,
          ),
        ),
      ];
    }
    return spans;
  }

  Color _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      String hex = colorStr.substring(1);
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceTemplate = item.text ?? '';
    final gameStateNotifier = ref.watch(gameStateProvider.notifier);
    final parsedText = _normalizeMarkdownListLayout(
      _parseTextWithVariables(sourceTemplate, gameStateNotifier),
    );
    final backgroundColor = item.backgroundColor;
    String effectiveFit = textFit;

    if (effectiveFit == 'auto') {
      if (isInsideRow) {
        final questAsync = ref.watch(questProvider(questId));
        effectiveFit = questAsync.value?.defaultTextFit ?? 'scale';
      } else {
        effectiveFit = 'wrap';
      }
    }

    final bool hasForcedMultiline =
        parsedText.contains('\n') ||
        RegExp(r'^\s*[-*+]\s+', multiLine: true).hasMatch(parsedText);
    if (effectiveFit == 'scale' && hasForcedMultiline) {
      effectiveFit = 'wrap';
    }

    final bool hasMarkdownList = RegExp(
      r'^\s*(?:[-*+]|•|\d+\.)\s+',
      multiLine: true,
    ).hasMatch(parsedText);

    TextAlign textAlign;
    if (isInsideRow) {
      if (hasMarkdownList) {
        textAlign = TextAlign.start;
      } else {
        switch (rowTextAlign) {
          case 'start':
            textAlign = TextAlign.start;
            break;
          case 'end':
            textAlign = TextAlign.end;
            break;
          default:
            textAlign = TextAlign.center;
        }
      }
    } else {
      textAlign = DefaultTextStyle.of(context).textAlign ?? TextAlign.start;
    }

    if (_looksLikeAsciiArt(sourceTemplate, parsedText)) {
      final resolvedBackground = backgroundColor ?? Colors.black;
      Widget textContent = Container(
        width: isInsideRow ? null : double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: resolvedBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Align(
          alignment: textAlign == TextAlign.start
              ? Alignment.centerLeft
              : (textAlign == TextAlign.end
                    ? Alignment.centerRight
                    : Alignment.center),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              parsedText,
              textAlign: textAlign,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.2,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );

      if (suppressInteractions) {
        return IgnorePointer(child: textContent);
      }
      return textContent;
    }

    if (effectiveFit == 'scale') {
      return Container(
        width: double.infinity,
        padding: backgroundColor != null
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: textAlign == TextAlign.start
              ? Alignment.centerLeft
              : (textAlign == TextAlign.end
                    ? Alignment.centerRight
                    : Alignment.center),
          child: RichText(
            text: _parseSimpleMarkdown(parsedText),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: textAlign,
          ),
        ),
      );
    }

    final baseMarkdownTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 16.0,
      height: 1.35,
      fontFamily: fontFamily,
    );

    final config = MarkdownConfig(
      configs: [
        PConfig(textStyle: baseMarkdownTextStyle),
        const ListConfig(marginLeft: 20.0, marginBottom: 0.0),
        H1Config(
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: fontFamily,
          ),
        ),
        H2Config(
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: fontFamily,
          ),
        ),
        H3Config(
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: fontFamily,
          ),
        ),
        LinkConfig(
          style: TextStyle(
            color: Colors.cyanAccent,
            decoration: TextDecoration.underline,
            fontFamily: fontFamily,
          ),
          onTap: (url) => _handleLinkTap(url),
        ),
        const BlockquoteConfig(
          textColor: Colors.white70,
          sideColor: Colors.white70,
        ),
        CodeConfig(
          style: TextStyle(
            fontFamily: 'monospace',
            color: Colors.white,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],
    );

    CrossAxisAlignment crossAlign = CrossAxisAlignment.start;
    if (textAlign == TextAlign.center) {
      crossAlign = CrossAxisAlignment.center;
    } else if (textAlign == TextAlign.end) {
      crossAlign = CrossAxisAlignment.end;
    }

    final markdownGenerator = createColorMarkdownGenerator(
      linesMargin: const EdgeInsets.symmetric(vertical: 2),
    );
    final markdownText = preserveMarkdownHardLineBreaks(parsedText);

    Widget textContent = Container(
      width: isInsideRow ? null : double.infinity,
      padding: backgroundColor != null
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        textAlign: textAlign,
        style: baseMarkdownTextStyle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAlign,
          children: markdownGenerator.buildWidgets(
            markdownText,
            config: config,
          ),
        ),
      ),
    );

    if (suppressInteractions) {
      return IgnorePointer(child: textContent);
    }
    return textContent;
  }
}

class ButtonItemWidget extends ConsumerWidget {
  final ContentItem item;
  final String questId;
  final Function(ContentItem) onPressed;
  final String? fontFamily;

  const ButtonItemWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onPressed,
    this.fontFamily,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questAsync = ref.watch(questProvider(questId));

    bool useWrapText = item.wrapTextOverride ?? item.wrapText;
    if (item.wrapTextOverride == null &&
        questAsync.hasValue &&
        questAsync.requireValue != null) {
      useWrapText = questAsync.requireValue!.wrapButtonText;
    }

    return GlassButton(
      onPressed: () => onPressed(item),
      text: item.text ?? 'Кнопка',
      wrapText: useWrapText,
      fontFamily: fontFamily,
      styleConfig: item.buttonStyle,
      questId: questId,
    );
  }
}

class GlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;
  final bool wrapText;
  final String? fontFamily;
  final ButtonStyleConfig? styleConfig;
  final String? questId;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.wrapText = true,
    this.fontFamily,
    this.styleConfig,
    this.questId,
  });

  TextSpan _parseSimpleMarkdown(String value) {
    final RegExp colorExp = RegExp(
      r'\[color=(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})\](.*?)\[\/color\]',
      dotAll: true,
    );
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)');
    int start = 0;

    final colorMatches = colorExp.allMatches(value).toList();

    if (colorMatches.isNotEmpty) {
      int colorStart = 0;
      for (final colorMatch in colorMatches) {
        if (colorMatch.start > colorStart) {
          final segment = value.substring(colorStart, colorMatch.start);
          spans.addAll(_parseMarkdownSegment(segment, fontFamily));
        }
        final colorStr = colorMatch.group(1)!;
        final content = colorMatch.group(2)!;
        final color = _parseColor(colorStr);
        spans.addAll(_parseMarkdownSegment(content, fontFamily, color: color));
        colorStart = colorMatch.end;
      }
      if (colorStart < value.length) {
        final segment = value.substring(colorStart);
        spans.addAll(_parseMarkdownSegment(segment, fontFamily));
      }
    } else {
      for (final match in exp.allMatches(value)) {
        if (match.start > start) {
          spans.add(
            TextSpan(
              text: value.substring(start, match.start),
              style: TextStyle(fontSize: 16, fontFamily: fontFamily),
            ),
          );
        }
        if (match.group(1) != null) {
          spans.add(
            TextSpan(
              text: match.group(2),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontFamily: fontFamily,
              ),
            ),
          );
        } else if (match.group(3) != null) {
          spans.add(
            TextSpan(
              text: match.group(4),
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontFamily: fontFamily,
              ),
            ),
          );
        }
        start = match.end;
      }
      if (start < value.length) {
        spans.add(
          TextSpan(
            text: value.substring(start),
            style: TextStyle(fontSize: 16, fontFamily: fontFamily),
          ),
        );
      }
      if (spans.isEmpty && value.isNotEmpty) {
        return TextSpan(
          text: value,
          style: TextStyle(fontSize: 16, fontFamily: fontFamily),
        );
      }
    }
    return TextSpan(children: spans);
  }

  List<TextSpan> _parseMarkdownSegment(
    String segment,
    String? fontFamily, {
    Color? color,
  }) {
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)');
    int start = 0;
    final defaultColor = color ?? Colors.white;

    for (final match in exp.allMatches(segment)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: segment.substring(start, match.start),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontFamily: fontFamily,
            ),
          ),
        );
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFamily: fontFamily,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(4),
            style: TextStyle(
              color: defaultColor,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              fontFamily: fontFamily,
            ),
          ),
        );
      }
      start = match.end;
    }
    if (start < segment.length) {
      spans.add(
        TextSpan(
          text: segment.substring(start),
          style: TextStyle(
            color: defaultColor,
            fontSize: 16,
            fontFamily: fontFamily,
          ),
        ),
      );
    }
    if (spans.isEmpty && segment.isNotEmpty) {
      return [
        TextSpan(
          text: segment,
          style: TextStyle(
            color: defaultColor,
            fontSize: 16,
            fontFamily: fontFamily,
          ),
        ),
      ];
    }
    return spans;
  }

  Color _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      String hex = colorStr.substring(1);
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.white;
  }

  TextSpan _withTextColor(TextSpan span, Color color) {
    final children = span.children?.map<InlineSpan>((child) {
      if (child is TextSpan) {
        return _withTextColor(child, color);
      }
      return child;
    }).toList();
    final existingColor = span.style?.color;
    return TextSpan(
      text: span.text,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
      style: (span.style ?? const TextStyle()).copyWith(
        color: existingColor ?? color,
      ),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final gameStateNotifier = ref.watch(gameStateProvider.notifier);
        final parsedText = text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (
          match,
        ) {
          final expression = match.group(1);
          final value = ScriptExecutor.evaluateExpression(
            expression,
            gameStateNotifier,
          );
          return value?.toString() ?? '';
        });

        if (styleConfig != null) {
          final config = styleConfig!;
          final double module = config.moduleSize.clamp(6.0, 32.0);
          final int centerModules = config.autoCenterByText
              ? (config.centerModules + (parsedText.length / 14).ceil()).clamp(
                  config.centerModules,
                  30,
                )
              : config.centerModules.clamp(4, 30);
          final bool hasModuleAssets =
              config.hasModuleAssets &&
              questId != null &&
              questId!.trim().isNotEmpty;
          final double horizontalPadding = hasModuleAssets
              ? (module * 0.6).clamp(10.0, 80.0)
              : (config.horizontalModules.clamp(2, 20) * module * 0.38).clamp(
                  10.0,
                  80.0,
                );
          final double verticalPadding = hasModuleAssets
              ? (module * 0.4).clamp(8.0, 34.0)
              : (config.verticalModules.clamp(2, 10) * module * 0.20).clamp(
                  8.0,
                  34.0,
                );
          final double minHeight =
              (config.verticalModules.clamp(2, 10) * module * 1.4).clamp(
                40.0,
                120.0,
              );
          final double minWidth = (centerModules * module * 1.15).clamp(
            120.0,
            720.0,
          );
          int assetWidthModules = config.horizontalModules.clamp(2, 40);
          int assetHeightModules = config.verticalModules.clamp(2, 20);
          if (hasModuleAssets && config.autoCenterByText) {
            final maxTotalWidth = (MediaQuery.of(context).size.width * 0.9)
                .clamp(240.0, 900.0);
            final maxCenterModulesRaw = ((maxTotalWidth / module).floor() - 2)
                .clamp(1, 40);
            final minCenterModules = config.horizontalModules.clamp(2, 40);
            final maxCenterModules = maxCenterModulesRaw < minCenterModules
                ? minCenterModules
                : maxCenterModulesRaw;
            final textSpan = _parseSimpleMarkdown(parsedText);
            final painter = TextPainter(
              text: textSpan,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              maxLines: wrapText ? null : 1,
            );
            final maxTextWidth = wrapText
                ? (maxTotalWidth - 2 * horizontalPadding).clamp(
                    40.0,
                    maxTotalWidth,
                  )
                : double.infinity;
            painter.layout(maxWidth: maxTextWidth);
            final contentWidth = painter.width + (2 * horizontalPadding);
            final contentHeight = painter.height + (2 * verticalPadding);
            assetWidthModules = (contentWidth / module).ceil().clamp(
              minCenterModules,
              maxCenterModules,
            );
            final minHeightModulesBase = config.verticalModules.clamp(2, 20);
            final lineCount = painter.computeLineMetrics().length;
            final rawHeightModules = (contentHeight / module).ceil().clamp(
              minHeightModulesBase,
              20,
            );
            if (lineCount <= 1) {
              final minHeightModules = math.min(
                minHeightModulesBase,
                assetWidthModules,
              );
              final maxHeightModules = assetWidthModules;
              assetHeightModules = rawHeightModules.clamp(
                minHeightModules,
                maxHeightModules,
              );
            } else {
              assetHeightModules = rawHeightModules;
            }
          }
          final double moduleFrameHeight =
              (assetHeightModules * module) + (module * 2);
          final double moduleFrameWidth =
              (assetWidthModules * module) + (module * 2);
          final double radius = (module * 1.1).clamp(10.0, 40.0);
          final double borderWidth = (module * 0.12).clamp(1.2, 3.5);
          final content = wrapText
              ? RichText(
                  text: _withTextColor(
                    _parseSimpleMarkdown(parsedText),
                    config.textColor,
                  ),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: null,
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RichText(
                    text: _withTextColor(
                      _parseSimpleMarkdown(parsedText),
                      config.textColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                );

          if (hasModuleAssets) {
            return LayoutBuilder(
              builder: (context, box) {
                final maxTotalWidth = box.maxWidth.isFinite
                    ? box.maxWidth
                    : (MediaQuery.of(context).size.width * 0.9).clamp(
                        240.0,
                        900.0,
                      );
                final maxPossibleModules =
                    ((maxTotalWidth / module).floor() - 2).clamp(1, 40);
                final configuredMinModules = config.horizontalModules.clamp(
                  2,
                  40,
                );
                final minCenterModules =
                    maxPossibleModules < configuredMinModules
                    ? maxPossibleModules
                    : configuredMinModules;
                final maxCenterModules = maxPossibleModules;

                int widthModules = minCenterModules;
                int heightModules = config.verticalModules.clamp(2, 20);

                if (config.autoCenterByText) {
                  final textSpan = _parseSimpleMarkdown(parsedText);
                  final painter = TextPainter(
                    text: textSpan,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    maxLines: wrapText ? null : 1,
                  );
                  final maxTextWidth = wrapText
                      ? (maxTotalWidth - 2 * horizontalPadding).clamp(
                          40.0,
                          maxTotalWidth,
                        )
                      : double.infinity;
                  painter.layout(maxWidth: maxTextWidth);
                  final contentWidth = painter.width + (2 * horizontalPadding);
                  final contentHeight = painter.height + (2 * verticalPadding);
                  widthModules = (contentWidth / module).ceil().clamp(
                    minCenterModules,
                    maxCenterModules,
                  );
                  final lineCount = painter.computeLineMetrics().length;
                  final rawHeightModules = (contentHeight / module)
                      .ceil()
                      .clamp(1, 20);
                  if (lineCount <= 1) {
                    heightModules = rawHeightModules.clamp(1, widthModules);
                  } else {
                    heightModules = rawHeightModules;
                  }
                }

                final frameWidth = (widthModules * module) + (module * 2);
                final frameHeight = (heightModules * module) + (module * 2);
                final hasBoxW = box.maxWidth.isFinite;
                final hasBoxH = box.maxHeight.isFinite;
                final scaleW = hasBoxW ? (box.maxWidth / frameWidth) : 1.0;
                final scaleH = hasBoxH ? (box.maxHeight / frameHeight) : 1.0;
                final scale = math.min(
                  scaleW.isFinite ? scaleW : 1.0,
                  scaleH.isFinite ? scaleH : 1.0,
                );
                final needsScaleDown = scale < 1.0;
                if (kDebugMode) {
                  final boxW = box.maxWidth.isFinite
                      ? box.maxWidth.toStringAsFixed(1)
                      : 'inf';
                  debugPrint(
                    '[ModuleButton] textLen=${parsedText.length} '
                    'module=${module.toStringAsFixed(1)} '
                    'hModules=${config.horizontalModules} vModules=${config.verticalModules} '
                    'auto=${config.autoCenterByText} '
                    'widthModules=$widthModules heightModules=$heightModules '
                    'frame=${frameWidth.toStringAsFixed(1)}x${frameHeight.toStringAsFixed(1)} '
                    'maxW=${maxTotalWidth.toStringAsFixed(1)} boxW=$boxW '
                    'maxPossible=$maxPossibleModules minCfg=$configuredMinModules '
                    'pad=${horizontalPadding.toStringAsFixed(1)}x${verticalPadding.toStringAsFixed(1)} '
                    'scale=${scale.toStringAsFixed(2)}',
                  );
                  debugPrint(
                    '[ModuleButton] assets corner=${config.cornerAsset} '
                    'h=${config.hAsset} v=${config.vAsset} c=${config.centerAsset}',
                  );
                }
                final frame = _ModuleAssetButtonFrame(
                  questId: questId!,
                  style: config,
                  onTap: onPressed,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  constraints: BoxConstraints.tightFor(
                    width: frameWidth,
                    height: frameHeight,
                  ),
                  child: content,
                );
                if (!needsScaleDown) return frame;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: frameWidth,
                    height: frameHeight,
                    child: frame,
                  ),
                );
              },
            );
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              color: config.fillColor.withOpacity(0.92),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: config.borderColor, width: borderWidth),
              boxShadow: [
                BoxShadow(
                  color: config.borderColor.withOpacity(0.2),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(radius),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: minHeight,
                    minWidth: minWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          );
        }

        return GlassSurface(
          radius: 16,
          blurSigma: 6,
          tintColor: Colors.white.withOpacity(0.08),
          borderColor: Colors.white.withOpacity(0.18),
          shadows: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: wrapText
                    ? RichText(
                        text: _parseSimpleMarkdown(parsedText),
                        textAlign: TextAlign.center,
                        softWrap: true,
                        maxLines: null,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RichText(
                          text: _parseSimpleMarkdown(parsedText),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModuleAssetButtonFrame extends StatelessWidget {
  final String questId;
  final ButtonStyleConfig style;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final BoxConstraints constraints;
  final Widget child;

  const _ModuleAssetButtonFrame({
    required this.questId,
    required this.style,
    required this.onTap,
    required this.padding,
    required this.constraints,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final module = style.moduleSize.clamp(6.0, 32.0);
    return ModuleAssetFrame(
      questId: questId,
      style: style,
      module: module,
      onTap: onTap,
      padding: padding,
      constraints: constraints,
      child: child,
    );
  }
}

class ImageItemWidget extends StatelessWidget {
  final ContentItem item;
  final String questId;
  final Function(ContentItem) onInteract;
  final bool suppressInteractions;

  /// Переопределение скругления, приходящее от родительского ряда
  /// через `row.childImageRoundedCorners`. `null` — использовать
  /// дефолт (скруглять).
  final bool? roundedCornersOverride;

  const ImageItemWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onInteract,
    this.suppressInteractions = false,
    this.roundedCornersOverride,
  });

  void _openFullScreen(BuildContext context, File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: const BackButton(color: Colors.white),
          ),
          body: PhotoView(
            imageProvider: FileImage(imageFile),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2.5,
            heroAttributes: PhotoViewHeroAttributes(tag: item.id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: item.resourcePath != null
          ? FileStorage.getFilePath(
              'quests/$questId/${item.resourcePath!}',
            ).then((path) async {
              if (path.isEmpty) return null;
              final file = File(path);
              if (await file.exists()) return file;
              return null;
            })
          : Future.value(null),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          // По умолчанию углы скругляем (как было). Ряд может отключить
          // это через `childImageRoundedCorners = false`.
          final bool rounded = roundedCornersOverride ?? true;
          final Widget rawImage = Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
          );
          final imageWidget = Hero(
            tag: item.id,
            child: rounded
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: rawImage,
                  )
                : rawImage,
          );

          if (suppressInteractions) return imageWidget;

          return GestureDetector(
            onTap: () => _openFullScreen(context, file),
            child: imageWidget,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _AudioItemPlayer extends StatefulWidget {
  final String questId;
  final ContentItem item;
  final double? initialVolume;
  final VoidCallback onComplete;

  const _AudioItemPlayer({
    required this.questId,
    required this.item,
    required this.onComplete,
    this.initialVolume,
  });

  @override
  State<_AudioItemPlayer> createState() => _AudioItemPlayerState();
}

class _AudioItemPlayerState extends State<_AudioItemPlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSub;

  void _log(String message) {
    debugPrint('[QuestAudio][content][${widget.item.id}] $message');
  }

  @override
  void initState() {
    super.initState();
    _play();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onComplete());
  }

  Future<void> _play() async {
    if (widget.item.resourcePath == null) return;
    try {
      final path = await FileStorage.getFilePath(
        'quests/${widget.questId}/${widget.item.resourcePath}',
      );
      if (!await File(path).exists()) {
        _log('missing file: $path');
        return;
      }

      if (!mounted) return;
      final volume = (widget.initialVolume ?? 1.0).clamp(0.0, 1.0);
      _player = AudioPlayer();
      _playerStateSub = _player!.onPlayerStateChanged.listen((state) {
        _log('state=$state');
      });

      // lowLatency on Android maps to SoundPool and can truncate long tracks.
      // Content audio in quests may include full-length ambiance/music, so use mediaPlayer.
      if (Platform.isAndroid) {
        await _player!.setPlayerMode(PlayerMode.mediaPlayer);
      }
      if (Platform.isAndroid || Platform.isIOS) {
        await _player!.setAudioContext(
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
      await _player!.setVolume(volume);
      _log('play start path=$path volume=${volume.toStringAsFixed(3)}');
      await _player!.play(DeviceFileSource(path));
    } catch (e) {
      _log('play error: $e');
    }
  }

  @override
  void dispose() {
    _log('dispose');
    _playerStateSub?.cancel();
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class TimerItemWidget extends StatefulWidget {
  final ContentItem item;
  final VoidCallback onComplete;
  const TimerItemWidget({
    super.key,
    required this.item,
    required this.onComplete,
  });
  @override
  State<TimerItemWidget> createState() => _TimerItemWidgetState();
}

class _TimerItemWidgetState extends State<TimerItemWidget>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _controller;
  bool _isCompleted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final textVal = (widget.item.text ?? '').trim().replaceAll(',', '.');
    double seconds = double.tryParse(textVal) ?? 1.0;
    if (seconds < 0.1) seconds = 0.1;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (seconds * 1000).toInt()),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_isCompleted) {
        _isCompleted = true;
        if (mounted) widget.onComplete();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.item.isHidden || _isCompleted) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return LinearProgressIndicator(
            value: _controller.value,
            backgroundColor: Colors.white10,
            color: Colors.white30,
          );
        },
      ),
    );
  }
}

class WaitInputItemWidget extends StatefulWidget {
  final ContentItem item;
  final VoidCallback onComplete;
  final String? fontFamily;

  const WaitInputItemWidget({
    super.key,
    required this.item,
    required this.onComplete,
    this.fontFamily,
  });
  @override
  State<WaitInputItemWidget> createState() => _WaitInputItemWidgetState();
}

class _WaitInputItemWidgetState extends State<WaitInputItemWidget>
    with AutomaticKeepAliveClientMixin {
  bool _isCompleted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isCompleted) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, child) {
        final gameStateNotifier = ref.watch(gameStateProvider.notifier);
        final rawText = widget.item.text ?? "Нажмите для продолжения";
        final parsedText = rawText.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (
          m,
        ) {
          final val = ScriptExecutor.evaluateExpression(
            m.group(1),
            gameStateNotifier,
          );
          return val?.toString() ?? '';
        });

        return GestureDetector(
          onTap: () {
            setState(() => _isCompleted = true);
            widget.onComplete();
          },
          child: Container(
            height: 60,
            alignment: Alignment.center,
            child: Text(
              parsedText,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFamily: widget.fontFamily,
              ),
            ),
          ),
        );
      },
    );
  }
}

class InputItemWidget extends StatefulWidget {
  final ContentItem item;
  final String questId;
  final Function(String, String) onSubmitted;
  final Function(ContentItem) onInteract;
  final VoidCallback onComplete;
  final OnNavigateToNode onNavigateToNode;
  final String? fontFamily;

  const InputItemWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onSubmitted,
    required this.onInteract,
    required this.onComplete,
    required this.onNavigateToNode,
    this.fontFamily,
  });
  @override
  State<InputItemWidget> createState() => _InputItemWidgetState();
}

class _InputItemWidgetState extends State<InputItemWidget>
    with AutomaticKeepAliveClientMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showError = false;
  String? _submittedValue;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submittedValue != null) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _showError = true);
      return;
    }

    if (widget.item.variableName != null) {
      widget.onSubmitted(widget.item.variableName!, text);
    }

    setState(() => _submittedValue = text);

    widget.onInteract(widget.item);

    bool hasAction =
        widget.item.targetNodeId != null ||
        (widget.item.scriptTriggers?.containsKey('onSubmit') ?? false);

    if (!hasAction) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_submittedValue != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.item.text != null)
              Consumer(
                builder: (context, ref, _) {
                  final gameStateNotifier = ref.watch(
                    gameStateProvider.notifier,
                  );
                  final parsed = widget.item.text!.replaceAllMapped(
                    RegExp(r'\{([^}]+)\}'),
                    (m) {
                      final val = ScriptExecutor.evaluateExpression(
                        m.group(1),
                        gameStateNotifier,
                      );
                      return val?.toString() ?? '';
                    },
                  );
                  return Text(
                    parsed,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: widget.fontFamily,
                    ),
                  );
                },
              ),
            const SizedBox(height: 4),
            Text(
              _submittedValue!,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: widget.fontFamily,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.item.text != null && widget.item.text!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextItemWidget(
              item: widget.item,
              questId: "",
              onNavigateToNode: widget.onNavigateToNode,
              fontFamily: widget.fontFamily,
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _showError ? Colors.redAccent : Colors.white24,
            ),
          ),
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: widget.fontFamily,
            ),
            decoration: InputDecoration(
              hintText: widget.item.placeholderText ?? '...',
              hintStyle: const TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_showError) setState(() => _showError = false);
            },
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Consumer(
            builder: (context, ref, child) {
              bool useWrapText =
                  widget.item.wrapTextOverride ?? widget.item.wrapText;
              if (widget.item.wrapTextOverride == null &&
                  widget.questId.isNotEmpty) {
                final questAsync = ref.watch(questProvider(widget.questId));
                if (questAsync.hasValue && questAsync.requireValue != null) {
                  useWrapText = questAsync.requireValue!.wrapButtonText;
                }
              }

              return GlassButton(
                onPressed: _submit,
                text: widget.item.buttonText ?? 'OK',
                wrapText: useWrapText,
                fontFamily: widget.fontFamily,
                questId: widget.questId,
              );
            },
          ),
        ),
      ],
    );
  }
}

class ChatItemWidget extends ConsumerStatefulWidget {
  final ContentItem item;
  final String questId;
  final String? fontFamily;

  const ChatItemWidget({
    super.key,
    required this.item,
    required this.questId,
    this.fontFamily,
  });

  @override
  ConsumerState<ChatItemWidget> createState() => _ChatItemWidgetState();
}

class _ChatItemWidgetState extends ConsumerState<ChatItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    if (widget.item.animateIn) {
      _animationController.forward();
    } else {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _parseTextWithVariables(String text, GameStateNotifier notifier) {
    return text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
      final expression = match.group(1);
      final value = ScriptExecutor.evaluateExpression(expression, notifier);
      return value?.toString() ?? '';
    });
  }

  Widget _buildMessageContent() {
    final gameStateNotifier = ref.watch(gameStateProvider.notifier);
    final parsedText = _parseTextWithVariables(
      widget.item.text ?? '',
      gameStateNotifier,
    );
    final senderName = widget.item.senderName ?? 'Отправитель';
    final avatarColor = Color(widget.item.avatarColor ?? 0xFF26C6DA);
    final isIncoming = widget.item.isIncoming;

    if (isIncoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(avatarColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    senderName,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.zero,
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: _buildMessageText(parsedText),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    senderName,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withOpacity(0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.zero,
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: _buildMessageText(parsedText),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildAvatar(Color color) {
    if (widget.item.avatarPath != null) {
      return FutureBuilder<File?>(
        future:
            FileStorage.getFilePath(
              'quests/${widget.questId}/${widget.item.avatarPath!}',
            ).then((path) async {
              final file = File(path);
              if (await file.exists()) return file;
              return null;
            }),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return CircleAvatar(
              radius: 18,
              backgroundImage: FileImage(snapshot.data!),
            );
          }
          return CircleAvatar(
            radius: 18,
            backgroundColor: color,
            child: const Icon(Icons.person, size: 18, color: Colors.white),
          );
        },
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: color,
      child: const Icon(Icons.person, size: 18, color: Colors.white),
    );
  }

  Widget _buildMessageText(String text) {
    final config = MarkdownConfig(
      configs: [
        PConfig(
          textStyle: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.3,
            fontFamily: widget.fontFamily,
          ),
        ),
        const ListConfig(marginLeft: 18.0, marginBottom: 0.0),
        const BlockquoteConfig(
          textColor: Colors.white70,
          sideColor: Colors.white70,
        ),
      ],
    );

    final markdownText = preserveMarkdownHardLineBreaks(text);
    final generator = createColorMarkdownGenerator(
      linesMargin: const EdgeInsets.symmetric(vertical: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: generator.buildWidgets(markdownText, config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.animateIn) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: _buildMessageContent(),
        ),
      );
    }
    return _buildMessageContent();
  }
}
