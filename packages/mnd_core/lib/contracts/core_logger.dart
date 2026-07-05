/// Минимальный логгер ядра. По умолчанию — silent.
/// Приложение может подключить любую реализацию (talker, logger, print).
abstract class CoreLogger {
  void debug(String message);
  void info(String message);
  void warn(String message);
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

class SilentCoreLogger implements CoreLogger {
  const SilentCoreLogger();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

class PrintCoreLogger implements CoreLogger {
  const PrintCoreLogger({this.debugEnabled = false});

  final bool debugEnabled;

  @override
  // ignore: avoid_print
  void debug(String message) {
    if (debugEnabled) print('[mnd_core][debug] $message');
  }

  @override
  // ignore: avoid_print
  void info(String message) => print('[mnd_core][info]  $message');

  @override
  // ignore: avoid_print
  void warn(String message) => print('[mnd_core][warn]  $message');

  @override
  // ignore: avoid_print
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[mnd_core][error] $message${error != null ? ' :: $error' : ''}');
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }
}
