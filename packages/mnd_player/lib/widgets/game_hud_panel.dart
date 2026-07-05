import 'dart:io';
import 'dart:ui';

import 'package:mnd_core/mnd_core.dart' hide ScriptCacheService;
import 'package:mnd_player/services/script_cache_service.dart';
import 'package:mnd_player/providers/game_screen_provider.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:mnd_player/providers/game_state_provider.dart';
import 'package:mnd_player/widgets/content_display_factory.dart';
import 'package:mnd_player/services/save_game_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// HUD-панель (2 реализации):
//   1. GameHudPanel     — legacy, читает настройки из SavedNode.toolbarMode
//   2. GameHudContentPanel — новая, принимает ContentItem типа 'hud_panel'
//                          и рендерит его children как Positioned-оверлей.

// 1. LEGACY PANEL  (backward compat — SavedNode.toolbarMode)

class GameHudPanel extends ConsumerStatefulWidget {
  final SavedNode node;
  final String questId;
  final bool isTesting;

  const GameHudPanel({
    super.key,
    required this.node,
    required this.questId,
    this.isTesting = false,
  });

  @override
  ConsumerState<GameHudPanel> createState() => _GameHudPanelState();
}

class _GameHudPanelState extends ConsumerState<GameHudPanel> {
  SavedNode get node => widget.node;

  bool get _isVisible {
    return node.toolbarMode == 'enabled' ||
        node.toolbarMode == 'statsOnly' ||
        node.toolbarMode == 'locked';
  }

  bool get _isInteractive =>
      node.toolbarMode == 'enabled' && node.allowToolbarInteractions;

  bool get _isLocked =>
      node.toolbarMode == 'locked' || node.toolbarMode == 'statsOnly';

  Color get _backgroundColor {
    final style = node.toolbarStyle;
    if (style != null && style['backgroundColor'] is int) {
      return Color(style['backgroundColor'] as int);
    }
    return const Color(0xB8000000);
  }

  double get _opacity {
    final style = node.toolbarStyle;
    if (style != null && style['opacity'] is num) {
      return (style['opacity'] as num).toDouble().clamp(0.0, 1.0);
    }
    return _isLocked ? 0.4 : 1.0;
  }

  double get _borderRadius {
    final style = node.toolbarStyle;
    if (style != null && style['borderRadius'] is num) {
      return (style['borderRadius'] as num).toDouble();
    }
    return 16.0;
  }

  double get _padding {
    final style = node.toolbarStyle;
    if (style != null && style['padding'] is num) {
      return (style['padding'] as num).toDouble();
    }
    return 12.0;
  }

  bool get _blur {
    final style = node.toolbarStyle;
    if (style != null && style['blur'] is bool) {
      return style['blur'] as bool;
    }
    return true;
  }

  Color? get _borderColor {
    final style = node.toolbarStyle;
    if (style != null && style['borderColor'] is int) {
      return Color(style['borderColor'] as int);
    }
    return const Color(0x14FFFFFF);
  }

  double get _borderWidth {
    final style = node.toolbarStyle;
    if (style != null && style['borderWidth'] is num) {
      return (style['borderWidth'] as num).toDouble();
    }
    return 1.0;
  }

  static const _statDefs = [
    {
      'keys': ['hp', 'health', 'жизни', 'здоровье'],
      'icon': '❤️',
      'label': 'HP',
    },
    {
      'keys': ['mana', 'mp', 'мана'],
      'icon': '💙',
      'label': 'MP',
    },
    {
      'keys': ['gold', 'money', 'coins', 'золото', 'деньги'],
      'icon': '🪙',
      'label': '',
    },
    {
      'keys': ['ammo', 'bullets', 'патроны'],
      'icon': '🔫',
      'label': '',
    },
    {
      'keys': ['food', 'hunger', 'еда', 'голод'],
      'icon': '🍞',
      'label': '',
    },
    {
      'keys': ['energy', 'stamina', 'энергия', 'выносливость'],
      'icon': '⚡',
      'label': '',
    },
    {
      'keys': ['exp', 'xp', 'опыт'],
      'icon': '⭐',
      'label': 'XP',
    },
    {
      'keys': ['armor', 'броня', 'defence'],
      'icon': '🛡️',
      'label': '',
    },
    {
      'keys': ['level', 'lvl', 'уровень'],
      'icon': '🏆',
      'label': 'Lv',
    },
  ];

  List<_StatEntry> _collectStats(Map<String, dynamic> variables) {
    final result = <_StatEntry>[];
    final lower = <String, String>{
      for (final kv in variables.entries) kv.key.toLowerCase(): kv.key,
    };
    for (final def in _statDefs) {
      final keys = def['keys'] as List<String>;
      for (final k in keys) {
        final realKey = lower[k];
        if (realKey != null && variables[realKey] != null) {
          final val = variables[realKey];
          if (val is num) {
            result.add(
              _StatEntry(
                icon: def['icon'] as String,
                label: def['label'] as String,
                value: val is double && val == val.truncateToDouble()
                    ? val.toInt().toString()
                    : val.toString(),
              ),
            );
          }
          break;
        }
      }
    }
    return result;
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    if (!node.allowSave) return;
    final gameState = ref.read(gameStateProvider);
    String currentNodeId = node.id;
    final hist = gameState.variables['_SYS_HISTORY'];
    if (hist is List && hist.isNotEmpty) {
      final last = hist.last;
      if (last is String) currentNodeId = last;
    }
    final service = ref.read(saveGameServiceProvider);
    final slots = await service.getSaveSlots(widget.questId);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavePanel(
        questId: widget.questId,
        currentNodeId: currentNodeId,
        variables: gameState.variables,
        tables: {
          for (final e in gameState.tables.entries) e.key: e.value.toJson(),
        },
        existingSlots: slots,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();
    final gameState = ref.watch(gameStateProvider);
    final stats = _collectStats(gameState.variables);
    final pos = node.toolbarPosition;
    final panel = _buildPanel(context, stats);
    return Positioned(
      bottom: pos == 'bottom' ? 0 : null,
      top: pos == 'top' ? 0 : null,
      left: (pos == 'left' || pos == 'bottom' || pos == 'top') ? 0 : null,
      right: (pos == 'right' || pos == 'bottom' || pos == 'top') ? 0 : null,
      child: panel,
    );
  }

  Widget _buildPanel(BuildContext context, List<_StatEntry> stats) {
    final pos = node.toolbarPosition;
    final isVertical = pos == 'left' || pos == 'right';
    final p = _padding;
    final br = _borderRadius;
    final borderRadius = BorderRadius.only(
      topLeft: pos == 'bottom' || pos == 'right'
          ? Radius.circular(br)
          : Radius.zero,
      topRight: pos == 'bottom' || pos == 'left'
          ? Radius.circular(br)
          : Radius.zero,
      bottomLeft: pos == 'top' || pos == 'right'
          ? Radius.circular(br)
          : Radius.zero,
      bottomRight: pos == 'top' || pos == 'left'
          ? Radius.circular(br)
          : Radius.zero,
    );
    Widget content = RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _blur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: _panelContent(
                  context,
                  stats,
                  isVertical,
                  p,
                  br,
                  borderRadius,
                ),
              )
            : _panelContent(context, stats, isVertical, p, br, borderRadius),
      ),
    );
    final eff = _opacity;
    if (eff < 1.0) content = Opacity(opacity: eff, child: content);
    if (isVertical) return IntrinsicWidth(child: content);
    return content;
  }

  Widget _panelContent(
    BuildContext context,
    List<_StatEntry> stats,
    bool isVertical,
    double p,
    double br,
    BorderRadius borderRadius,
  ) {
    final locked = _isLocked;
    final interactive = _isInteractive;

    final statsRow = stats.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 12,
            runSpacing: 6,
            children: stats.map((s) => _StatChip(entry: s)).toList(),
          );

    final buttons = <Widget>[];
    if (node.allowSave && !locked && interactive) {
      buttons.add(
        _HudButton(
          icon: Icons.save_alt_rounded,
          tooltip: 'Сохранить',
          onTap: () => _showSaveDialog(context),
        ),
      );
    }

    final buttonsRow = buttons.isEmpty
        ? const SizedBox.shrink()
        : Wrap(spacing: 6, runSpacing: 6, children: buttons);

    Widget innerContent;
    if (isVertical) {
      innerContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats.isNotEmpty) statsRow,
          if (stats.isNotEmpty && buttons.isNotEmpty) const SizedBox(height: 8),
          if (buttons.isNotEmpty) buttonsRow,
        ],
      );
    } else {
      innerContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stats.isNotEmpty) Flexible(child: statsRow),
          if (stats.isNotEmpty && buttons.isNotEmpty) const SizedBox(width: 12),
          if (buttons.isNotEmpty) buttonsRow,
        ],
      );
    }

    if (locked && stats.isEmpty) {
      innerContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, color: Colors.white54, size: 14),
          const SizedBox(width: 4),
          const Text(
            'HUD заблокирован',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.all(p),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: _borderColor ?? Colors.transparent,
          width: _borderWidth,
        ),
      ),
      child: innerContent,
    );
  }
}

// 2. CONTENT-ITEM PANEL  (new — ContentItem type 'hud_panel')

/// Читает настройки из pluginData ContentItem типа `hud_panel`.
class _HudPanelConfig {
  final String position; // bottom | top | left | right
  final String mode; // enabled | statsOnly | locked | disabled
  final String direction; // row | column
  final bool allowSave;
  final bool allowToolbarInteractions;
  final double opacity;
  final double borderRadius;
  final bool blur;
  final double padding;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final String? backgroundImageId;

  /// 'wrap' — перенос строки/колонки, 'scale' — масштабировать при переполнении
  final String overflow;

  /// Размер картинок в HUD-панели (ширина = высота, квадрат).
  /// Применяется ко всем image-элементам — и на верхнем уровне, и внутри
  /// row/column. По умолчанию 48px.
  final double imageSize;

  /// Сила размытия фона (BackdropFilter blur sigma). По умолчанию 14.
  final double blurSigma;

  const _HudPanelConfig({
    this.position = 'bottom',
    this.mode = 'enabled',
    this.direction = 'row',
    this.allowSave = true,
    this.allowToolbarInteractions = true,
    this.opacity = 1.0,
    this.borderRadius = 16.0,
    this.blur = true,
    this.padding = 12.0,
    this.backgroundColor = const Color(0xB8000000),
    this.borderColor = const Color(0x14FFFFFF),
    this.borderWidth = 1.0,
    this.backgroundImageId,
    this.overflow = 'wrap',
    this.imageSize = 48.0,
    this.blurSigma = 14.0,
  });

  factory _HudPanelConfig.fromPluginData(Map<String, dynamic>? d) {
    if (d == null) return const _HudPanelConfig();
    return _HudPanelConfig(
      position: d['position']?.toString() ?? 'bottom',
      mode: d['mode']?.toString() ?? 'enabled',
      direction: d['direction']?.toString() ?? 'row',
      allowSave: d['allowSave'] is bool ? d['allowSave'] as bool : true,
      allowToolbarInteractions: d['allowToolbarInteractions'] is bool
          ? d['allowToolbarInteractions'] as bool
          : true,
      opacity: (d['opacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0,
      borderRadius: (d['borderRadius'] as num?)?.toDouble() ?? 16.0,
      blur: d['blur'] is bool ? d['blur'] as bool : true,
      padding: (d['padding'] as num?)?.toDouble() ?? 12.0,
      backgroundColor: d['backgroundColor'] is int
          ? Color(d['backgroundColor'] as int)
          : const Color(0xB8000000),
      borderColor: d['borderColor'] is int
          ? Color(d['borderColor'] as int)
          : const Color(0x14FFFFFF),
      borderWidth: (d['borderWidth'] as num?)?.toDouble() ?? 1.0,
      backgroundImageId: d['backgroundImageId']?.toString(),
      overflow: d['overflow']?.toString() == 'scale' ? 'scale' : 'wrap',
      imageSize:
          (d['imageSize'] as num?)?.toDouble().clamp(16.0, 200.0) ?? 48.0,
      blurSigma: (d['blurSigma'] as num?)?.toDouble().clamp(1.0, 40.0) ?? 14.0,
    );
  }

  bool get isVisible =>
      mode == 'enabled' || mode == 'statsOnly' || mode == 'locked';
  bool get isInteractive => mode == 'enabled' && allowToolbarInteractions;
  bool get isLocked => mode == 'locked' || mode == 'statsOnly';
}

/// Статичная HUD-панель на основе ContentItem типа `hud_panel`.
/// Монтируется из GameScreen как Positioned-виджет поверх контента.
class GameHudContentPanel extends ConsumerStatefulWidget {
  final ContentItem item;
  final String questId;

  const GameHudContentPanel({
    super.key,
    required this.item,
    required this.questId,
  });

  @override
  ConsumerState<GameHudContentPanel> createState() =>
      _GameHudContentPanelState();
}

class _GameHudContentPanelState extends ConsumerState<GameHudContentPanel> {
  _HudPanelConfig get _cfg =>
      _HudPanelConfig.fromPluginData(widget.item.pluginData);

  // Background image resolved path
  String? _backgroundImagePath;
  String? _lastResolvedImageId;

  @override
  void initState() {
    super.initState();
    _resolveBackgroundImage(_cfg.backgroundImageId);
  }

  @override
  void didUpdateWidget(GameHudContentPanel old) {
    super.didUpdateWidget(old);
    final newId = _cfg.backgroundImageId;
    if (newId != _lastResolvedImageId) {
      _resolveBackgroundImage(newId);
    }
  }

  Future<void> _resolveBackgroundImage(String? imageId) async {
    _lastResolvedImageId = imageId;
    if (imageId == null || imageId.isEmpty) {
      if (mounted) setState(() => _backgroundImagePath = null);
      return;
    }
    try {
      final p = await FileStorage.getFilePath(
        'quests/${widget.questId}/res/images/$imageId',
      );
      if (await File(p).exists()) {
        if (mounted) setState(() => _backgroundImagePath = p);
      } else {
        if (mounted) setState(() => _backgroundImagePath = null);
      }
    } catch (_) {
      if (mounted) setState(() => _backgroundImagePath = null);
    }
  }

  /// Подставляет {varName} → значение переменной.
  String _substituteVars(String text, Map<String, dynamic> variables) {
    return text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final key = m.group(1)!;
      final val = variables[key];
      if (val == null) return m.group(0)!;
      if (val is double && val == val.truncateToDouble()) {
        return val.toInt().toString();
      }
      return val.toString();
    });
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    final cfg = _cfg;
    if (!cfg.allowSave) return;
    final gameState = ref.read(gameStateProvider);
    final service = ref.read(saveGameServiceProvider);
    final slots = await service.getSaveSlots(widget.questId);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavePanel(
        questId: widget.questId,
        currentNodeId: gameState.variables['ID']?.toString() ?? '',
        variables: gameState.variables,
        tables: {
          for (final e in gameState.tables.entries) e.key: e.value.toJson(),
        },
        existingSlots: slots,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (!cfg.isVisible) return const SizedBox.shrink();

    final gameState = ref.watch(gameStateProvider);
    final variables = gameState.variables;

    final children = widget.item.children ?? const [];
    final pos = cfg.position;

    final borderRadius = BorderRadius.only(
      topLeft: pos == 'bottom' || pos == 'right'
          ? Radius.circular(cfg.borderRadius)
          : Radius.zero,
      topRight: pos == 'bottom' || pos == 'left'
          ? Radius.circular(cfg.borderRadius)
          : Radius.zero,
      bottomLeft: pos == 'top' || pos == 'right'
          ? Radius.circular(cfg.borderRadius)
          : Radius.zero,
      bottomRight: pos == 'top' || pos == 'left'
          ? Radius.circular(cfg.borderRadius)
          : Radius.zero,
    );

    // Build child widgets
    final childWidgets = <Widget>[];

    // Explicit children
    for (final child in children) {
      final w = _buildChild(context, child, cfg, variables);
      if (w != null) {
        childWidgets.add(w);
      }
    }

    // Save button (if interactive and allowSave)
    if (cfg.isInteractive && cfg.allowSave) {
      childWidgets.add(
        _HudButton(
          icon: Icons.save_alt_rounded,
          tooltip: 'Сохранить',
          onTap: () => _showSaveDialog(context),
        ),
      );
    }

    // Направление Wrap
    final isRow = cfg.direction == 'row';
    final wrapDirection = isRow ? Axis.horizontal : Axis.vertical;

    Widget inner;
    if (cfg.overflow == 'scale') {
      // Масштабируем содержимое при переполнении
      Widget rawLayout;
      if (isRow) {
        rawLayout = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: childWidgets
              .expand((w) => [w, const SizedBox(width: 8)])
              .take(childWidgets.isEmpty ? 0 : childWidgets.length * 2 - 1)
              .toList(),
        );
      } else {
        rawLayout = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: childWidgets
              .expand((w) => [w, const SizedBox(height: 6)])
              .take(childWidgets.isEmpty ? 0 : childWidgets.length * 2 - 1)
              .toList(),
        );
      }
      inner = FittedBox(fit: BoxFit.scaleDown, child: rawLayout);
    } else {
      // wrap: автоперенос строк/колонок
      inner = Wrap(
        direction: wrapDirection,
        spacing: isRow ? 8.0 : 6.0,
        runSpacing: isRow ? 6.0 : 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: childWidgets,
      );
    }

    Widget panel = RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: cfg.blur
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: cfg.blurSigma,
                  sigmaY: cfg.blurSigma,
                ),
                child: _panelFrame(inner, cfg, borderRadius),
              )
            : _panelFrame(inner, cfg, borderRadius),
      ),
    );
    final effOpacity = cfg.isLocked ? cfg.opacity * 0.5 : cfg.opacity;
    if (effOpacity < 1.0) panel = Opacity(opacity: effOpacity, child: panel);

    final isVertical = pos == 'left' || pos == 'right';
    if (isVertical) {
      // Вертикальная панель: ограничиваем высоту и разрешаем расти в ширину
      panel = SafeArea(child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.70,
          ),
          child: panel,
        ),
      ));
    } else {
      // Горизонтальная панель: ограничиваем высоту чтобы Wrap не занял весь экран
      panel = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.35,
        ),
        child: panel,
      );
    }

    return Positioned(
      bottom: pos == 'bottom' ? 0 : null,
      top: pos == 'top' ? 0 : null,
      left: (pos == 'left' || pos == 'bottom' || pos == 'top') ? 0 : null,
      right: (pos == 'right' || pos == 'bottom' || pos == 'top') ? 0 : null,
      child: panel,
    );
  }

  Widget _panelFrame(
    Widget child,
    _HudPanelConfig cfg,
    BorderRadius borderRadius,
  ) {
    final imgPath = _backgroundImagePath;
    return Container(
      padding: EdgeInsets.all(cfg.padding),
      decoration: BoxDecoration(
        color: cfg.backgroundColor,
        image: imgPath != null
            ? DecorationImage(
                image: FileImage(File(imgPath)),
                fit: BoxFit.cover,
              )
            : null,
        borderRadius: borderRadius,
        border: Border.all(color: cfg.borderColor, width: cfg.borderWidth),
      ),
      child: child,
    );
  }

    Widget? _buildChild(
    BuildContext context,
    ContentItem child,
    _HudPanelConfig cfg,
    Map<String, dynamic> variables, {
    bool inContainer = false,
  }) {
    final built = _buildChildImpl(context, child, cfg, variables, inContainer: inContainer);
    if (built == null) return null;
    
    // Оборачиваем в ConditionalContentWrapper для обработки скриптов onAppear
    return ConditionalContentWrapper(
      key: ValueKey(child.id),
      item: child,
      questId: widget.questId,
      onComplete: () {},
      onTransition: (id) => ref.read(gameScreenProvider(widget.questId).notifier).loadNode(id),
      onNavigateToNode: (id) => ref.read(gameScreenProvider(widget.questId).notifier).loadNode(id),
      allowTargetMismatchFallback: false,
      child: built,
    );
  }
  
  Widget? _buildChildImpl(
    BuildContext context,
    ContentItem child,
    _HudPanelConfig cfg,
    Map<String, dynamic> variables, {
    bool inContainer = false,
  }) {
    switch (child.type) {
      case 'text':
        final raw = child.text ?? '';
        final substituted = _substituteVars(raw, variables);
        return Text(
          substituted,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        );

      case 'hud_stat':
        // variableName — имя переменной, text — иконка/префикс
        final varName = child.variableName ?? '';
        final icon = child.text ?? '';
        final val = variables[varName];
        if (val == null) return null;
        String valStr;
        if (val is double && val == val.truncateToDouble()) {
          valStr = val.toInt().toString();
        } else {
          valStr = val.toString();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon.isNotEmpty)
              Text(icon, style: const TextStyle(fontSize: 15)),
            if (icon.isNotEmpty) const SizedBox(width: 3),
            Text(
              valStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

      case 'row':
        {
          final rowKids = child.children ?? const [];
          final built = <Widget>[];
          for (final c in rowKids) {
            final w = _buildChild(
              context,
              c,
              cfg,
              variables,
              inContainer: true,
            );
            if (w != null) built.add(w);
          }
          if (built.isEmpty) return null;
          final spaced = <Widget>[];
          for (int i = 0; i < built.length; i++) {
            if (i > 0) spaced.add(const SizedBox(width: 6));
            spaced.add(built[i]);
          }
          Widget rowWidget = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: spaced,
          );
          // Если у row есть onPress-триггер или targetNodeId — оборачиваем в GestureDetector
          rowWidget = _wrapWithTapIfNeeded(rowWidget, child, cfg);
          return rowWidget;
        }

      case 'column':
        {
          final colKids = child.children ?? const [];
          final built = <Widget>[];
          for (final c in colKids) {
            final w = _buildChild(
              context,
              c,
              cfg,
              variables,
              inContainer: true,
            );
            if (w != null) built.add(w);
          }
          if (built.isEmpty) return null;
          final spaced = <Widget>[];
          for (int i = 0; i < built.length; i++) {
            if (i > 0) spaced.add(const SizedBox(height: 4));
            spaced.add(built[i]);
          }
          Widget colWidget = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: spaced,
          );
          // Если у column есть onPress-триггер или targetNodeId — оборачиваем в GestureDetector
          colWidget = _wrapWithTapIfNeeded(colWidget, child, cfg);
          return colWidget;
        }

      case 'image':
        if (child.resourcePath == null || child.resourcePath!.isEmpty) {
          return null;
        }
        // Используем imageSize из настроек HUD-панели для обоих контекстов.
        // Никогда не используем double.infinity — Wrap даёт детям
        // неограниченную ширину и это вызывает layout exception.
        return _HudImage(
          questId: widget.questId,
          resourcePath: child.resourcePath!,
          size: cfg.imageSize,
        );

      case 'button':
        {
          debugPrint(
            '[HUD] button: isInteractive=${cfg.isInteractive} '
            'mode=${cfg.mode} allowInteractions=${cfg.allowToolbarInteractions}',
          );
          if (!cfg.isInteractive) {
            debugPrint('[HUD] button SKIPPED (not interactive)');
            return null;
          }
          final label = child.text ?? '';
          final action = child.pluginData?['action']?.toString() ?? '';
          debugPrint(
            '[HUD] button label="$label" action="$action" '
            'targetNodeId="${child.targetNodeId}" '
            'scriptTriggers=${child.scriptTriggers}',
          );
          if (action == 'save' && cfg.allowSave) {
            return _HudButton(
              icon: Icons.save_alt_rounded,
              tooltip: label.isNotEmpty ? label : 'Сохранить',
              onTap: () {
                debugPrint('[HUD] save button tapped');
                _showSaveDialog(context);
              },
            );
          }
          final targetId = child.targetNodeId;
          final onPressTrigger = child.scriptTriggers?['onPress'];
          final hasAction =
              (targetId != null && targetId.isNotEmpty) ||
              (onPressTrigger != null && onPressTrigger.isNotEmpty);
          debugPrint(
            '[HUD] button: targetId="$targetId" '
            'onPressTrigger="$onPressTrigger" hasAction=$hasAction',
          );
          final VoidCallback tapFn = () {
            debugPrint(
              '[HUD] tapFn fired: targetId="$targetId" '
              'onPressTrigger="$onPressTrigger"',
            );
            if (targetId != null && targetId.isNotEmpty) {
              debugPrint('[HUD] calling loadNode("$targetId")');
              ref
                  .read(gameScreenProvider(widget.questId).notifier)
                  .loadNode(targetId);
              return;
            }
            if (onPressTrigger != null && onPressTrigger.isNotEmpty) {
              debugPrint('[HUD] running script "$onPressTrigger"');
              _runHudButtonScript(onPressTrigger);
            }
          };
          if (label.isNotEmpty) {
            return _HudTextButton(
              label: label,
              onTap: hasAction
                  ? tapFn
                  : () {
                      debugPrint('[HUD] button "$label" tapped but NO ACTION');
                    },
            );
          }
          if (hasAction) {
            return _HudButton(
              icon: Icons.touch_app,
              tooltip: 'Кнопка',
              onTap: tapFn,
            );
          }
          debugPrint('[HUD] button has no label and no action — skipped');
          return null;
        }

      default:
        return null;
    }
  }

  /// Оборачивает виджет в GestureDetector если у ContentItem есть
  /// onPress-триггер или targetNodeId (и панель интерактивна).
  Widget _wrapWithTapIfNeeded(
    Widget childWidget,
    ContentItem item,
    _HudPanelConfig cfg,
  ) {
    if (!cfg.isInteractive) return childWidget;
    final targetId = item.targetNodeId;
    final onPressTrigger = item.scriptTriggers?['onPress'];
    final hasAction =
        (targetId != null && targetId.isNotEmpty) ||
        (onPressTrigger != null && onPressTrigger.isNotEmpty);
    if (!hasAction) return childWidget;

    debugPrint(
      '[HUD] _wrapWithTapIfNeeded: type=${item.type} '
      'targetId="$targetId" onPress="$onPressTrigger"',
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint(
          '[HUD] container tap: type=${item.type} '
          'targetId="$targetId" onPress="$onPressTrigger"',
        );
        if (targetId != null && targetId.isNotEmpty) {
          debugPrint('[HUD] container loadNode("$targetId")');
          ref
              .read(gameScreenProvider(widget.questId).notifier)
              .loadNode(targetId);
          return;
        }
        if (onPressTrigger != null && onPressTrigger.isNotEmpty) {
          debugPrint('[HUD] container running script "$onPressTrigger"');
          _runHudButtonScript(onPressTrigger);
        }
      },
      child: childWidget,
    );
  }

  Future<void> _runHudButtonScript(String scriptRelPath) async {
    debugPrint('[HUD] _runHudButtonScript: path="$scriptRelPath"');
    try {
      final fullPath = 'quests/${widget.questId}/$scriptRelPath';
      debugPrint('[HUD] resolving script at "$fullPath"');
      final scriptData = await ScriptCacheService().getScript(fullPath);
      if (scriptData == null) {
        debugPrint('[HUD] script not found at "$fullPath"');
        return;
      }
      debugPrint('[HUD] executing script…');
      final gameStateNotifier = ref.read(gameStateProvider.notifier);
      final nextNodeId = await ScriptExecutor.execute(
        scriptData,
        gameStateNotifier,
        questId: widget.questId,
        eventType: EventType.onPress,
      );
      debugPrint('[HUD] script executed, nextNodeId="$nextNodeId"');
      if (!mounted) return;
      if (nextNodeId != null && nextNodeId.isNotEmpty) {
        debugPrint('[HUD] loadNode("$nextNodeId") after script');
        ref
            .read(gameScreenProvider(widget.questId).notifier)
            .loadNode(nextNodeId);
      }
    } catch (e, st) {
      debugPrint('[HUD] Button script error: $e\n$st');
    }
  }
}

// Shared internals

class _StatEntry {
  final String icon;
  final String label;
  final String value;
  const _StatEntry({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _StatChip extends StatelessWidget {
  final _StatEntry entry;
  const _StatChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(entry.icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 3),
        if (entry.label.isNotEmpty)
          Text(
            '${entry.label} ',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          entry.value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _HudButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HudButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_HudButton> createState() => _HudButtonState();
}

class _HudButtonState extends State<_HudButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          debugPrint('[HUD] _HudButton icon tap');
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0x40FFFFFF) : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _HudTextButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HudTextButton({required this.label, required this.onTap});

  @override
  State<_HudTextButton> createState() => _HudTextButtonState();
}

class _HudTextButtonState extends State<_HudTextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        debugPrint('[HUD] _HudTextButton "${widget.label}" tap');
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0x40FFFFFF) : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Маленькое изображение в HUD-панели.
/// [size] — фиксированная сторона квадрата; null = растянуть по ширине.
class _HudImage extends StatefulWidget {
  final String questId;
  final String resourcePath;
  final double? size;
  const _HudImage({
    required this.questId,
    required this.resourcePath,
    this.size = 32,
  });

  @override
  State<_HudImage> createState() => _HudImageState();
}

class _HudImageState extends State<_HudImage> {
  String? _fullPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final p = await FileStorage.getFilePath(
        'quests/${widget.questId}/${widget.resourcePath}',
      );
      if (await File(p).exists() && mounted) {
        setState(() => _fullPath = p);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    if (_fullPath == null) {
      // Placeholder: никогда не используем double.infinity — это
      // ломает layout внутри Wrap/Row с неограниченными ограничениями.
      return sz != null
          ? SizedBox(width: sz, height: sz)
          : const SizedBox(width: 80, height: 80);
    }
    if (sz == null) {
      // Безопасный «авто» режим: ограничиваем разумным максимумом.
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(File(_fullPath!), fit: BoxFit.contain),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(_fullPath!),
        width: sz,
        height: sz,
        fit: BoxFit.cover,
      ),
    );
  }
}

// Quick save panel (bottom sheet) — shared

class _SavePanel extends ConsumerStatefulWidget {
  final String questId;
  final String currentNodeId;
  final Map<String, dynamic> variables;
  final Map<String, dynamic> tables;
  final List<SaveSlot> existingSlots;

  const _SavePanel({
    required this.questId,
    required this.currentNodeId,
    required this.variables,
    required this.tables,
    required this.existingSlots,
  });

  @override
  ConsumerState<_SavePanel> createState() => _SavePanelState();
}

class _SavePanelState extends ConsumerState<_SavePanel> {
  bool _saving = false;

  Future<void> _saveToSlot(int slotIndex) async {
    setState(() => _saving = true);
    try {
      final service = ref.read(saveGameServiceProvider);
      final existing = widget.existingSlots.length > slotIndex
          ? widget.existingSlots[slotIndex]
          : null;
      final slot = SaveSlot(
        id: existing?.id ?? 'hud_slot_$slotIndex',
        questId: widget.questId,
        slotName: 'Слот ${slotIndex + 1}',
        savedAt: DateTime.now(),
        currentNodeId: widget.currentNodeId,
        variables: widget.variables,
        tables: widget.tables,
      );
      await service.saveGame(slot);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено в слот ${slotIndex + 1}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const totalSlots = 5;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Сохранить игру',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else
            ...List.generate(totalSlots, (i) {
              final slot = widget.existingSlots.length > i
                  ? widget.existingSlots[i]
                  : null;
              final dateStr = slot != null
                  ? '${slot.savedAt.day.toString().padLeft(2, '0')}.${slot.savedAt.month.toString().padLeft(2, '0')}.${slot.savedAt.year} '
                        '${slot.savedAt.hour.toString().padLeft(2, '0')}:${slot.savedAt.minute.toString().padLeft(2, '0')}'
                  : null;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2A2A2A),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                title: Text(
                  slot?.slotName ?? 'Пустой слот',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: dateStr != null
                    ? Text(
                        dateStr,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      )
                    : null,
                trailing: const Icon(Icons.save_rounded, color: Colors.white38),
                onTap: () => _saveToSlot(i),
              );
            }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
