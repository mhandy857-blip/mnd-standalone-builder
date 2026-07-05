import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformPerformance {
  static PlatformPerformance? _instance;
  static PlatformPerformance get instance {
    _instance ??= PlatformPerformance._();
    return _instance!;
  }

  PlatformPerformance._();

  bool? _shouldDisableBlur;
  bool? _userPreference;

  Future<bool> shouldDisableBlur() async {
    if (_userPreference != null) {
      return _userPreference!;
    }

    if (_shouldDisableBlur != null) {
      return _shouldDisableBlur!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('disable_blur_effects');
      if (saved != null) {
        _userPreference = saved;
        return saved;
      }
    } catch (_) {}

    _shouldDisableBlur = _detectShouldDisableBlur();
    return _shouldDisableBlur!;
  }

  bool _detectShouldDisableBlur() {
    if (kIsWeb) return false;

    if (Platform.isLinux) {
      if (kDebugMode) {
        print(
          '🐧 [Performance] Linux detected - blur may cause performance issues',
        );
      }
      return true;
    }

    if (Platform.isWindows) {
      return false;
    }

    return false;
  }

  Future<void> setBlurEnabled(bool enabled) async {
    _userPreference = !enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('disable_blur_effects', !enabled);
    } catch (_) {}
  }

  Future<double> getOptimalBlurSigma(double requestedSigma) async {
    if (await shouldDisableBlur()) {
      return 0.0;
    }

    if (!kIsWeb && Platform.isLinux) {
      return requestedSigma / 2;
    }

    return requestedSigma;
  }

  Future<bool> shouldUseShadows() async {
    if (await shouldDisableBlur()) {
      return false;
    }
    return true;
  }

  int getTargetFPS() {
    if (kIsWeb) return 60;
    if (!kIsWeb && Platform.isLinux) return 60;
    return 60;
  }

  String getPlatformInfo() {
    if (kIsWeb) return 'Web';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }
}
