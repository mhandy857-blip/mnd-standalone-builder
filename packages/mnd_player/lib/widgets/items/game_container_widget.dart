import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:flutter/material.dart';

class GameContainerWidget extends StatefulWidget {
  final ContentItem item;
  final String questId;
  final Function(ContentItem) onInteract;
  final Function(String, String) onInputSubmitted;
  final VoidCallback onComplete;
  final Function(String) onTransition;
  final Function(String) onNavigateToNode;
  final double? audioVolume;
  final bool parentIsInteractable;
  final String? fontFamily;
  final String scriptEngineMode;
  final bool? imageRoundedCornersOverride;

  const GameContainerWidget({
    super.key,
    required this.item,
    required this.questId,
    required this.onInteract,
    required this.onInputSubmitted,
    required this.onComplete,
    required this.onTransition,
    required this.onNavigateToNode,
    this.audioVolume,
    this.parentIsInteractable = false,
    this.fontFamily,
    this.scriptEngineMode = kScriptEngineModeNew,
    this.imageRoundedCornersOverride,
  });

  @override
  State<GameContainerWidget> createState() => _GameContainerWidgetState();
}

class _GameContainerWidgetState extends State<GameContainerWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.children == null || widget.item.children!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Do not block children interactions when container itself has onPress.
    // Otherwise nested buttons inside row/column can become non-functional.
    final bool hasTriggers =
        (widget.item.scriptTriggers?.containsKey('onPress') ?? false) ||
        (widget.item.targetNodeId != null &&
            widget.item.targetNodeId!.isNotEmpty) ||
        (widget.item.scriptAssetId != null &&
            widget.item.scriptAssetId!.isNotEmpty);

    final bool suppressChildrenInteraction =
        widget.parentIsInteractable || hasTriggers;

    CrossAxisAlignment align;
    switch (widget.item.crossAxisAlignment) {
      case 'start':
        align = CrossAxisAlignment.start;
        break;
      case 'end':
        align = CrossAxisAlignment.end;
        break;
      default:
        align = CrossAxisAlignment.center;
    }

    final textFitMode = widget.item.textFit;
    final rowTextAlignMode = widget.item.rowTextAlignment;

    // Внутренний gap. null → старое поведение (4px у ряда, 8px у колонки).
    final double? customSpacing = widget.item.itemSpacing;
    final double rowHorizontalPad = customSpacing != null
        ? customSpacing / 2.0
        : 4.0;
    final double columnBottomPad = customSpacing != null ? customSpacing : 8.0;

    // Если контейнер явно задаёт скругление (или отключение), то используем его.
    // Иначе наследуем то, что пришло сверху (от ноды).
    final bool? effectiveRoundImages =
        widget.item.childImageRoundedCorners ??
        widget.imageRoundedCornersOverride;

    if (widget.item.type == 'row') {
      final children = widget.item.children!;
      return Row(
        crossAxisAlignment: align,
        children: List.generate(children.length, (i) {
          final childItem = children[i];
          // Если spacing задан явно — кладём padding только МЕЖДУ детьми,
          // чтобы 0 действительно давал стык без зазоров по краям.
          EdgeInsets pad;
          if (customSpacing != null) {
            pad = EdgeInsets.only(
              left: i == 0 ? 0 : rowHorizontalPad,
              right: i == children.length - 1 ? 0 : rowHorizontalPad,
            );
          } else {
            pad = const EdgeInsets.symmetric(horizontal: 4.0);
          }
          if (childItem.type == 'spacer') {
            return Padding(
              padding: pad,
              child: ContentDisplayFactory.build(
                item: childItem,
                questId: widget.questId,
                onInteract: widget.onInteract,
                onInputSubmitted: widget.onInputSubmitted,
                onComplete: () {},
                onTransition: widget.onTransition,
                onNavigateToNode: widget.onNavigateToNode,
                audioVolume: widget.audioVolume,
                isInsideRow: true,
                parentIsInteractable: suppressChildrenInteraction,
                imageRoundedCornersOverride: effectiveRoundImages,
                textFit: textFitMode,
                rowTextAlign: rowTextAlignMode,
                fontFamily: widget.fontFamily,
                scriptEngineMode: widget.scriptEngineMode,
              ),
            );
          }
          return Expanded(
            flex: childItem.flex,
            child: Padding(
              padding: pad,
              child: ContentDisplayFactory.build(
                item: childItem,
                questId: widget.questId,
                onInteract: widget.onInteract,
                onInputSubmitted: widget.onInputSubmitted,
                onComplete: () {},
                onTransition: widget.onTransition,
                onNavigateToNode: widget.onNavigateToNode,
                audioVolume: widget.audioVolume,
                isInsideRow: true,
                parentIsInteractable: suppressChildrenInteraction,
                imageRoundedCornersOverride: effectiveRoundImages,
                textFit: textFitMode,
                rowTextAlign: rowTextAlignMode,
                fontFamily: widget.fontFamily,
                scriptEngineMode: widget.scriptEngineMode,
              ),
            ),
          );
        }),
      );
    } else {
      // Это КОЛОНКА
      final children = widget.item.children!;
      return DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: widget.fontFamily),
        child: Column(
          crossAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(children.length, (i) {
            final childItem = children[i];
            // Аналогично ряду: при явном spacing — gap только между детьми.
            final double bottomPad;
            if (customSpacing != null) {
              bottomPad = i == children.length - 1 ? 0.0 : columnBottomPad;
            } else {
              bottomPad = 8.0;
            }
            return ContentDisplayFactory.build(
              item: childItem,
              questId: widget.questId,
              onInteract: widget.onInteract,
              onInputSubmitted: widget.onInputSubmitted,
              onComplete: () {},
              onTransition: widget.onTransition,
              onNavigateToNode: widget.onNavigateToNode,
              audioVolume: widget.audioVolume,
              isInsideRow: false,
              parentIsInteractable: suppressChildrenInteraction,
              imageRoundedCornersOverride: effectiveRoundImages,
              textFit: 'wrap',
              bottomPadding: bottomPad,
              fontFamily: widget.fontFamily,
              scriptEngineMode: widget.scriptEngineMode,
            );
          }),
        ),
      );
    }
  }
}
