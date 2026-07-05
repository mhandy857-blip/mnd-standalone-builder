import 'package:uuid/uuid.dart';

/// Тип шаблона. Определяет, что именно хранится в [TemplateItem.payload].
///
/// * [node] — целая нода канваса (включая её content/items).
/// * [content] — одиночный [ContentItem] любого «листового» типа
///   (text/button/image/audio/script/plugin/timer/input/modal/chat...).
/// * [row] — `ContentItem` типа `row` с детьми.
/// * [column] — `ContentItem` типа `column` с детьми.
/// * [modal] — `ContentItem` типа `modal` (всплывающее окно с кнопками).
/// * [chapter] — целая глава с нодами и связями.
/// * [multi] — набор `ContentItem` или нескольких нод (на будущее).
enum TemplateKind { node, content, row, column, modal, chapter, multi }

extension TemplateKindX on TemplateKind {
  String get raw {
    switch (this) {
      case TemplateKind.node:
        return 'node';
      case TemplateKind.content:
        return 'content';
      case TemplateKind.row:
        return 'row';
      case TemplateKind.column:
        return 'column';
      case TemplateKind.modal:
        return 'modal';
      case TemplateKind.chapter:
        return 'chapter';
      case TemplateKind.multi:
        return 'multi';
    }
  }

  /// Человекочитаемое название (для UI).
  String get displayName {
    switch (this) {
      case TemplateKind.node:
        return 'Нода';
      case TemplateKind.content:
        return 'Контент';
      case TemplateKind.row:
        return 'Ряд';
      case TemplateKind.column:
        return 'Колонка';
      case TemplateKind.modal:
        return 'Модалка';
      case TemplateKind.chapter:
        return 'Глава';
      case TemplateKind.multi:
        return 'Набор';
    }
  }

  static TemplateKind fromRaw(String? raw) {
    switch (raw) {
      case 'node':
        return TemplateKind.node;
      case 'content':
        return TemplateKind.content;
      case 'row':
        return TemplateKind.row;
      case 'column':
        return TemplateKind.column;
      case 'modal':
        return TemplateKind.modal;
      case 'chapter':
        return TemplateKind.chapter;
      case 'multi':
        return TemplateKind.multi;
    }
    return TemplateKind.content;
  }
}

/// Описание одного упакованного ресурса в шаблоне.
class TemplateAsset {
  /// Относительный путь внутри квеста (например, `res/images/bg.png`).
  /// Тот же путь будет использован при распаковке.
  final String relativePath;

  /// SHA-256 содержимого (hex). Используется для дедупликации.
  final String sha256;

  /// Размер в байтах.
  final int size;

  /// Локально хранимое имя файла в `app/templates/assets/`
  /// (обычно `<sha256>.<ext>`). Для квест-локального хранилища
  /// и при «in-place» сохранении может совпадать с relativePath.
  final String? storageFileName;

  const TemplateAsset({
    required this.relativePath,
    required this.sha256,
    required this.size,
    this.storageFileName,
  });

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'sha256': sha256,
    'size': size,
    if (storageFileName != null) 'storageFileName': storageFileName,
  };

  factory TemplateAsset.fromJson(Map<String, dynamic> json) {
    return TemplateAsset(
      relativePath: (json['relativePath'] as String?) ?? '',
      sha256: (json['sha256'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      storageFileName: json['storageFileName'] as String?,
    );
  }

  TemplateAsset copyWith({
    String? relativePath,
    String? sha256,
    int? size,
    String? storageFileName,
  }) {
    return TemplateAsset(
      relativePath: relativePath ?? this.relativePath,
      sha256: sha256 ?? this.sha256,
      size: size ?? this.size,
      storageFileName: storageFileName ?? this.storageFileName,
    );
  }
}

/// Источник шаблона: где он физически хранится.
enum TemplateScope {
  /// Локальный для одного квеста: `quests/<id>/res/templates.json`.
  quest,

  /// Глобальный для всех квестов: `app/templates/templates.json`.
  global,
}

/// Единица «репозитория шаблонов».
///
/// Сериализация максимально консервативна: ни одно поле не обязательно
/// для совместимости (см. [fromJson] — все поля имеют дефолты).
class TemplateItem {
  /// Версия схемы. При расширении сериализации увеличиваем.
  /// Текущая = 3 (добавлен contentVersion для linked-инстансов).
  static const int currentSchemaVersion = 3;

  final String id;
  final String name;
  final TemplateKind kind;
  final String? description;
  final String? category;
  final String? iconName;

  /// Сериализованное содержимое. Конкретный формат зависит от [kind]:
  /// * [TemplateKind.node] — `SavedNode.toJson()` (или совместимый Map с
  ///   ключами `id`, `title`, `content`, `x`, `y`, ...).
  /// * [TemplateKind.chapter] — структура `{chapterName, nodes[], connections[]}`.
  /// * остальные `kind` — `ContentItem.toJson()`.
  final Map<String, dynamic> payload;

  /// Список упакованных ресурсов. Пустой, если шаблон ссылается только на
  /// файлы целевого квеста (или вовсе не использует ресурсов).
  final List<TemplateAsset> assets;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Версия схемы файла на момент сохранения.
  final int schemaVersion;

  /// Версия СОДЕРЖИМОГО шаблона. Инкрементируется при каждом изменении
  /// payload в репозитории (см. `TemplateRepository._upsert`).
  ///
  /// Используется linked-инстансами: они хранят последнюю известную
  /// `templateVersion`, и при расхождении с текущей контент перерендеривается.
  /// Для snapshot-вставок никакого эффекта не оказывает.
  final int contentVersion;

  TemplateItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.payload,
    this.description,
    this.category,
    this.iconName,
    this.assets = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.schemaVersion = currentSchemaVersion,
    this.contentVersion = 1,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Есть ли у шаблона упакованные ресурсы.
  bool get hasAssets => assets.isNotEmpty;

  /// Суммарный размер ассетов в байтах (для отображения в UI).
  int get totalAssetsSize {
    var sum = 0;
    for (final a in assets) {
      sum += a.size;
    }
    return sum;
  }

  TemplateItem copyWith({
    String? id,
    String? name,
    TemplateKind? kind,
    Map<String, dynamic>? payload,
    String? description,
    String? category,
    String? iconName,
    List<TemplateAsset>? assets,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
    int? contentVersion,
    bool clearDescription = false,
    bool clearCategory = false,
    bool clearIconName = false,
  }) {
    return TemplateItem(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      description: clearDescription ? null : (description ?? this.description),
      category: clearCategory ? null : (category ?? this.category),
      iconName: clearIconName ? null : (iconName ?? this.iconName),
      assets: assets ?? this.assets,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      schemaVersion: schemaVersion ?? this.schemaVersion,
      contentVersion: contentVersion ?? this.contentVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.raw,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    if (iconName != null) 'iconName': iconName,
    'payload': payload,
    if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'schemaVersion': schemaVersion,
    'contentVersion': contentVersion,
  };

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    final raw = json['payload'];
    Map<String, dynamic> payload = const {};
    if (raw is Map<String, dynamic>) {
      payload = raw;
    } else if (raw is Map) {
      payload = Map<String, dynamic>.from(raw);
    }

    final assetsRaw = json['assets'];
    final assets = <TemplateAsset>[];
    if (assetsRaw is List) {
      for (final a in assetsRaw) {
        if (a is Map<String, dynamic>) {
          assets.add(TemplateAsset.fromJson(a));
        } else if (a is Map) {
          assets.add(TemplateAsset.fromJson(Map<String, dynamic>.from(a)));
        }
      }
    }

    return TemplateItem(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      name: (json['name'] as String?) ?? 'Без имени',
      kind: TemplateKindX.fromRaw(json['kind'] as String?),
      description: json['description'] as String?,
      category: json['category'] as String?,
      iconName: json['iconName'] as String?,
      payload: payload,
      assets: assets,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      contentVersion: (json['contentVersion'] as num?)?.toInt() ?? 1,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
