import 'package:flutter/services.dart';

// Screen brightness, keep-awake and volume-key page turns while a book is open (Android).
// Each call is best-effort: a missing channel (tests, other platforms) is ignored.
class DeviceControls {
  DeviceControls({required this.onVolumeKey}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') onVolumeKey(call.arguments == true);
    });
  }

  static const _channel = MethodChannel('app.quill/reader');
  final void Function(bool forward) onVolumeKey;

  Future<void> _call(String method, Object? value) async {
    try {
      await _channel.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // Not available on this platform.
    } on PlatformException {
      // Ignore: these are conveniences, never required to read.
    }
  }

  // null hands brightness back to the system.
  Future<void> brightness(double? value) => _call('brightness', value ?? -1.0);
  Future<double> systemBrightness() async {
    try {
      return await _channel.invokeMethod<double>('systemBrightness') ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  // Battery level 0–100, or null when unknown.
  Future<int?> battery() async {
    try {
      return await _channel.invokeMethod<int>('battery');
    } catch (_) {
      return null;
    }
  }

  Future<void> keepAwake(bool on) => _call('keepAwake', on);
  Future<void> volumeKeys(bool on) => _call('volumeKeys', on);

  // Leaving the reader restores the system's behaviour.
  Future<void> release() async {
    _channel.setMethodCallHandler(null);
    await Future.wait([brightness(null), keepAwake(false), volumeKeys(false)]);
  }
}
