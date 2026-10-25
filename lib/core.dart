import 'dart:convert';
import 'package:flutter/services.dart';

/// Bridge to the native side (libXray + VpnService).
class Core {
  static const _ch = MethodChannel('dastras/core');

  /// Calls libXray's single entry point (apiVersion 3).
  static Future<Map<String, dynamic>> invoke(
      String method, Map<String, dynamic> payload) async {
    final req = jsonEncode({'apiVersion': 3, 'method': method, 'payload': payload});
    final res = await _ch.invokeMethod<String>('invoke', req);
    try {
      return Map<String, dynamic>.from(jsonDecode(res ?? '{}') as Map);
    } catch (_) {
      return {'success': false, 'error': res ?? 'empty response'};
    }
  }

  static Future<String> start(String config) async =>
      (await _ch.invokeMethod<String>('start', config)) ?? 'error';

  static Future<void> stop() => _ch.invokeMethod('stop');

  static Future<String> status() async =>
      (await _ch.invokeMethod<String>('status')) ?? 'stopped';
}
