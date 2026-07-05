import 'package:uuid/uuid.dart';

double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? defaultValue;
  return defaultValue;
}

bool _parseBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return defaultValue;
}

String _parseString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  return value.toString();
}

class SavedNode {
  final String id;
  final String chapterId;
  final String title;
  final Map<String, dynamic> content;
  final double x;
  final double y;
  final int? color; // Цвет ноды в формате ARGB
  final String? backgroundAssetId;
  final String? scriptAssetId;
  final double? timerDuration;
  final String? defaultActionNodeId;
  final String? backgroundAudioId;
  final double? backgroundAudioVolume;

  /// Режим нижней статичной HUD-панели в игровом режиме:
  /// * `inherit` — наследовать настройки главы/квеста (сейчас ведёт себя как disabled)
  /// * `enabled` — показать панель и разрешить интерактив
  /// * `statsOnly` — показать панель, но заблокировать интерактив
  /// * `locked` — показать панель полупрозрачно и заблокировать интерактив
  /// * `disabled` — скрыть панель
  final String toolbarMode;

  /// Позиция HUD-панели: `bottom` (по умолчанию), `top`, `left`, `right`.
  final String toolbarPosition;

  /// Стиль HUD-панели: цвет фона, прозрачность, скругление и т.д.
  /// Хранится как JSON-объект. Ключи:
  /// * `backgroundColor` (int ARGB)
  /// * `opacity` (double 0–1)
  /// * `borderRadius` (double)
  /// * `padding` (double)
  /// * `blur` (bool)
  /// * `borderColor` (int ARGB)
  /// * `borderWidth` (double)
  final Map<String, dynamic>? toolbarStyle;

  /// Точечные runtime-ограничения для текущей ноды.
  final bool allowSave;
  final bool allowInventoryAccess;
  final bool allowToolbarInteractions;

  /// Внутренний отступ между корневыми элементами ноды в игровом списке.
  /// `null` — старое поведение (24 px между детьми). `0` — без зазоров.
  final double? itemSpacing;

  /// Глобальное переопределение скругления углов картинок для всей ноды.
  /// `null` — по умолчанию скругление включено. `false` — выключено для всех картинок.
  final bool? imageRoundedCorners;

  // ====== Linked template fields (Templates v2) ======
  /// Если задан — нода связана с мастер-шаблоном `templateRef`.
  /// Различение режимов через [isTemplateMaster]:
  ///
  /// * `templateRef != null && !isTemplateMaster` → **linked-инстанс**:
  ///   контент разворачивается из мастера резолвером.
  /// * `templateRef != null && isTemplateMaster` → **мастер-нода**:
  ///   полноценная редактируемая нода, при сохранении её payload
  ///   синхронизируется с `TemplateRepository`.
  /// * `templateRef == null` — обычная (snapshot) нода.
  final String? templateRef;

  /// Последняя известная инстансу версия мастера (для UI / индикации).
  final int? templateVersion;

  /// true — эта нода сама является «мастером» шаблона [templateRef].
  /// Изменения её payload синхронизируются в репозиторий шаблонов
  /// при следующем сохранении.
  final bool isTemplateMaster;

  SavedNode({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.content,
    this.x = 0.0,
    this.y = 0.0,
    this.color,
    this.backgroundAssetId,
    this.scriptAssetId,
    this.timerDuration,
    this.defaultActionNodeId,
    this.backgroundAudioId,
    this.backgroundAudioVolume,
    this.toolbarMode = 'inherit',
    this.toolbarPosition = 'bottom',
    this.toolbarStyle,
    this.allowSave = true,
    this.allowInventoryAccess = true,
    this.allowToolbarInteractions = true,
    this.itemSpacing,
    this.imageRoundedCorners,
    this.templateRef,
    this.templateVersion,
    this.isTemplateMaster = false,
  });

  /// Связана ли нода с мастер-шаблоном (любой режим).
  bool get hasTemplateLink => templateRef != null && templateRef!.isNotEmpty;

  /// Является ли нода **linked-инстансом** (read-only от мастера).
  bool get isTemplateInstance => hasTemplateLink && !isTemplateMaster;

  /// Является ли нода **мастером** шаблона (источник правды для linked).
  bool get isTemplateMasterNode => hasTemplateLink && isTemplateMaster;

  SavedNode copyWith({
    String? id,
    String? chapterId,
    String? title,
    Map<String, dynamic>? content,
    double? x,
    double? y,
    int? color,
    String? backgroundAssetId,
    String? scriptAssetId,
    double? timerDuration,
    String? defaultActionNodeId,
    String? backgroundAudioId,
    double? backgroundAudioVolume,
    String? templateRef,
    int? templateVersion,
    bool? isTemplateMaster,
    String? toolbarMode,
    String? toolbarPosition,
    Map<String, dynamic>? toolbarStyle,
    bool clearToolbarStyle = false,
    bool? allowSave,
    bool? allowInventoryAccess,
    bool? allowToolbarInteractions,
    double? itemSpacing,
    bool clearItemSpacing = false,
    bool? imageRoundedCorners,
    bool clearImageRoundedCorners = false,
    bool clearTemplateLink = false,
  }) {
    return SavedNode(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      title: title ?? this.title,
      content: content ?? this.content,
      x: x ?? this.x,
      y: y ?? this.y,
      color: color ?? this.color,
      backgroundAssetId: backgroundAssetId ?? this.backgroundAssetId,
      scriptAssetId: scriptAssetId ?? this.scriptAssetId,
      timerDuration: timerDuration ?? this.timerDuration,
      defaultActionNodeId: defaultActionNodeId ?? this.defaultActionNodeId,
      backgroundAudioId: backgroundAudioId ?? this.backgroundAudioId,
      backgroundAudioVolume:
          backgroundAudioVolume ?? this.backgroundAudioVolume,
      toolbarMode: toolbarMode ?? this.toolbarMode,
      toolbarPosition: toolbarPosition ?? this.toolbarPosition,
      toolbarStyle: clearToolbarStyle
          ? null
          : (toolbarStyle ?? this.toolbarStyle),
      allowSave: allowSave ?? this.allowSave,
      allowInventoryAccess: allowInventoryAccess ?? this.allowInventoryAccess,
      allowToolbarInteractions:
          allowToolbarInteractions ?? this.allowToolbarInteractions,
      itemSpacing: clearItemSpacing ? null : (itemSpacing ?? this.itemSpacing),
      imageRoundedCorners: clearImageRoundedCorners
          ? null
          : (imageRoundedCorners ?? this.imageRoundedCorners),
      templateRef: clearTemplateLink ? null : (templateRef ?? this.templateRef),
      templateVersion: clearTemplateLink
          ? null
          : (templateVersion ?? this.templateVersion),
      isTemplateMaster: clearTemplateLink
          ? false
          : (isTemplateMaster ?? this.isTemplateMaster),
    );
  }

  factory SavedNode.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? 'error_id_${const Uuid().v4()}';
    final title = json['title']?.toString() ?? 'Нода без имени';

    final rawContent = json['content'];
    final Map<String, dynamic> contentData = rawContent is Map<String, dynamic>
        ? rawContent
        : {'items': []};

    return SavedNode(
      id: id,
      title: title,
      content: contentData,
      chapterId: _parseString(json['chapterId']),
      x: _parseDouble(json['x']),
      y: _parseDouble(json['y']),
      color: json['color'] as int?,
      backgroundAssetId: json['backgroundAssetId']?.toString(),
      scriptAssetId: json['scriptAssetId']?.toString(),
      timerDuration: json['timerDuration'] != null
          ? _parseDouble(json['timerDuration'])
          : null,
      defaultActionNodeId: json['defaultActionNodeId']?.toString(),
      backgroundAudioId: json['backgroundAudioId']?.toString(),
      backgroundAudioVolume: json['backgroundAudioVolume'] != null
          ? _parseDouble(json['backgroundAudioVolume'])
          : null,
      toolbarMode: _parseString(json['toolbarMode'], defaultValue: 'inherit'),
      toolbarPosition: _parseString(
        json['toolbarPosition'],
        defaultValue: 'bottom',
      ),
      toolbarStyle: json['toolbarStyle'] is Map
          ? Map<String, dynamic>.from(json['toolbarStyle'] as Map)
          : null,
      allowSave: _parseBool(json['allowSave'], defaultValue: true),
      allowInventoryAccess: _parseBool(
        json['allowInventoryAccess'],
        defaultValue: true,
      ),
      allowToolbarInteractions: _parseBool(
        json['allowToolbarInteractions'],
        defaultValue: true,
      ),
      itemSpacing: json['itemSpacing'] != null
          ? _parseDouble(json['itemSpacing'])
          : null,
      imageRoundedCorners: json['imageRoundedCorners'] as bool?,
      templateRef: json['templateRef']?.toString(),
      templateVersion: (json['templateVersion'] as num?)?.toInt(),
      isTemplateMaster: json['isTemplateMaster'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterId': chapterId,
    'title': title,
    'content': content,
    'x': x,
    'y': y,
    if (color != null) 'color': color,
    if (backgroundAssetId != null) 'backgroundAssetId': backgroundAssetId,
    if (scriptAssetId != null) 'scriptAssetId': scriptAssetId,
    if (timerDuration != null) 'timerDuration': timerDuration,
    if (defaultActionNodeId != null) 'defaultActionNodeId': defaultActionNodeId,
    if (backgroundAudioId != null) 'backgroundAudioId': backgroundAudioId,
    if (backgroundAudioVolume != null)
      'backgroundAudioVolume': backgroundAudioVolume,
    if (toolbarMode != 'inherit') 'toolbarMode': toolbarMode,
    if (toolbarPosition != 'bottom') 'toolbarPosition': toolbarPosition,
    if (toolbarStyle != null) 'toolbarStyle': toolbarStyle,
    if (!allowSave) 'allowSave': false,
    if (!allowInventoryAccess) 'allowInventoryAccess': false,
    if (allowToolbarInteractions != true) 'allowToolbarInteractions': false,
    if (itemSpacing != null) 'itemSpacing': itemSpacing,
    if (imageRoundedCorners != null) 'imageRoundedCorners': imageRoundedCorners,
    if (templateRef != null) 'templateRef': templateRef,
    if (templateVersion != null) 'templateVersion': templateVersion,
    if (isTemplateMaster) 'isTemplateMaster': true,
  };
}

class CameraState {
  final double offsetX;
  final double offsetY;
  final double scale;

  CameraState({this.offsetX = 0.0, this.offsetY = 0.0, this.scale = 1.0});

  factory CameraState.fromJson(Map<String, dynamic> json) => CameraState(
    offsetX: _parseDouble(json['offsetX']),
    offsetY: _parseDouble(json['offsetY']),
    scale: _parseDouble(json['scale'], defaultValue: 1.0),
  );

  Map<String, dynamic> toJson() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'scale': scale,
  };
}
