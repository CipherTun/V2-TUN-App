import 'dart:async';
import 'package:flutter/services.dart';

/// Thin wrapper over the Kotlin side (MainActivity + V2TunVpnService).
class Bridge {
  static const _m = MethodChannel('io.surprise.vpn/core');
  static const _e = EventChannel('io.surprise.vpn/events');

  /// Events: {type: state|log|traffic, ...}
  static Stream<Map<dynamic, dynamic>> get events =>
      _e.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);

  static Future<bool> prepareVpn() async => (await _m.invokeMethod<bool>('prepareVpn')) ?? false;
  static Future<void> start(String configJson, Map<String, Object?> opts) =>
      _m.invokeMethod('start', {'config': configJson, 'opts': opts});
  static Future<void> stop() => _m.invokeMethod('stop');
  static Future<bool> isRunning() async => (await _m.invokeMethod<bool>('isRunning')) ?? false;

  static Future<String> parseLink(String link) async => (await _m.invokeMethod<String>('parseLink', {'link': link}))!;
  /// The standard share link of a config. Throws when the config has none (SSH, a payload, ...).
  static Future<String> shareLink(String configJson, String name) async =>
      (await _m.invokeMethod<String>('shareLink', {'config': configJson, 'name': name}))!;
  static Future<String> validate(String json) async => (await _m.invokeMethod<String>('validate', {'config': json})) ?? '';
  static Future<int> ping(String json, String url) async => (await _m.invokeMethod<int>('ping', {'config': json, 'url': url})) ?? -1;
  static Future<String> speedTest(String json, int seconds) async =>
      (await _m.invokeMethod<String>('speedTest', {'config': json, 'seconds': seconds}))!;
  static Future<String> scanHosts(String json, String field, String values, String target, int jobs, int seconds) async =>
      (await _m.invokeMethod<String>('scanHosts', {
        'config': json, 'field': field, 'values': values, 'target': target, 'jobs': jobs, 'seconds': seconds,
      }))!;
  /// Tests a config one layer at a time (DNS, TCP, payload and reply, TLS, SSH banner, a real request).
  /// Returns JSON: {ok, summary, stages: [{name, ok, ms, detail, raw, error}]}.
  static Future<String> diagnose(String json, int seconds) async =>
      (await _m.invokeMethod<String>('diagnose', {'config': json, 'seconds': seconds}))!;
  static Future<String> payloadPreview(String json) async => (await _m.invokeMethod<String>('payloadPreview', {'config': json}))!;
  static Future<String> previewPayload(String template, String host, String server, int port) async =>
      (await _m.invokeMethod<String>('previewPayload', {'template': template, 'host': host, 'server': server, 'port': port}))!;
  static Future<String> validatePayload(String template) async =>
      (await _m.invokeMethod<String>('validatePayload', {'template': template})) ?? '';
  static Future<String> explainRoute(String network, String addr, String protocol) async =>
      (await _m.invokeMethod<String>('explainRoute', {'network': network, 'addr': addr, 'protocol': protocol}))!;
  static Future<void> updateRouting(String routingJson) => _m.invokeMethod('updateRouting', {'routing': routingJson});
  static Future<void> setRouteList(String name, String items) =>
      _m.invokeMethod('setRouteList', {'name': name, 'items': items});
  static Future<int> activeOutbound() async => (await _m.invokeMethod<int>('activeOutbound')) ?? -1;
  static Future<void> resetTraffic() => _m.invokeMethod('resetTraffic');
  /// How much the tunnel library logs: 'info' (default) or 'debug'.
  static Future<void> setLogLevel(String level) => _m.invokeMethod('setLogLevel', {'level': level});
  static Future<List<Map<dynamic, dynamic>>> installedApps() async =>
      ((await _m.invokeMethod<List<dynamic>>('installedApps')) ?? []).cast<Map<dynamic, dynamic>>();
  static Future<void> openVpnSettings() => _m.invokeMethod('openVpnSettings');
  static Future<void> keepScreenOn(bool on) => _m.invokeMethod('keepScreenOn', {'on': on});

  /// Opens the system share sheet with [text].
  static Future<void> shareText(String text, {String title = 'Share'}) =>
      _m.invokeMethod('shareText', {'text': text, 'title': title});

  /// Encrypted storage backed by the Android Keystore. [vaultGet] gives null when nothing is stored.
  static Future<void> vaultPut(String key, String value) => _m.invokeMethod('vaultPut', {'key': key, 'value': value});
  static Future<String?> vaultGet(String key) => _m.invokeMethod<String>('vaultGet', {'key': key});
}
