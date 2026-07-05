const String kScriptEngineModeNew = 'new';

String normalizeScriptEngineMode(String? rawMode) {
  // Legacy engine mode is fully removed; always normalize to the new engine.
  return kScriptEngineModeNew;
}

String? _stringOrNull(dynamic value) {
  if (value == null) return null;
  final result = value.toString().trim();
  return result.isEmpty ? null : result;
}

String _stringOrFallback(dynamic value, String fallback) {
  return _stringOrNull(value) ?? fallback;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

class Quest {
  final String id;
  final String title;
  final String? imageUrl;
  final String? author;
  final String? description;
  final String? startNodeId;
  final String? password;
  final DateTime? created;
  final DateTime? lastOpened;
  final String? version;
  final String? backgroundAssetId;
  final String? localPreviewPath;
  final List<String>? screenshotFiles;
  final bool dimBackground;
  final bool hideNodeTitles;
  final List<String> genres;
  final String defaultTextFit;
  final bool isReadOnly;
  final bool isMarketDownloaded;
  final String? marketQuestId;
  final String? customFontFileName;
  final bool wrapButtonText;
  final String nodeTransitionMode;
  final String scriptEngineMode;
  final bool isCorrupted;
  final String? loadError;
  final List<String> pluginDependencies;
  final bool allowOpenContent;

  Quest({
    required this.id,
    required this.title,
    this.imageUrl,
    this.author,
    this.description,
    this.startNodeId,
    this.password,
    this.created,
    this.lastOpened,
    this.version,
    this.backgroundAssetId,
    this.localPreviewPath,
    this.screenshotFiles,
    this.dimBackground = true,
    this.hideNodeTitles = false,
    this.genres = const [],
    this.defaultTextFit = 'scale',
    this.isReadOnly = false,
    this.isMarketDownloaded = false,
    this.marketQuestId,
    this.customFontFileName,
    this.wrapButtonText = true,
    this.nodeTransitionMode = 'none',
    this.scriptEngineMode = kScriptEngineModeNew,
    this.isCorrupted = false,
    this.loadError,
    this.pluginDependencies = const [],
    this.allowOpenContent = false,
  });

  factory Quest.fromJson(Map<String, dynamic> json) {
    final bool isDimmed = json['dimBackground'] as bool? ?? true;
    final bool isTitlesHidden = json['hideNodeTitles'] as bool? ?? false;
    final String textFit = json['defaultTextFit'] as String? ?? 'scale';
    final bool readOnly = json['isReadOnly'] as bool? ?? false;
    final bool isMarketDownloaded =
        json['isMarketDownloaded'] as bool? ??
        json['isFromMarket'] as bool? ??
        false;
    final String? marketQuestId = json['marketQuestId'] as String?;
    final bool buttonWrapText = json['wrapButtonText'] as bool? ?? true;
    final String transitionMode =
        json['nodeTransitionMode'] as String? ?? 'none';
    final String scriptEngineMode = normalizeScriptEngineMode(
      json['scriptEngineMode']?.toString() ?? json['scriptEngine']?.toString(),
    );
    final pluginDeps =
        (json['pluginDependencies'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final bool allowOpenContent = json['allowOpenContent'] as bool? ?? false;

    List<String> loadedGenres = [];
    if (json['genres'] != null && json['genres'] is List) {
      loadedGenres = (json['genres'] as List).map((e) => e.toString()).toList();
    } else if (json['category'] != null) {
      loadedGenres.add(json['category'].toString());
    }

    return Quest(
      id: _stringOrFallback(json['id'], ''),
      title: _stringOrFallback(json['title'], 'Без названия'),
      imageUrl: _stringOrNull(json['imageUrl']),
      author: _stringOrNull(json['author']),
      description: _stringOrNull(json['description']),
      startNodeId: _stringOrNull(json['startNodeId']),
      password: _stringOrNull(json['password']),
      created: _parseDate(json['created']),
      lastOpened: _parseDate(json['lastOpened']),
      version: _stringOrNull(json['version']),
      backgroundAssetId: _stringOrNull(json['backgroundAssetId']),
      screenshotFiles: (json['screenshot_files'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      dimBackground: isDimmed,
      hideNodeTitles: isTitlesHidden,
      genres: loadedGenres,
      defaultTextFit: textFit,
      isReadOnly: readOnly,
      isMarketDownloaded: isMarketDownloaded,
      marketQuestId: marketQuestId,
      customFontFileName: _stringOrNull(json['customFontFileName']),
      wrapButtonText: buttonWrapText,
      nodeTransitionMode: transitionMode,
      scriptEngineMode: scriptEngineMode,
      isCorrupted: json['isCorrupted'] as bool? ?? false,
      loadError: _stringOrNull(json['loadError']),
      pluginDependencies: pluginDeps,
      allowOpenContent: allowOpenContent,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'imageUrl': imageUrl,
    'author': author,
    'description': description,
    'startNodeId': startNodeId,
    'password': password,
    'created': created?.toIso8601String(),
    'lastOpened': lastOpened?.toIso8601String(),
    'version': version,
    'dimBackground': dimBackground,
    'hideNodeTitles': hideNodeTitles,
    'genres': genres,
    'defaultTextFit': defaultTextFit,
    'isReadOnly': isReadOnly,
    'isMarketDownloaded': isMarketDownloaded,
    'allowOpenContent': allowOpenContent,
    if (marketQuestId != null) 'marketQuestId': marketQuestId,
    'wrapButtonText': wrapButtonText,
    'nodeTransitionMode': nodeTransitionMode,
    'scriptEngineMode': scriptEngineMode,
    'pluginDependencies': pluginDependencies,
    'category': genres.isNotEmpty ? genres.first : null,
    if (backgroundAssetId != null) 'backgroundAssetId': backgroundAssetId,
    if (screenshotFiles != null) 'screenshot_files': screenshotFiles,
    if (customFontFileName != null) 'customFontFileName': customFontFileName,
  };

  Quest copyWith({
    String? id,
    String? title,
    String? imageUrl,
    String? author,
    String? description,
    String? startNodeId,
    String? password,
    DateTime? created,
    DateTime? lastOpened,
    String? version,
    String? backgroundAssetId,
    String? localPreviewPath,
    List<String>? screenshotFiles,
    bool? dimBackground,
    bool? hideNodeTitles,
    List<String>? genres,
    String? defaultTextFit,
    bool? isReadOnly,
    bool? isMarketDownloaded,
    String? marketQuestId,
    String? customFontFileName,
    bool? wrapButtonText,
    String? nodeTransitionMode,
    String? scriptEngineMode,
    bool? isCorrupted,
    String? loadError,
    List<String>? pluginDependencies,
    bool? allowOpenContent,
  }) {
    return Quest(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      author: author ?? this.author,
      description: description ?? this.description,
      startNodeId: startNodeId ?? this.startNodeId,
      password: password ?? this.password,
      created: created ?? this.created,
      lastOpened: lastOpened ?? this.lastOpened,
      version: version ?? this.version,
      backgroundAssetId: backgroundAssetId ?? this.backgroundAssetId,
      localPreviewPath: localPreviewPath ?? this.localPreviewPath,
      screenshotFiles: screenshotFiles ?? this.screenshotFiles,
      dimBackground: dimBackground ?? this.dimBackground,
      hideNodeTitles: hideNodeTitles ?? this.hideNodeTitles,
      genres: genres ?? this.genres,
      defaultTextFit: defaultTextFit ?? this.defaultTextFit,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      isMarketDownloaded: isMarketDownloaded ?? this.isMarketDownloaded,
      marketQuestId: marketQuestId ?? this.marketQuestId,
      customFontFileName: customFontFileName ?? this.customFontFileName,
      wrapButtonText: wrapButtonText ?? this.wrapButtonText,
      nodeTransitionMode: nodeTransitionMode ?? this.nodeTransitionMode,
      scriptEngineMode: scriptEngineMode ?? this.scriptEngineMode,
      isCorrupted: isCorrupted ?? this.isCorrupted,
      loadError: loadError ?? this.loadError,
      pluginDependencies: pluginDependencies ?? this.pluginDependencies,
      allowOpenContent: allowOpenContent ?? this.allowOpenContent,
    );
  }
}
