import 'dart:async';
import 'dart:convert';
import 'package:mnd_core/contracts/script_engine_dependencies.dart';
import 'package:mnd_core/contracts/script_runtime.dart';

class ScriptExecutor {
  static const String _legacyTitleOnNodeEnter =
      '\u041f\u0440\u0438 \u0437\u0430\u043f\u0443\u0441\u043a\u0435 \u043d\u043e\u0434\u044b';
  static const String _legacyTitleOnPress =
      '\u041f\u0440\u0438 \u043d\u0430\u0436\u0430\u0442\u0438\u0438';

  static ScriptExpressionEngine? _expressionEngine;
  static ScriptAssetStore? _assetStore;
  static void Function(String message)? _logger;
  static bool _debugLogsEnabled = false;

  static void configure({
    ScriptExpressionEngine? expressionEngine,
    ScriptAssetStore? assetStore,
    void Function(String message)? logger,
    bool? debugLogsEnabled,
  }) {
    if (expressionEngine != null) {
      _expressionEngine = expressionEngine;
    }
    if (assetStore != null) {
      _assetStore = assetStore;
    }
    if (logger != null) {
      _logger = logger;
    }
    if (debugLogsEnabled != null) {
      _debugLogsEnabled = debugLogsEnabled;
    }
  }

  static ScriptExpressionEngine get _engine {
    final engine = _expressionEngine;
    if (engine == null) {
      throw StateError(
        'ScriptExecutor is not configured: expression engine is missing. '
        'Call ScriptExecutor.configure(...) during app bootstrap.',
      );
    }
    return engine;
  }

  static ScriptAssetStore get _store {
    final store = _assetStore;
    if (store == null) {
      throw StateError(
        'ScriptExecutor is not configured: asset store is missing. '
        'Call ScriptExecutor.configure(...) during app bootstrap.',
      );
    }
    return store;
  }

  static void _log(String message) {
    if (_logger != null) {
      _logger!(message);
      return;
    }
    if (!_debugLogsEnabled) return;
    final now = DateTime.now();
    final timeStr =
        "${now.hour}:${now.minute}:${now.second}.${now.millisecond}";
    print("📜 [$timeStr] [Script] $message");
  }

  static EventType checkScriptEventType(Map<String, dynamic> scriptData) {
    final blocks = scriptData['blocks'] as List<dynamic>? ?? [];
    for (final b in blocks) {
      if (b is Map<String, dynamic> && b['type'] == 'event') {
        final et = _resolveEventTypeName(b);
        if (et == EventType.function.name) return EventType.function;
        if (et == EventType.onPress.name) return EventType.onPress;
        if (et == EventType.onContentAppear.name) {
          return EventType.onContentAppear;
        }
        if (et == EventType.onNodeEnter.name) return EventType.onNodeEnter;
      }
    }

    final title = scriptData['name'] ?? scriptData['title'];
    if (title == _legacyTitleOnNodeEnter) return EventType.onNodeEnter;
    if (title == _legacyTitleOnPress) return EventType.onPress;
    if (title == 'Функция') return EventType.function;
    if (title == 'При запуске ноды') return EventType.onNodeEnter;
    if (title == 'При нажатии') return EventType.onPress;

    return EventType.onContentAppear;
  }

  static bool evaluateCondition(
    Map<String, dynamic> scriptData,
    ScriptRuntimeState gameState, {
    EventType eventType = EventType.onContentAppear,
    String? functionName,
    String? contentItemId,
    bool allowTargetMismatchFallback = false,
    bool allowStateMutation = true,
  }) {
    final blocks = scriptData['blocks'] as List<dynamic>? ?? [];
    final blocksToRun = _resolveBlocksToRun(
      blocks,
      eventType,
      functionName: functionName,
      contentItemId: contentItemId,
      allowTargetMismatchFallback: allowTargetMismatchFallback,
    );

    if (blocksToRun.isEmpty) return true;

    for (var blockJson in blocksToRun) {
      if (blockJson is! Map<String, dynamic>) continue;

      final type = blockJson['type'] ?? blockJson['действие'];
      if (type == 'condition' || type == 'условие') {
        return _evaluateConditionLogic(blockJson, gameState);
      }
      if (allowStateMutation && type == 'table_operation') {
        _executeConditionPreludeTableOperation(blockJson, gameState);
        continue;
      }
      if (allowStateMutation &&
          (type == 'assign_variable' ||
              type == 'СЃРѕР·РґР°С‚СЊ_РїРµСЂРµРјРµРЅРЅСѓСЋ' ||
              type == 'РёР·РјРµРЅРёС‚СЊ_РїРµСЂРµРјРµРЅРЅСѓСЋ')) {
        final varName =
            blockJson['variable'] ?? blockJson['РїРµСЂРµРјРµРЅРЅР°СЏ'];
        if (varName != null) {
          final val = evaluateExpression(
            blockJson['value'] ?? blockJson['Р·РЅР°С‡РµРЅРёРµ'],
            gameState,
          );
          gameState.setVariable(varName, val);
        }
      }
    }

    return true;
  }

  static bool _evaluateConditionLogic(
    Map<String, dynamic> block,
    ScriptRuntimeState gameState,
  ) {
    String expression;
    if (block.containsKey('expression')) {
      expression = block['expression'];
    } else {
      final variable = block['variable'] ?? block['переменная'] ?? '';
      final comparison = block['comparison'] ?? block['сравнение'] ?? '==';
      final value = (block['value'] ?? block['значение'] ?? '0').toString();

      final isNumeric = num.tryParse(value) != null;
      final isVariable = value.startsWith('{') && value.endsWith('}');
      final needsQuotes =
          !isNumeric &&
          !isVariable &&
          !value.startsWith("'") &&
          !value.startsWith('"');
      final valueStr = needsQuotes ? "'$value'" : value;

      expression = '{$variable} $comparison $valueStr';
    }

    final result = evaluateExpression(expression, gameState);

    if (result is bool) return result;
    if (result is num) return result != 0;
    if (result is String) return result.isNotEmpty && result != 'false';
    return result != null;
  }

  static void _executeConditionPreludeTableOperation(
    Map<String, dynamic> block,
    ScriptRuntimeState gameState,
  ) {
    final opName = block['operation'];
    if (opName != 'get') return;

    final tableNameExpr = block['tableName'];
    final evaluatedTable = evaluateExpression(tableNameExpr, gameState);
    String tableName;
    if (evaluatedTable is Map || evaluatedTable is List) {
      tableName = tableNameExpr.toString();
    } else {
      tableName = evaluatedTable?.toString() ?? 'storage';
    }

    final table = gameState.getTable(tableName);
    if (table == null) return;

    final rawPath = block['path'] ?? '';
    final pathStr = evaluateExpression(rawPath, gameState)?.toString() ?? '';
    final keys = _parsePath(pathStr);
    final val = _getValueAtPath(table.data, keys);
    final fallbackValue = block.containsKey('value')
        ? evaluateExpression(block['value'], gameState)
        : null;
    final targetVar = block['targetVariable'];

    dynamic resultVal = val ?? fallbackValue;
    if (val is String &&
        (val.contains('{') || val.contains('+') || val.contains('('))) {
      final calc = evaluateExpression(val, gameState);
      if (calc != null) resultVal = calc;
    }

    if (targetVar != null) {
      gameState.setVariable(targetVar, resultVal);
    }
  }

  static Future<String?> execute(
    Map<String, dynamic> scriptData,
    ScriptRuntimeState gameState, {
    required String questId,
    required EventType eventType,
    String? functionName,
    String? contentItemId,
    bool allowTargetMismatchFallback = false,
  }) async {
    final scriptName = scriptData['name'] ?? 'безымянный';
    _log("=== START: $scriptName [Req: ${eventType.name}] ===");

    final allBlocks = scriptData['blocks'] as List<dynamic>? ?? [];
    final controller = ExecutionController();
    String? transitionNodeId;

    try {
      final filteredBlocksToRun = _resolveBlocksToRun(
        allBlocks,
        eventType,
        functionName: functionName,
        contentItemId: contentItemId,
        allowTargetMismatchFallback: allowTargetMismatchFallback,
      );

      if (filteredBlocksToRun.isEmpty) {
        return null;
      }

      for (final blockJson in filteredBlocksToRun) {
        if (blockJson is! Map<String, dynamic>) continue;

        final result = await _executeBlockRecursively(
          blockJson,
          gameState,
          controller,
          questId,
        );

        if (result != null) {
          transitionNodeId = result;
          break;
        }
      }
    } catch (e, stack) {
      _log("❌ ERROR: $e\n$stack");
    }

    return transitionNodeId;
  }

  static bool hasExecutableBlocksForEvent(
    Map<String, dynamic> scriptData,
    EventType eventType, {
    String? functionName,
    String? contentItemId,
    bool allowTargetMismatchFallback = false,
  }) {
    final allBlocks = scriptData['blocks'] as List<dynamic>? ?? const [];
    final blocksToRun = _resolveBlocksToRun(
      allBlocks,
      eventType,
      functionName: functionName,
      contentItemId: contentItemId,
      allowTargetMismatchFallback: allowTargetMismatchFallback,
    );
    return blocksToRun.isNotEmpty;
  }

  static dynamic evaluateExpression(
    dynamic inputValue,
    ScriptRuntimeState gameState,
  ) {
    if (inputValue == null) return null;
    String expr = inputValue.toString().trim();
    if (expr.isEmpty) return null;
    final lowerExpr = expr.toLowerCase();
    if (lowerExpr == 'null') return null;
    if (lowerExpr == 'true') return true;
    if (lowerExpr == 'false') return false;

    expr = _stripWrappingParentheses(expr);

    // Fast path: exact placeholder should preserve original value type
    // (Map/List/table object), not stringify it.
    final exactPlaceholder = RegExp(r'^\{([^{}]+)\}$').firstMatch(expr);
    if (exactPlaceholder != null) {
      final token = exactPlaceholder.group(1)?.trim();
      if (token != null && token.isNotEmpty) {
        final resolved = _resolveInlineTokenValue(token, gameState);
        if (resolved != null) {
          _log(
            '   🧩 Exact placeholder "$expr" resolved to type ${resolved.runtimeType}',
          );
          return resolved;
        }
      }
    }

    final composite = _tryEvaluateCompositeExpression(expr, gameState);
    if (composite.$1) {
      return composite.$2;
    }

    if (expr.contains('{')) {
      expr = _resolveInlinePlaceholders(expr, gameState);
      final resolvedLowerExpr = expr.toLowerCase();
      if (resolvedLowerExpr == 'null') return null;
      if (resolvedLowerExpr == 'true') return true;
      if (resolvedLowerExpr == 'false') return false;
    }

    // 1. Попытка стандартного парсера (для математики)
    try {
      final Map<String, dynamic> context = Map.of(gameState.allVariables);
      // Добавляем таблицы в контекст, если имена не заняты переменными
      gameState.allTables.forEach((tableName, tableObj) {
        if (!context.containsKey(tableName)) {
          context[tableName] = tableObj.data;
        }
      });

      final result = _engine.evaluate(expr, context);
      if (result != null) return result;
    } catch (_) {
      // Игнорируем, пробуем ручной разбор
    }

    // 2. Ручной парсер (для вложенных таблиц: table['key']['subkey'])
    // Это решает проблему с кириллицей и сложными путями
    final deepResult = _manualDeepLookup(expr, gameState);
    if (deepResult != null) return deepResult;

    // 3. Простое число
    final numValue = num.tryParse(expr);
    if (numValue != null) return numValue;

    // 4. Вернуть как есть
    if ((expr.startsWith("'") && expr.endsWith("'")) ||
        (expr.startsWith('"') && expr.endsWith('"'))) {
      return expr.substring(1, expr.length - 1);
    }

    if (expr.contains('[') || expr.contains(']')) {
      return null;
    }

    return expr;
  }

  static (bool, dynamic) _tryEvaluateCompositeExpression(
    String expression,
    ScriptRuntimeState gameState,
  ) {
    final expr = _stripWrappingParentheses(expression.trim());
    if (expr.isEmpty) return (false, null);

    if (expr.startsWith('!')) {
      final inner = evaluateExpression(expr.substring(1), gameState);
      return (true, !_toBool(inner));
    }

    final orPos = _findTopLevelOperator(expr, '||');
    if (orPos != -1) {
      final left = evaluateExpression(expr.substring(0, orPos), gameState);
      final right = evaluateExpression(expr.substring(orPos + 2), gameState);
      return (true, _toBool(left) || _toBool(right));
    }

    final andPos = _findTopLevelOperator(expr, '&&');
    if (andPos != -1) {
      final left = evaluateExpression(expr.substring(0, andPos), gameState);
      final right = evaluateExpression(expr.substring(andPos + 2), gameState);
      return (true, _toBool(left) && _toBool(right));
    }

    // Оператор "in": {A} in (1, 2, 3) / {Месяц} in ('Май', 'Июнь')
    // Истина, если значение слева равно хотя бы одному из значений в списке справа.
    final inPos = _findTopLevelKeyword(expr, 'in');
    if (inPos != -1) {
      final leftExpr = expr.substring(0, inPos).trim();
      final rightExpr = expr.substring(inPos + 2).trim();
      final left = evaluateExpression(leftExpr, gameState);
      final items = _parseInListItems(rightExpr, gameState);
      final matched = items.any((item) => _valuesEqual(left, item));
      return (true, matched);
    }

    final comparisons = ['==', '!=', '>=', '<=', '>', '<'];
    for (final op in comparisons) {
      final idx = _findTopLevelOperator(expr, op);
      if (idx == -1) continue;

      final leftExpr = expr.substring(0, idx).trim();
      final rightExpr = expr.substring(idx + op.length).trim();
      final left = evaluateExpression(leftExpr, gameState);
      final right = evaluateExpression(rightExpr, gameState);
      return (true, _compareValues(left, right, op));
    }

    return (false, null);
  }

  /// Парсит правую часть оператора "in" в список значений.
  /// Поддерживает: (1, 2, 3) / 1, 2, 3 / ('Май', 'Июнь') / {Var}, 5.
  /// Разделителями считаются запятая `,` или вертикальная черта `|`
  /// на верхнем уровне (вне кавычек/скобок).
  static List<dynamic> _parseInListItems(
    String rightExpr,
    ScriptRuntimeState gameState,
  ) {
    var body = rightExpr.trim();
    body = _stripWrappingParentheses(body);
    if (body.isEmpty) return const [];

    final parts = <String>[];
    final buffer = StringBuffer();
    var inQuote = false;
    var quoteChar = '';
    var bracketDepth = 0;
    var parenDepth = 0;

    for (int i = 0; i < body.length; i++) {
      final c = body[i];
      if (inQuote) {
        buffer.write(c);
        if (c == quoteChar && (i == 0 || body[i - 1] != '\\')) {
          inQuote = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inQuote = true;
        quoteChar = c;
        buffer.write(c);
        continue;
      }
      if (c == '[') {
        bracketDepth++;
        buffer.write(c);
        continue;
      }
      if (c == ']') {
        bracketDepth = (bracketDepth - 1).clamp(0, 1000000);
        buffer.write(c);
        continue;
      }
      if (c == '(') {
        parenDepth++;
        buffer.write(c);
        continue;
      }
      if (c == ')') {
        parenDepth = (parenDepth - 1).clamp(0, 1000000);
        buffer.write(c);
        continue;
      }
      final isSeparator = (c == ',' || c == '|');
      if (isSeparator && bracketDepth == 0 && parenDepth == 0) {
        // `||` (логическое ИЛИ) внутри списка трактуем как разделитель тоже,
        // поэтому просто пропускаем повторную `|`.
        final piece = buffer.toString().trim();
        if (piece.isNotEmpty) parts.add(piece);
        buffer.clear();
        continue;
      }
      buffer.write(c);
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) parts.add(last);

    return parts.map((p) => evaluateExpression(p, gameState)).toList();
  }

  /// Ищет ключевое слово-оператор (например, `in`) на верхнем уровне выражения,
  /// окружённое границами слова (пробелы/скобки), вне кавычек и вложенных скобок.
  static int _findTopLevelKeyword(String expression, String keyword) {
    var inQuote = false;
    var quoteChar = '';
    var bracketDepth = 0;
    var parenDepth = 0;
    final kwLen = keyword.length;

    bool isWordChar(String ch) {
      return RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
    }

    for (int i = 0; i <= expression.length - kwLen; i++) {
      final c = expression[i];
      if (inQuote) {
        if (c == quoteChar && expression[i - 1] != '\\') {
          inQuote = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inQuote = true;
        quoteChar = c;
        continue;
      }
      if (c == '[') {
        bracketDepth++;
        continue;
      }
      if (c == ']') {
        bracketDepth = (bracketDepth - 1).clamp(0, 1000000);
        continue;
      }
      if (c == '(') {
        parenDepth++;
        continue;
      }
      if (c == ')') {
        parenDepth = (parenDepth - 1).clamp(0, 1000000);
        continue;
      }
      if (bracketDepth != 0 || parenDepth != 0) continue;
      if (!expression.startsWith(keyword, i)) continue;

      // Проверяем границы слова, чтобы не словить "in" внутри идентификатора.
      final prevChar = i > 0 ? expression[i - 1] : ' ';
      final nextIndex = i + kwLen;
      final nextChar = nextIndex < expression.length
          ? expression[nextIndex]
          : ' ';
      if (isWordChar(prevChar) || isWordChar(nextChar)) continue;

      return i;
    }

    return -1;
  }

  static String _stripWrappingParentheses(String expression) {
    var expr = expression.trim();
    while (expr.startsWith('(') && expr.endsWith(')')) {
      var depth = 0;
      var inQuote = false;
      var quoteChar = '';
      var wraps = true;
      for (int i = 0; i < expr.length; i++) {
        final c = expr[i];
        if (inQuote) {
          if (c == quoteChar && expr[i - 1] != '\\') {
            inQuote = false;
          }
          continue;
        }
        if (c == "'" || c == '"') {
          inQuote = true;
          quoteChar = c;
          continue;
        }
        if (c == '(') depth++;
        if (c == ')') depth--;
        if (depth == 0 && i < expr.length - 1) {
          wraps = false;
          break;
        }
      }
      if (!wraps) break;
      expr = expr.substring(1, expr.length - 1).trim();
    }
    return expr;
  }

  static int _findTopLevelOperator(String expression, String op) {
    var inQuote = false;
    var quoteChar = '';
    var bracketDepth = 0;
    var parenDepth = 0;

    for (int i = 0; i <= expression.length - op.length; i++) {
      final c = expression[i];
      if (inQuote) {
        if (c == quoteChar && expression[i - 1] != '\\') {
          inQuote = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inQuote = true;
        quoteChar = c;
        continue;
      }
      if (c == '[') {
        bracketDepth++;
        continue;
      }
      if (c == ']') {
        bracketDepth = (bracketDepth - 1).clamp(0, 1000000);
        continue;
      }
      if (c == '(') {
        parenDepth++;
        continue;
      }
      if (c == ')') {
        parenDepth = (parenDepth - 1).clamp(0, 1000000);
        continue;
      }
      if (bracketDepth == 0 &&
          parenDepth == 0 &&
          expression.startsWith(op, i)) {
        return i;
      }
    }

    return -1;
  }

  static bool _compareValues(dynamic left, dynamic right, String op) {
    switch (op) {
      case '==':
        return _valuesEqual(left, right);
      case '!=':
        return !_valuesEqual(left, right);
      case '>':
      case '<':
      case '>=':
      case '<=':
        final leftNum = _toNum(left);
        final rightNum = _toNum(right);
        if (leftNum != null && rightNum != null) {
          switch (op) {
            case '>':
              return leftNum > rightNum;
            case '<':
              return leftNum < rightNum;
            case '>=':
              return leftNum >= rightNum;
            case '<=':
              return leftNum <= rightNum;
          }
        }
        final leftStr = left?.toString() ?? '';
        final rightStr = right?.toString() ?? '';
        final cmp = leftStr.compareTo(rightStr);
        switch (op) {
          case '>':
            return cmp > 0;
          case '<':
            return cmp < 0;
          case '>=':
            return cmp >= 0;
          case '<=':
            return cmp <= 0;
        }
    }
    return false;
  }

  static bool _valuesEqual(dynamic left, dynamic right) {
    if (left == null && right == null) return true;
    if (left == null || right == null) {
      final nonNull = left ?? right;
      if (nonNull is String) {
        final normalized = nonNull.trim();
        if (normalized.isEmpty || _isNothingLike(normalized)) {
          return true;
        }
      }
      return false;
    }
    final leftNum = _toNum(left);
    final rightNum = _toNum(right);
    if (leftNum != null && rightNum != null) {
      return leftNum == rightNum;
    }
    final leftVariants = _stringVariants(left.toString());
    final rightVariants = _stringVariants(right.toString());
    return leftVariants.any(rightVariants.contains);
  }

  static bool _isNothingLike(String value) {
    final normalized = value.trim().toLowerCase();
    const nothingLike = <String>{
      '',
      'ничего',
      'nothing',
      'none',
      'null',
      'пусто',
      'нет',
      // mojibake variants seen in legacy saves/quests
      'рќрёс‡рµрірѕ',
      'сђсњсђс‘сђвђўсђвµсђс–сђс•',
      'рѕрёс‡рµрірѕ',
    };
    return nothingLike.contains(normalized);
  }

  static Set<String> _stringVariants(String source) {
    final variants = <String>{};
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      variants.add('');
      return variants;
    }

    variants.add(trimmed);
    variants.add(trimmed.toLowerCase());

    final repaired = _tryRepairMojibake(trimmed);
    if (repaired != null && repaired.isNotEmpty) {
      variants.add(repaired);
      variants.add(repaired.toLowerCase());
    }

    return variants;
  }

  static String? _tryRepairMojibake(String input) {
    // Legacy saves can contain UTF-8 text decoded as latin1/cp1251-like data.
    if (!input.contains('Р') && !input.contains('С')) {
      return null;
    }
    try {
      final repaired = utf8.decode(latin1.encode(input), allowMalformed: true);
      final trimmed = repaired.trim();
      if (trimmed.isEmpty || trimmed == input) return null;
      return trimmed;
    } catch (_) {
      return null;
    }
  }

  static num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is bool) return value ? 1 : 0;
    if (value == null) return null;
    return num.tryParse(value.toString());
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return false;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null' || text == 'false') {
      return false;
    }
    return true;
  }

  static String _resolveInlinePlaceholders(
    String expression,
    ScriptRuntimeState gameState,
  ) {
    return expression.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
      final token = match.group(1)?.trim();
      if (token == null || token.isEmpty) return 'null';
      final value = _resolveInlineTokenValue(token, gameState);
      return _toExpressionLiteral(value);
    });
  }

  static dynamic _resolveInlineTokenValue(
    String token,
    ScriptRuntimeState gameState,
  ) {
    if (gameState.allVariables.containsKey(token)) {
      return gameState.getVariable(token);
    }
    final table = gameState.getTable(token);
    if (table != null) {
      return table.data;
    }
    return _manualDeepLookup(token, gameState);
  }

  static String _toExpressionLiteral(dynamic value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return value.toString();
    return "'${value.toString().replaceAll("'", "\\'")}'";
  }

  /// Парсер без регулярных выражений для путей вида: name['key'].prop
  static dynamic _manualDeepLookup(String expr, ScriptRuntimeState gameState) {
    if (expr.isEmpty) return null;

    int i = 0;
    // 1. Читаем базовое имя (до первого [ или .)
    while (i < expr.length) {
      final char = expr[i];
      if (char == '[' || char == '.') break;
      i++;
    }

    final baseName = expr.substring(0, i).trim();
    if (baseName.isEmpty) return null;

    // Ищем базу
    dynamic currentObj;
    final table = gameState.getTable(baseName);
    if (table != null) {
      currentObj = table.data;
    } else {
      currentObj = gameState.getVariable(baseName);
    }

    if (currentObj == null) return null;

    // 2. Идем по пути
    while (i < expr.length) {
      final char = expr[i];

      if (char == '.') {
        // Dot notation: .key
        i++; // skip dot
        int start = i;
        while (i < expr.length) {
          final c = expr[i];
          if (c == '[' || c == '.') break;
          i++;
        }
        final key = expr.substring(start, i).trim();
        if (key.isEmpty) return null;

        if (currentObj is Map) {
          currentObj = currentObj[key];
        } else {
          return null; // Ошибка типа
        }
      } else if (char == '[') {
        // Bracket notation: ['key'] or [0]
        i++; // skip [
        // Ищем закрывающую скобку, учитывая кавычки
        int start = i;
        int? endBracketIndex;
        bool inQuote = false;
        String quoteChar = '';

        while (i < expr.length) {
          final c = expr[i];
          if (inQuote) {
            if (c == quoteChar && expr[i - 1] != '\\') {
              inQuote = false;
            }
          } else {
            if (c == '"' || c == "'") {
              inQuote = true;
              quoteChar = c;
            } else if (c == ']') {
              endBracketIndex = i;
              break;
            }
          }
          i++;
        }

        if (endBracketIndex == null) return null; // Не закрыта скобка

        final content = expr.substring(start, endBracketIndex).trim();
        i = endBracketIndex + 1; // move past ]

        // Разбираем контент внутри []
        if ((content.startsWith('"') && content.endsWith('"')) ||
            (content.startsWith("'") && content.endsWith("'"))) {
          // Строковый ключ
          if (content.length < 2) return null;
          final key = content.substring(1, content.length - 1);
          if (currentObj is Map) {
            if (currentObj.containsKey(key)) {
              currentObj = currentObj[key];
            } else {
              final dynamic variableKey = gameState.getVariable(key);
              if (variableKey == null) return null;
              currentObj =
                  currentObj[variableKey] ?? currentObj[variableKey.toString()];
            }
          } else {
            return null;
          }
        } else {
          // Числовой индекс (или переменная, но пока поддерживаем int)
          final index = int.tryParse(content);
          if (index != null) {
            if (currentObj is List && index >= 0 && index < currentObj.length) {
              currentObj = currentObj[index];
            } else {
              return null;
            }
          } else {
            final dynamic keyValue = evaluateExpression(content, gameState);
            if (currentObj is Map) {
              if (keyValue == null) return null;
              currentObj =
                  currentObj[keyValue] ?? currentObj[keyValue.toString()];
            } else if (currentObj is List) {
              final dynamicIndex = keyValue is int
                  ? keyValue
                  : int.tryParse(keyValue?.toString() ?? '');
              if (dynamicIndex == null ||
                  dynamicIndex < 0 ||
                  dynamicIndex >= currentObj.length) {
                return null;
              }
              currentObj = currentObj[dynamicIndex];
            } else {
              return null;
            }
          }
        }
      } else {
        // Пропускаем пробелы
        if (char.trim().isEmpty) {
          i++;
          continue;
        }
        return null; // Неожиданный символ
      }

      if (currentObj == null) return null;
    }

    return currentObj;
  }

  static String? _resolveEventTypeName(Map<String, dynamic> block) {
    final eventType = block['eventType']?.toString().trim();
    if (eventType != null && eventType.isNotEmpty) {
      return eventType;
    }

    final title = block['title']?.toString().trim() ?? '';
    if (title == _legacyTitleOnNodeEnter) {
      return EventType.onNodeEnter.name;
    }
    if (title == _legacyTitleOnPress) {
      return EventType.onPress.name;
    }
    if (title == 'Функция') {
      return EventType.function.name;
    }

    if (block['type'] == 'event' || title.isNotEmpty) {
      return EventType.onContentAppear.name;
    }

    return null;
  }

  static List<dynamic> _resolveBlocksToRun(
    List<dynamic> allBlocks,
    EventType requestedType, {
    String? functionName,
    String? contentItemId,
    bool allowTargetMismatchFallback = false,
  }) {
    final allEvents = allBlocks
        .whereType<Map<String, dynamic>>()
        .where(
          (b) =>
              b['type'] == 'event' ||
              b.containsKey('eventType') ||
              b.containsKey('title'),
        )
        .toList();

    bool targetMatches(Map<String, dynamic> block) {
      final target = block['targetContentItemId']?.toString();
      final hasExplicitTarget = target != null && target.isNotEmpty;

      if (contentItemId == null || contentItemId.isEmpty) {
        return !hasExplicitTarget;
      }
      return !hasExplicitTarget || target == contentItemId;
    }

    bool functionMatches(Map<String, dynamic> block) {
      if (requestedType != EventType.function) return true;
      final requiredName = (functionName == null || functionName.trim().isEmpty)
          ? 'main'
          : functionName.trim();
      final currentNameRaw = block['functionName']?.toString().trim();
      final currentName = (currentNameRaw == null || currentNameRaw.isEmpty)
          ? 'main'
          : currentNameRaw;
      return currentName == requiredName;
    }

    final targetEvents = allEvents.where((b) {
      String type = _resolveEventTypeName(b) ?? '';
      if (type.isEmpty && b['title'] == 'При запуске ноды') {
        type = 'onNodeEnter';
      }
      if (type.isEmpty && b['title'] == 'При нажатии') {
        type = 'onPress';
      }
      return type == requestedType.name &&
          targetMatches(b) &&
          functionMatches(b);
    }).toList();

    if (targetEvents.isNotEmpty) {
      final List<dynamic> result = [];
      for (var e in targetEvents) {
        result.addAll(e['children'] ?? []);
      }
      return result;
    }

    final hasAnyEvents = allEvents.isNotEmpty;
    if (!hasAnyEvents) {
      if (requestedType == EventType.onNodeEnter ||
          requestedType == EventType.onContentAppear) {
        return allBlocks;
      }
    }

    return [];
  }

  static String _normalizeScriptId(dynamic rawScriptId) {
    if (rawScriptId == null) return '';
    var value = rawScriptId.toString().trim();
    if (value.isEmpty) return value;
    final slashIndex = value.lastIndexOf('/');
    if (slashIndex != -1) {
      value = value.substring(slashIndex + 1);
    }
    if (value.endsWith('.json')) {
      value = value.substring(0, value.length - 5);
    }
    return value;
  }

  static Future<String?> _resolveScriptPath(
    String questId,
    dynamic rawScriptId,
  ) async {
    final normalizedId = _normalizeScriptId(rawScriptId);
    if (normalizedId.isEmpty) return null;
    final candidates = <String>[
      'quests/$questId/scripts/$normalizedId.json',
      'quests/$questId/_internal_scripts/$normalizedId.json',
    ];
    for (final candidate in candidates) {
      if (await _store.exists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static Future<String?> _executeBlockRecursively(
    Map<String, dynamic> block,
    ScriptRuntimeState gameState,
    ExecutionController controller,
    String questId,
  ) async {
    controller.tick();
    final type = block['type'] ?? block['действие'];

    if (type == 'assign_variable' ||
        type == 'создать_переменную' ||
        type == 'изменить_переменную') {
      final varName = block['variable'] ?? block['переменная'];
      final val = evaluateExpression(
        block['value'] ?? block['значение'],
        gameState,
      );

      final operation = block['операция'];
      if (operation != null && varName != null) {
        dynamic current = gameState.getVariable(varName) ?? 0;
        if (operation == 'прибавить') {
          current += (val ?? 0);
        } else if (operation == 'отнять') {
          current -= (val ?? 0);
        } else {
          current = val;
        }
        gameState.setVariable(varName, current);
      } else if (varName != null) {
        gameState.setVariable(varName, val);
      }
    } else if (type == 'condition' || type == 'условие') {
      final bool conditionResult = _evaluateConditionLogic(block, gameState);

      final key = conditionResult
          ? (block.containsKey('then_blocks') ? 'then_blocks' : 'если_да')
          : (block.containsKey('else_blocks') ? 'else_blocks' : 'если_нет');

      final children = block[key] as List<dynamic>? ?? [];

      for (final child in children) {
        if (child is Map<String, dynamic>) {
          final res = await _executeBlockRecursively(
            child,
            gameState,
            controller,
            questId,
          );
          if (res != null) return res;
        }
      }
    } else if (type == 'call_function') {
      final functionId = block['function_id'];
      final functionEntryRaw = block['function_entry']?.toString().trim();
      final functionEntry =
          (functionEntryRaw == null || functionEntryRaw.isEmpty)
          ? 'main'
          : functionEntryRaw;
      if (functionId != null) {
        final normalizedId = _normalizeScriptId(functionId);
        _log("Calling function: $normalizedId::$functionEntry");
        String? scriptPath;
        try {
          scriptPath = await _resolveScriptPath(questId, functionId);
        } catch (e) {
          _log("Error resolving function path: $e");
          scriptPath = null;
        }

        if (scriptPath != null) {
          try {
            final nestedScriptData = await _store.readJson(scriptPath);
            final hasFunctionBlocks = hasExecutableBlocksForEvent(
              nestedScriptData,
              EventType.function,
              functionName: functionEntry,
            );
            final declaredEvent = checkScriptEventType(nestedScriptData);

            final candidateEvents = <EventType>[
              EventType.function,
              if (!hasFunctionBlocks) declaredEvent,
            ];

            final attempted = <String>{};
            for (final candidateEvent in candidateEvents) {
              if (!attempted.add(candidateEvent.name)) continue;
              if (!hasExecutableBlocksForEvent(
                nestedScriptData,
                candidateEvent,
                functionName: candidateEvent == EventType.function
                    ? functionEntry
                    : null,
              )) {
                continue;
              }

              final res = await execute(
                nestedScriptData,
                gameState,
                questId: questId,
                eventType: candidateEvent,
                functionName: candidateEvent == EventType.function
                    ? functionEntry
                    : null,
                contentItemId: null,
              );
              if (res != null) {
                _log(
                  "Function returned transition: $res "
                  "[event=${candidateEvent.name}]",
                );
                return res;
              }
            }
          } catch (e) {
            _log("Error calling function: $e");
          }
        } else {
          _log("Function script not found: $functionId");
        }
      }
    } else if (type == 'call_script') {
      final scriptId = block['script_id'];
      if (scriptId != null) {
        final normalizedId = _normalizeScriptId(scriptId);
        _log("Calling nested script: $normalizedId");
        String? scriptPath;
        try {
          scriptPath = await _resolveScriptPath(questId, scriptId);
        } catch (e) {
          _log("Error resolving script path: $e");
          scriptPath = null;
        }
        if (scriptPath != null) {
          try {
            final nestedScriptData = await _store.readJson(scriptPath);
            final declaredEvent = checkScriptEventType(nestedScriptData);
            final hasDeclaredBlocks = hasExecutableBlocksForEvent(
              nestedScriptData,
              declaredEvent,
            );

            final candidateEvents = <EventType>[declaredEvent];
            if (!hasDeclaredBlocks) {
              candidateEvents.addAll(const [
                EventType.function,
                EventType.onNodeEnter,
                EventType.onContentAppear,
                EventType.onPress,
              ]);
            }

            final attempted = <String>{};
            for (final candidateEvent in candidateEvents) {
              if (!attempted.add(candidateEvent.name)) continue;
              if (!hasExecutableBlocksForEvent(
                nestedScriptData,
                candidateEvent,
              )) {
                continue;
              }

              final res = await execute(
                nestedScriptData,
                gameState,
                questId: questId,
                eventType: candidateEvent,
                contentItemId: null,
              );
              if (res != null) {
                _log(
                  "Nested script returned transition: $res "
                  "[event=${candidateEvent.name}]",
                );
                return res;
              }
            }
          } catch (e) {
            _log("Error calling script: $e");
          }
        } else {
          _log("Script not found: $scriptId");
        }
      }
    }
    // --- TABLE OPERATIONS ---
    else if (type == 'table_operation') {
      final opName = block['operation'];
      final tableNameExpr = block['tableName'];

      final evaluatedTable = evaluateExpression(tableNameExpr, gameState);
      String tableName;
      if (evaluatedTable is Map || evaluatedTable is List) {
        tableName = tableNameExpr.toString();
      } else {
        tableName = evaluatedTable?.toString() ?? 'storage';
      }

      final table = gameState.getTable(tableName);
      if (table == null) {
        _log("⚠️ Table '$tableName' not found! (Expr: $tableNameExpr)");
        return null;
      }

      String rawPath = block['path'] ?? '';
      String pathStr = evaluateExpression(rawPath, gameState)?.toString() ?? '';
      List<dynamic> keys = _parsePath(pathStr);

      _log(
        "   📊 DataOp: $opName on '$tableName' path $keys (Raw: '$pathStr')",
      );

      dynamic root = table.data;

      if (opName == 'get') {
        final val = _getValueAtPath(root, keys);
        final fallbackValue = block.containsKey('value')
            ? evaluateExpression(block['value'], gameState)
            : null;
        final targetVar = block['targetVariable'];

        dynamic resultVal = val ?? fallbackValue;
        if (val is String &&
            (val.contains('{') || val.contains('+') || val.contains('('))) {
          final calc = evaluateExpression(val, gameState);
          if (calc != null) {
            resultVal = calc;
          }
        }

        if (targetVar != null) {
          gameState.setVariable(targetVar, resultVal);
          _log(
            "      -> Got(type=${resultVal.runtimeType}): $resultVal saved to $targetVar",
          );
        }
      } else if (opName == 'set') {
        final val = evaluateExpression(block['value'], gameState);
        if (keys.isEmpty) {
          _log("⚠️ Cannot set root directly. Use a key.");
        } else {
          _log("      -> Set value type=${val.runtimeType}, value=$val");
          _setValueAtPath(root, keys, val);
          gameState.setTable(tableName, table);
        }
      } else if (opName == 'add') {
        final val = evaluateExpression(block['value'], gameState);
        _log("      -> Add value type=${val.runtimeType}, value=$val");
        final target = _getValueAtPath(root, keys);

        if (target is List) {
          target.add(val);
          gameState.setTable(tableName, table);
        } else if (target == null && keys.isNotEmpty) {
          _setValueAtPath(root, keys, [val]);
          gameState.setTable(tableName, table);
        } else {
          _log("⚠️ Cannot 'add' to non-list at path $keys");
        }
      } else if (opName == 'clear') {
        if (keys.isEmpty) {
          table.data.clear();
        } else {
          final target = _getValueAtPath(root, keys);
          if (target is List) {
            target.clear();
          }
          if (target is Map) {
            target.clear();
          }
        }
        gameState.setTable(tableName, table);
      }
    } else if (type == 'go_to_node') {
      final rawNodeId = block['node_id'];
      if (rawNodeId != null) {
        String expression = rawNodeId.toString().trim();
        if (expression.startsWith('=')) {
          expression = expression.substring(1).trim();
        }
        if (expression.isNotEmpty) {
          final evaluated = evaluateExpression(expression, gameState);
          final resolved = evaluated?.toString().trim();
          if (resolved != null && resolved.isNotEmpty) {
            return resolved;
          }
        }
        return rawNodeId.toString();
      }
    } else if (type == 'wait' || type == 'задержка') {
      final expr = block['expression'] ?? block['milliseconds'] ?? '0';
      final val = evaluateExpression(expr, gameState);
      final int ms = (val is num)
          ? val.toInt()
          : (int.tryParse(val.toString()) ?? 0);
      if (ms > 0) {
        await Future.delayed(Duration(milliseconds: ms));
      }
    } else if (type == 'set_blur') {
      final target = block['target'] ?? 'node';
      final rawBlur = block['blur'] ?? 10.0;
      final evaluatedBlur = evaluateExpression(rawBlur, gameState);
      final blurValue = (evaluatedBlur is num)
          ? evaluatedBlur.toDouble()
          : double.tryParse(evaluatedBlur?.toString() ?? '');
      if (blurValue == null) {
        _log("Invalid blur value: $rawBlur (evaluated: $evaluatedBlur)");
        return null;
      }

      if (target == 'node' || target == 'quest' || target == 'tag') {
        // Устанавливаем переменную, которая влияет на размытие фона
        gameState.setVariable('_internal_background_blur', blurValue);
      }
    } else if (type == 'set_volume') {
      final target = block['target'] ?? 'contentAudio';
      final rawVolume = block['volume'] ?? 1.0;
      final evaluatedVolume = evaluateExpression(rawVolume, gameState);
      final volumeValue = (evaluatedVolume is num)
          ? evaluatedVolume.toDouble()
          : double.tryParse(evaluatedVolume?.toString() ?? '');
      if (volumeValue == null) {
        _log("Invalid volume value: $rawVolume (evaluated: $evaluatedVolume)");
        return null;
      }
      final clampedVolume = volumeValue.clamp(0.0, 1.0);

      // Устанавливаем переменные для управления громкостью
      if (target == 'contentAudio') {
        gameState.setVariable('_internal_node_content_volume', clampedVolume);
      } else if (target == 'tagAudio') {
        gameState.setVariable('_internal_tag_volume', clampedVolume);
      }
    } else if (type == 'play_sound') {
      final audioId = block['audio_id'];
      final rawVolume = block['volume'] ?? 1.0;
      final evaluatedVolume = evaluateExpression(rawVolume, gameState);
      final volumeValue = (evaluatedVolume is num)
          ? evaluatedVolume.toDouble()
          : double.tryParse(evaluatedVolume?.toString() ?? '1.0');
      final clampedVolume = (volumeValue ?? 1.0).clamp(0.0, 1.0);

      if (audioId != null) {
        gameState.setVariable('_internal_play_sound_volume', clampedVolume);
        gameState.setVariable('_internal_play_sound_id', audioId.toString());
        _log("   🔊 Play sound: $audioId (Vol: $clampedVolume)");
      }
    } else if (type == 'stop_sound') {
      final target = block['target'] ?? 'all';
      final audioId = block['audio_id'];

      if (target == 'all') {
        gameState.setVariable('_internal_stop_sound_target', 'all');
        _log("   ⏹ Stop all sounds");
      } else if (audioId != null) {
        gameState.setVariable(
          '_internal_stop_sound_target',
          audioId.toString(),
        );
        _log("   ⏹ Stop sound: $audioId");
      }
    } else if (type == 'play_music') {
      final audioId = block['audio_id'];
      final rawVolume = block['volume'] ?? 1.0;
      final loop = block['loop'] ?? true;
      final global = block['global'] ?? false;
      final evaluatedVolume = evaluateExpression(rawVolume, gameState);
      final volumeValue = (evaluatedVolume is num)
          ? evaluatedVolume.toDouble()
          : double.tryParse(evaluatedVolume?.toString() ?? '1.0');
      final clampedVolume = (volumeValue ?? 1.0).clamp(0.0, 1.0);

      if (audioId != null) {
        gameState.setVariable('_internal_play_music_volume', clampedVolume);
        gameState.setVariable('_internal_play_music_loop', loop);
        gameState.setVariable('_internal_play_music_global', global);
        gameState.setVariable('_internal_play_music_id', audioId.toString());
        _log(
          "   🎵 Play music: $audioId (Vol: $clampedVolume, Loop: $loop, Global: $global)",
        );
      }
    } else if (type == 'stop_music') {
      gameState.setVariable('_internal_stop_music', true);
      _log("   ⏹ Stop music");
    } else if (type == 'pause_resume') {
      final target = block['target'] ?? 'all';
      final action = block['action'] ?? 'toggle';

      gameState.setVariable('_internal_pause_resume_target', target);
      gameState.setVariable('_internal_pause_resume_action', action);
      _log("   ⏸ Pause/Resume: target=$target, action=$action");
    } else if (type == 'crossfade') {
      final rawDuration = block['duration'] ?? '2';
      final evaluatedDuration = evaluateExpression(rawDuration, gameState);
      final durationValue = (evaluatedDuration is num)
          ? evaluatedDuration.toDouble()
          : double.tryParse(evaluatedDuration?.toString() ?? '2.0');
      final durationMs = ((durationValue ?? 2.0) * 1000).round();

      _log("   🎵 Crossfade start (Duration: ${durationValue ?? 2.0}s)");

      gameState.setVariable('_internal_crossfade_fade_out', durationMs);
      await Future.delayed(Duration(milliseconds: durationMs));

      final children = block['children'] as List<dynamic>? ?? [];
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          final res = await _executeBlockRecursively(
            child,
            gameState,
            controller,
            questId,
          );
          if (res != null) return res;
        }
      }

      gameState.setVariable('_internal_crossfade_fade_in', durationMs);
      await Future.delayed(Duration(milliseconds: durationMs));

      _log("   🎵 Crossfade complete");
    }

    return null;
  }

  static List<dynamic> _parsePath(String path) {
    if (path.isEmpty) return [];

    // Используем тот же ручной парсер для извлечения ключей из пути
    // Это простой вариант, разбивающий по точкам и скобкам
    // В идеале стоит унифицировать логику, но для table_operation path часто приходит уже вычисленной строкой.

    final List<dynamic> keys = [];
    final regExp = RegExp(
      r'''\.?([a-zA-Zа-яА-ЯёЁ0-9_]+)|\["([^"]+)"\]|\['([^']+)'\]|\[(\d+)\]|'([^']+)'|"([^"]+)"''',
    );

    final matches = regExp.allMatches(path);

    for (final match in matches) {
      if (match.group(1) != null) {
        final val = match.group(1)!;
        keys.add(int.tryParse(val) ?? val);
      } else if (match.group(2) != null) {
        keys.add(match.group(2)!);
      } else if (match.group(3) != null) {
        keys.add(match.group(3)!);
      } else if (match.group(4) != null) {
        keys.add(int.parse(match.group(4)!));
      } else if (match.group(5) != null) {
        keys.add(match.group(5)!);
      } else if (match.group(6) != null) {
        keys.add(match.group(6)!);
      }
    }
    return keys;
  }

  static dynamic _getValueAtPath(dynamic root, List<dynamic> keys) {
    dynamic current = root;
    for (var key in keys) {
      if (current is Map) {
        current = current[key];
      } else if (current is List && key is int) {
        if (key >= 0 && key < current.length) {
          current = current[key];
        } else {
          return null;
        }
      } else {
        return null;
      }
      if (current == null) return null;
    }
    return current;
  }

  static void _setValueAtPath(dynamic root, List<dynamic> keys, dynamic value) {
    dynamic current = root;
    for (int i = 0; i < keys.length - 1; i++) {
      var key = keys[i];
      var nextKey = keys[i + 1];

      if (current is Map) {
        if (!current.containsKey(key) || current[key] == null) {
          current[key] = (nextKey is int) ? <dynamic>[] : <String, dynamic>{};
        }
        current = current[key];
      } else if (current is List && key is int) {
        if (key >= 0 && key < current.length) {
          current = current[key];
        } else {
          return;
        }
      } else {
        return;
      }
    }

    var lastKey = keys.last;
    if (current is Map) {
      current[lastKey] = value;
    } else if (current is List && lastKey is int) {
      if (lastKey >= 0 && lastKey < current.length) {
        current[lastKey] = value;
      } else if (lastKey == current.length) {
        current.add(value);
      }
    }
  }
}

class ExecutionController {
  int _steps = 0;
  final int _maxSteps;
  ExecutionController({int maxSteps = 2000}) : _maxSteps = maxSteps;
  void tick() {
    _steps++;
    if (_steps > _maxSteps) throw Exception("Script limit exceeded.");
  }
}
