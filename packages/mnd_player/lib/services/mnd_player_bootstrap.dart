import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:expressions/expressions.dart' as expressions;

class MndPlayerBootstrap {
  static void initialize({bool debugLogs = false}) {
    ScriptExecutor.configure(
      expressionEngine: _AppExpressionEngine(),
      assetStore: _AppAssetStore(),
      debugLogsEnabled: debugLogs,
    );
  }
}

class _AppExpressionEngine implements ScriptExpressionEngine {
  @override
  dynamic evaluate(String expression, Map<String, dynamic> context) {
    return _evaluateExpression(expression, context);
  }
}

class _AppAssetStore implements ScriptAssetStore {
  @override
  Future<bool> exists(String path) => FileStorage.exists(path);

  @override
  Future<Map<String, dynamic>> readJson(String path) =>
      FileStorage.readJsonFile(path);
}

dynamic _evaluateExpression(String expression, Map<String, dynamic> context) {
  if (expression.isEmpty) return expression;

  try {
    final resolved = _resolveVariables(expression, context);
    final parsed = expressions.Expression.parse(resolved);
    final evaluator = const expressions.ExpressionEvaluator();
    final result = evaluator.eval(parsed, context);
    if (result is num && result == result.toDouble().roundToDouble()) {
      return result.toInt();
    }
    return result;
  } catch (_) {
    return expression;
  }
}

final _variablePattern = RegExp(r'\{([^}]+)\}');

String _resolveVariables(String expression, Map<String, dynamic> context) {
  return expression.replaceAllMapped(_variablePattern, (match) {
    final varName = match.group(1)!;
    final value = context[varName];
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is bool) return value.toString();
    return value.toString();
  });
}
