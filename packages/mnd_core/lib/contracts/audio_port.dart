/// Порт воспроизведения звука/музыки квеста.
///
/// Реализуется приложением поверх любого аудио-движка (just_audio, soloud,
/// audioplayers, веб-аудио и т.п.).
abstract class AudioPort {
  Future<void> playSound(String path, {double volume = 1.0});
  Future<void> playMusic(String path, {bool loop = true, double volume = 1.0});
  Future<void> stop();
  Future<void> stopAll();
  Future<void> dispose();
}

/// No-op реализация: ничего не воспроизводит. Удобна для тестов и
/// окружений без аудио.
class NoopAudioPort implements AudioPort {
  const NoopAudioPort();

  @override
  Future<void> playSound(String path, {double volume = 1.0}) async {}

  @override
  Future<void> playMusic(
    String path, {
    bool loop = true,
    double volume = 1.0,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<void> dispose() async {}
}
