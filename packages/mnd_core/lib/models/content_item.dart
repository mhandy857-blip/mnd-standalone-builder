import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class ButtonStyleConfig {
  final String presetId;
  final String? presetName;
  final int horizontalModules;
  final int verticalModules;
  final int centerModules;
  final double moduleSize;
  final bool autoCenterByText;
  final int fillColorValue;
  final int borderColorValue;
  final int textColorValue;
  final String? cornerAsset;
  final String? hAsset;
  final String? vAsset;
  final String? centerAsset;

  const ButtonStyleConfig({
    this.presetId = 'custom',
    this.presetName,
    this.horizontalModules = 6,
    this.verticalModules = 3,
    this.centerModules = 10,
    this.moduleSize = 12.0,
    this.autoCenterByText = true,
    this.fillColorValue = 0xFF1A2336,
    this.borderColorValue = 0xFF26C6DA,
    this.textColorValue = 0xFF26C6DA,
    this.cornerAsset,
    this.hAsset,
    this.vAsset,
    this.centerAsset,
  });

  Color get fillColor => Color(fillColorValue);
  Color get borderColor => Color(borderColorValue);
  Color get textColor => Color(textColorValue);
  bool get hasModuleAssets =>
      (cornerAsset?.trim().isNotEmpty ?? false) &&
      (hAsset?.trim().isNotEmpty ?? false) &&
      (vAsset?.trim().isNotEmpty ?? false) &&
      (centerAsset?.trim().isNotEmpty ?? false);

  ButtonStyleConfig copyWith({
    String? presetId,
    String? presetName,
    int? horizontalModules,
    int? verticalModules,
    int? centerModules,
    double? moduleSize,
    bool? autoCenterByText,
    int? fillColorValue,
    int? borderColorValue,
    int? textColorValue,
    String? cornerAsset,
    String? hAsset,
    String? vAsset,
    String? centerAsset,
    bool clearModuleAssets = false,
  }) {
    return ButtonStyleConfig(
      presetId: presetId ?? this.presetId,
      presetName: presetName ?? this.presetName,
      horizontalModules: horizontalModules ?? this.horizontalModules,
      verticalModules: verticalModules ?? this.verticalModules,
      centerModules: centerModules ?? this.centerModules,
      moduleSize: moduleSize ?? this.moduleSize,
      autoCenterByText: autoCenterByText ?? this.autoCenterByText,
      fillColorValue: fillColorValue ?? this.fillColorValue,
      borderColorValue: borderColorValue ?? this.borderColorValue,
      textColorValue: textColorValue ?? this.textColorValue,
      cornerAsset: clearModuleAssets ? null : (cornerAsset ?? this.cornerAsset),
      hAsset: clearModuleAssets ? null : (hAsset ?? this.hAsset),
      vAsset: clearModuleAssets ? null : (vAsset ?? this.vAsset),
      centerAsset: clearModuleAssets ? null : (centerAsset ?? this.centerAsset),
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    if (presetName != null) 'presetName': presetName,
    'horizontalModules': horizontalModules,
    'verticalModules': verticalModules,
    'centerModules': centerModules,
    'moduleSize': moduleSize,
    'autoCenterByText': autoCenterByText,
    'fillColor': fillColorValue,
    'borderColor': borderColorValue,
    'textColor': textColorValue,
    if (cornerAsset != null) 'cornerAsset': cornerAsset,
    if (hAsset != null) 'hAsset': hAsset,
    if (vAsset != null) 'vAsset': vAsset,
    if (centerAsset != null) 'centerAsset': centerAsset,
  };

  factory ButtonStyleConfig.fromJson(Map<String, dynamic> json) {
    return ButtonStyleConfig(
      presetId: json['presetId'] as String? ?? 'custom',
      presetName: json['presetName'] as String?,
      horizontalModules: (json['horizontalModules'] as num?)?.toInt() ?? 6,
      verticalModules: (json['verticalModules'] as num?)?.toInt() ?? 3,
      centerModules: (json['centerModules'] as num?)?.toInt() ?? 10,
      moduleSize: (json['moduleSize'] as num?)?.toDouble() ?? 12.0,
      autoCenterByText: json['autoCenterByText'] as bool? ?? true,
      fillColorValue: (json['fillColor'] as num?)?.toInt() ?? 0xFF1A2336,
      borderColorValue: (json['borderColor'] as num?)?.toInt() ?? 0xFF26C6DA,
      textColorValue: (json['textColor'] as num?)?.toInt() ?? 0xFF26C6DA,
      cornerAsset: (json['cornerAsset'] ?? json['cornerAssetPath']) as String?,
      hAsset: (json['hAsset'] ?? json['horizontalAsset']) as String?,
      vAsset: (json['vAsset'] ?? json['verticalAsset']) as String?,
      centerAsset: (json['centerAsset'] ?? json['centerAssetPath']) as String?,
    );
  }

  static ButtonStyleConfig fantasy() {
    return const ButtonStyleConfig(
      presetId: 'fantasy',
      presetName: 'Фэнтези',
      horizontalModules: 7,
      verticalModules: 3,
      centerModules: 11,
      moduleSize: 12.0,
      autoCenterByText: true,
      fillColorValue: 0xFF1B2138,
      borderColorValue: 0xFF26C6DA,
      textColorValue: 0xFF4DD0E1,
    );
  }

  static ButtonStyleConfig classic() {
    return const ButtonStyleConfig(
      presetId: 'classic',
      presetName: 'Классика',
      horizontalModules: 6,
      verticalModules: 3,
      centerModules: 9,
      moduleSize: 11.0,
      autoCenterByText: true,
      fillColorValue: 0xFF2B2B2B,
      borderColorValue: 0xFF9E9E9E,
      textColorValue: 0xFFF5F5F5,
    );
  }
}

/// Модель кнопки для всплывающего окна
class ModalButtonConfig {
  final String id;
  final String text; // Текст кнопки (поддерживает формулы)
  final String? targetNodeId; // Целевая нода для перехода
  final String? scriptAssetId; // ID скрипта для выполнения
  final bool isPrimary; // Является ли кнопка основной (стиль)

  const ModalButtonConfig({
    required this.id,
    required this.text,
    this.targetNodeId,
    this.scriptAssetId,
    this.isPrimary = true,
  });

  ModalButtonConfig copyWith({
    String? id,
    String? text,
    String? targetNodeId,
    String? scriptAssetId,
    bool? isPrimary,
  }) {
    return ModalButtonConfig(
      id: id ?? this.id,
      text: text ?? this.text,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      scriptAssetId: scriptAssetId ?? this.scriptAssetId,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (targetNodeId != null) 'targetNodeId': targetNodeId,
    if (scriptAssetId != null) 'scriptAssetId': scriptAssetId,
    'isPrimary': isPrimary,
  };

  factory ModalButtonConfig.fromJson(Map<String, dynamic> json) {
    return ModalButtonConfig(
      id: json['id'] as String? ?? const Uuid().v4(),
      text: json['text'] as String? ?? 'Кнопка',
      targetNodeId: json['targetNodeId'] as String?,
      scriptAssetId: json['scriptAssetId'] as String?,
      isPrimary: json['isPrimary'] as bool? ?? true,
    );
  }
}

class ContentItem {
  final String id;
  final String type;
  final String? text;
  final String? contentMarkdown; // Для всплывающих окон - содержимое в Markdown
  final String? targetNodeId;
  final String? resourcePath;
  final String? scriptAssetId; // ID скрипта для выполнения
  final String? pluginId;
  final String? pluginTypeId;
  final Map<String, dynamic>? pluginData;
  final List<ModalButtonConfig>?
  modalButtons; // Список кнопок для модального окна
  final Map<String, String>? scriptTriggers;
  final String? variableName;
  final String? placeholderText;
  final String? buttonText;
  final Color? backgroundColor;
  final double? padding;
  final double? borderRadius;
  final List<ContentItem>? children;
  final int flex;
  final String crossAxisAlignment;
  final String rowTextAlignment;
  final bool isHidden;
  final String textFit;
  /// Внутренний отступ между детьми контейнера (row/column).
  /// `null` — старое поведение (4px горизонталь у ряда, 8px низ у колонки).
  /// `0` — сетка без зазоров. Любое другое — используется как gap.
  final double? itemSpacing;
  /// Только для `row`: скруглять ли углы у детей-изображений.
  /// `null` — старое поведение (скругление 12). `false` — без скругления.
  final bool? childImageRoundedCorners;
  final bool wrapText;
  // null means use quest-level button wrap setting
  final bool? wrapTextOverride;
  final ButtonStyleConfig? buttonStyle;
  final double volume;
  // Chat fields
  final String? senderName;
  final bool isIncoming;
  final String? avatarPath;
  final int? avatarColor;
  final bool animateIn;

  // ====== Linked template fields (Templates v2) ======
  /// Если задан — этот ContentItem связан с мастер-шаблоном `templateRef`.
  /// Различение двух режимов через [isTemplateMaster]:
  ///
  /// * `templateRef != null && !isTemplateMaster` → **linked-инстанс**:
  ///   read-only, реальное содержимое разворачивается из мастера через
  ///   `TemplateInstanceResolver`. На диске хранится только инстанс
  ///   (id + templateRef + локальные layout-поля).
  /// * `templateRef != null && isTemplateMaster` → **мастер-элемент**:
  ///   обычный full-edit ContentItem, но при сохранении его payload
  ///   автоматически пишется обратно в `TemplateRepository`, что
  ///   обновляет все linked-инстансы по всему квесту.
  /// * `templateRef == null` → обычный (snapshot) ContentItem.
  final String? templateRef;

  /// Последняя известная инстансу версия мастера. Информационное поле —
  /// при текущей политике always-latest используется только для UI
  /// (показать «обновлён» / «версия N»). При обнаружении расхождения
  /// будет переписано на актуальное при следующем сохранении.
  final int? templateVersion;

  /// true — этот объект сам является «мастером» шаблона `templateRef`.
  /// Изменения его содержимого синхронизируются с
  /// `TemplateRepository` при следующем сохранении ноды.
  /// Имеет смысл только если `templateRef != null`.
  final bool isTemplateMaster;

  ContentItem({
    required this.id,
    required this.type,
    this.text,
    this.contentMarkdown,
    this.targetNodeId,
    this.resourcePath,
    this.scriptAssetId,
    this.pluginId,
    this.pluginTypeId,
    this.pluginData,
    this.modalButtons,
    this.scriptTriggers,
    this.variableName,
    this.placeholderText,
    this.buttonText,
    this.backgroundColor,
    this.padding,
    this.borderRadius,
    this.children,
    this.flex = 1,
    this.crossAxisAlignment = 'center',
    this.rowTextAlignment = 'center',
    this.isHidden = false,
    this.textFit = 'auto',
    this.itemSpacing,
    this.childImageRoundedCorners,
    this.wrapText = true,
    this.wrapTextOverride,
    this.buttonStyle,
    this.volume = 1.0,
    this.senderName,
    this.isIncoming = true,
    this.avatarPath,
    this.avatarColor,
    this.animateIn = true,
    this.templateRef,
    this.templateVersion,
    this.isTemplateMaster = false,
  });

  /// Связан ли элемент с мастер-шаблоном (любой режим: linked или master).
  bool get hasTemplateLink => templateRef != null && templateRef!.isNotEmpty;

  /// Является ли элемент **linked-инстансом** шаблона (read-only от мастера).
  bool get isTemplateInstance => hasTemplateLink && !isTemplateMaster;

  /// Является ли элемент **мастером** шаблона (источник правды для linked).
  bool get isTemplateMasterItem => hasTemplateLink && isTemplateMaster;

  ContentItem copyWith({
    String? id,
    String? type,
    String? text,
    String? contentMarkdown,
    String? targetNodeId,
    bool clearTargetNodeId = false,
    String? resourcePath,
    String? scriptAssetId,
    String? pluginId,
    String? pluginTypeId,
    Map<String, dynamic>? pluginData,
    List<ModalButtonConfig>? modalButtons,
    Map<String, String>? scriptTriggers,
    bool forceClearTriggers = false,
    String? variableName,
    String? placeholderText,
    String? buttonText,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
    double? padding,
    bool clearPadding = false,
    double? borderRadius,
    bool clearBorderRadius = false,
    List<ContentItem>? children,
    int? flex,
    String? crossAxisAlignment,
    String? rowTextAlignment,
    bool? isHidden,
    String? textFit,
    double? itemSpacing,
    bool clearItemSpacing = false,
    bool? childImageRoundedCorners,
    bool clearChildImageRoundedCorners = false,
    bool? wrapText,
    bool? wrapTextOverride,
    bool clearWrapTextOverride = false,
    ButtonStyleConfig? buttonStyle,
    bool clearButtonStyle = false,
    double? volume,
    String? senderName,
    bool? isIncoming,
    String? avatarPath,
    int? avatarColor,
    bool? animateIn,
    String? templateRef,
    int? templateVersion,
    bool? isTemplateMaster,
    bool clearTemplateLink = false,
  }) {
    return ContentItem(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      contentMarkdown: contentMarkdown ?? this.contentMarkdown,
      targetNodeId: clearTargetNodeId
          ? null
          : (targetNodeId ?? this.targetNodeId),
      resourcePath: resourcePath ?? this.resourcePath,
      scriptAssetId: scriptAssetId ?? this.scriptAssetId,
      pluginId: pluginId ?? this.pluginId,
      pluginTypeId: pluginTypeId ?? this.pluginTypeId,
      pluginData: pluginData ?? this.pluginData,
      modalButtons: modalButtons ?? this.modalButtons,
      scriptTriggers: forceClearTriggers
          ? null
          : (scriptTriggers ?? this.scriptTriggers),
      variableName: variableName ?? this.variableName,
      placeholderText: placeholderText ?? this.placeholderText,
      buttonText: buttonText ?? this.buttonText,
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      padding: clearPadding ? null : (padding ?? this.padding),
      borderRadius: clearBorderRadius ? null : (borderRadius ?? this.borderRadius),
      children: children ?? this.children,
      flex: flex ?? this.flex,
      crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
      rowTextAlignment: rowTextAlignment ?? this.rowTextAlignment,
      isHidden: isHidden ?? this.isHidden,
      textFit: textFit ?? this.textFit,
      itemSpacing: clearItemSpacing ? null : (itemSpacing ?? this.itemSpacing),
      childImageRoundedCorners: clearChildImageRoundedCorners
          ? null
          : (childImageRoundedCorners ?? this.childImageRoundedCorners),
      wrapText: wrapText ?? this.wrapText,
      wrapTextOverride: clearWrapTextOverride
          ? null
          : (wrapTextOverride ?? this.wrapTextOverride),
      buttonStyle: clearButtonStyle ? null : (buttonStyle ?? this.buttonStyle),
      volume: volume ?? this.volume,
      senderName: senderName ?? this.senderName,
      isIncoming: isIncoming ?? this.isIncoming,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarColor: avatarColor ?? this.avatarColor,
      animateIn: animateIn ?? this.animateIn,
      templateRef: clearTemplateLink ? null : (templateRef ?? this.templateRef),
      templateVersion: clearTemplateLink
          ? null
          : (templateVersion ?? this.templateVersion),
      isTemplateMaster: clearTemplateLink
          ? false
          : (isTemplateMaster ?? this.isTemplateMaster),
    );
  }

  static Color? _colorFromInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return Color(value);
    if (value is num) return Color(value.toInt());
    return null;
  }

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    var childrenList = <ContentItem>[];
    if (json['children'] != null && json['children'] is List) {
      childrenList = (json['children'] as List)
          .map((i) => ContentItem.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    // Парсим кнопки модалки если есть
    List<ModalButtonConfig>? modalButtons;
    if (json['modalButtons'] != null && json['modalButtons'] is List) {
      modalButtons = (json['modalButtons'] as List)
          .map((b) => ModalButtonConfig.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    final legacyWrapText = json['wrapText'] as bool? ?? true;
    final type = json['type'] as String;

    return ContentItem(
      id: json['id'] as String? ?? const Uuid().v4(),
      type: type,
      text: json['text'] as String?,
      contentMarkdown: json['contentMarkdown'] as String?,
      targetNodeId: json['targetNodeId'] as String?,
      resourcePath:
          json['resourcePath'] as String? ?? json['imagePath'] as String?,
      scriptAssetId: json['scriptAssetId'] as String?,
      pluginId: json['pluginId'] as String?,
      pluginTypeId: json['pluginTypeId'] as String?,
      pluginData: json['pluginData'] is Map
          ? Map<String, dynamic>.from(json['pluginData'] as Map)
          : null,
      modalButtons: modalButtons,
      scriptTriggers: (json['scriptTriggers'] as Map?)?.cast<String, String>(),
      variableName: json['variableName'] as String?,
      placeholderText: json['placeholderText'] as String?,
      buttonText: json['buttonText'] as String?,
      backgroundColor: _colorFromInt(json['backgroundColor']),
      padding: (json['padding'] as num?)?.toDouble(),
      borderRadius: (json['borderRadius'] as num?)?.toDouble(),
      children: childrenList.isNotEmpty ? childrenList : null,
      flex: (json['flex'] as num?)?.toInt() ?? 1,
      crossAxisAlignment: json['crossAxisAlignment'] as String? ?? 'center',
      rowTextAlignment: json['rowTextAlignment'] as String? ?? 'center',
      isHidden: json['isHidden'] as bool? ?? false,
      textFit: json['textFit'] as String? ?? 'auto',
      itemSpacing: (json['itemSpacing'] as num?)?.toDouble(),
      childImageRoundedCorners: json['childImageRoundedCorners'] as bool?,
      wrapText: legacyWrapText,
      wrapTextOverride: json.containsKey('wrapTextOverride')
          ? json['wrapTextOverride'] as bool?
          : ((type == 'button' || type == 'input') && legacyWrapText == false
                ? false
                : null),
      buttonStyle: json['buttonStyle'] is Map<String, dynamic>
          ? ButtonStyleConfig.fromJson(
              json['buttonStyle'] as Map<String, dynamic>,
            )
          : (json['buttonStyle'] is Map
                ? ButtonStyleConfig.fromJson(
                    Map<String, dynamic>.from(json['buttonStyle'] as Map),
                  )
                : null),
      volume: (json['volume'] as num? ?? 1.0).toDouble(),
      senderName: json['senderName'] as String?,
      isIncoming: json['isIncoming'] as bool? ?? true,
      avatarPath: json['avatarPath'] as String?,
      avatarColor: (json['avatarColor'] as num?)?.toInt(),
      animateIn: json['animateIn'] as bool? ?? true,
      templateRef: json['templateRef'] as String?,
      templateVersion: (json['templateVersion'] as num?)?.toInt(),
      isTemplateMaster: json['isTemplateMaster'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (text != null) 'text': text,
    if (contentMarkdown != null) 'contentMarkdown': contentMarkdown,
    if (targetNodeId != null) 'targetNodeId': targetNodeId,
    if (resourcePath != null) 'resourcePath': resourcePath,
    if (scriptAssetId != null) 'scriptAssetId': scriptAssetId,
    if (pluginId != null) 'pluginId': pluginId,
    if (pluginTypeId != null) 'pluginTypeId': pluginTypeId,
    if (pluginData != null) 'pluginData': pluginData,
    if (modalButtons != null)
      'modalButtons': modalButtons!.map((b) => b.toJson()).toList(),
    if (scriptTriggers != null) 'scriptTriggers': scriptTriggers,
    if (variableName != null) 'variableName': variableName,
    if (placeholderText != null) 'placeholderText': placeholderText,
    if (buttonText != null) 'buttonText': buttonText,
    if (backgroundColor != null) 'backgroundColor': backgroundColor!.value,
    if (padding != null) 'padding': padding,
    if (borderRadius != null) 'borderRadius': borderRadius,
    if (children != null) 'children': children!.map((x) => x.toJson()).toList(),
    'flex': flex,
    'crossAxisAlignment': crossAxisAlignment,
    'rowTextAlignment': rowTextAlignment,
    'isHidden': isHidden,
    'textFit': textFit,
    if (itemSpacing != null) 'itemSpacing': itemSpacing,
    if (childImageRoundedCorners != null)
      'childImageRoundedCorners': childImageRoundedCorners,
    'wrapText': wrapText,
    if (wrapTextOverride != null) 'wrapTextOverride': wrapTextOverride,
    if (buttonStyle != null) 'buttonStyle': buttonStyle!.toJson(),
    'volume': volume,
    if (senderName != null) 'senderName': senderName,
    'isIncoming': isIncoming,
    if (avatarPath != null) 'avatarPath': avatarPath,
    if (avatarColor != null) 'avatarColor': avatarColor,
    'animateIn': animateIn,
    if (templateRef != null) 'templateRef': templateRef,
    if (templateVersion != null) 'templateVersion': templateVersion,
    if (isTemplateMaster) 'isTemplateMaster': true,
  };
}
