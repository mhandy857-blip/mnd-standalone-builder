import 'package:meta/meta.dart';
import 'package:mnd_core/contracts/audio_port.dart';
import 'package:mnd_core/contracts/core_logger.dart';
import 'package:mnd_core/contracts/save_store.dart';
import 'package:mnd_core/contracts/script_asset_store.dart';
import 'package:mnd_core/contracts/script_expression_engine.dart';
import 'package:mnd_core/engine/script_executor.dart';

/// Точка входа конфигурации ядра. Приложение (main_app, quest_player,
/// сервер и т.п.) собирает свои реализации портов и передаёт их сюда
/// единожды на старте.
///
/// Пример (Flutter):
/// ```dart
/// MndCore.initialize(
///   expressionEngine: FlutterExpressionsEngine(),
///   assetStore: FlutterAssetStore(),
///   saveStore: FilesystemSaveStore(),
///   logger: const PrintCoreLogger(debugEnabled: kDebugMode),
/// );
/// ```
class MndCore {
  MndCore._({
    required this.expressionEngine,
    required this.assetStore,
    required this.saveStore,
    required this.audio,
    required this.logger,
    required this.debugLogs,
  });

  static MndCore? _instance;

  /// Единственный сконфигурированный инстанс. Доступен после
  /// вызова [initialize]. До этого обращение бросает [StateError].
  static MndCore get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'MndCore is not initialized. Call MndCore.initialize(...) '
        'during app bootstrap before using the engine.',
      );
    }
    return i;
  }

  /// Был ли вызван [initialize].
  static bool get isInitialized => _instance != null;

  final ScriptExpressionEngine expressionEngine;
  final ScriptAssetStore assetStore;
  final SaveStore? saveStore;
  final AudioPort audio;
  final CoreLogger logger;
  final bool debugLogs;

  /// Полная инициализация. Безопасно вызывать только один раз —
  /// повторный вызов будет проигнорирован, если [allowReinit] = false.
  static void initialize({
    required ScriptExpressionEngine expressionEngine,
    required ScriptAssetStore assetStore,
    SaveStore? saveStore,
    AudioPort? audio,
    CoreLogger? logger,
    bool debugLogs = false,
    bool allowReinit = false,
  }) {
    if (_instance != null && !allowReinit) return;
    final core = MndCore._(
      expressionEngine: expressionEngine,
      assetStore: assetStore,
      saveStore: saveStore,
      audio: audio ?? const NoopAudioPort(),
      logger: logger ?? const SilentCoreLogger(),
      debugLogs: debugLogs,
    );
    _instance = core;

    // Прокидываем устаревшую статическую конфигурацию ScriptExecutor,
    // чтобы код, ходящий через статические методы, продолжал работать.
    ScriptExecutor.configure(
      expressionEngine: expressionEngine,
      assetStore: assetStore,
      logger: logger == null ? null : (msg) => logger.debug(msg),
      debugLogsEnabled: debugLogs,
    );
  }

  /// Только для тестов: сбросить состояние перед перенастройкой.
  @visibleForTesting
  static void reset() {
    _instance = null;
  }
}
