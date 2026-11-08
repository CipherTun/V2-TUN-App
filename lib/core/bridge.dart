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
  static Future<String> validate(String json) async => (await _m.invokeMethod<String>('validate', {'config': json})) ?? '';
  static Future<int> ping(String json, String url) async => (await _m.invokeMethod<int>('ping', {'config': json, 'url': url})) ?? -1;
  static Future<String> speedTest(String json, int seconds) async =>
      (await _m.invokeMethod<String>('speedTest', {'config': json, 'seconds': seconds}))!;
  static Future<String> scanHosts(String json, String field, String values, String target, int jobs, int seconds) async =>
      (await _m.invokeMethod<String>('scanHosts', {
        'config': json, 'field': field, 'values': values, 'target': target, 'jobs': jobs, 'seconds': seconds,
      }))!;
  static Future<String> payloadPreview(String json) async => (await _m.invokeMethod<String>('payloadPreview', {'config': json}))!;
  static Future<String> previewPayload(String template, String host, int port) async =>
      (await _m.invokeMethod<String>('previewPayload', {'template': template, 'host': host, 'port': port}))!;
  static Future<String> validatePayload(String template) async =>
      (await _m.invokeMethod<String>('validatePayload', {'template': template})) ?? '';
  static Future<List<String>> payloadPresets() async =>
      ((await _m.invokeMethod<String>('payloadPresets')) ?? '').split('\n').where((e) => e.isNotEmpty).toList();
  static Future<String> explainRoute(String network, String addr, String protocol) async =>
      (await _m.invokeMethod<String>('explainRoute', {'network': network, 'addr': addr, 'protocol': protocol}))!;
  static Future<void> updateRouting(String routingJson) => _m.invokeMethod('updateRouting', {'routing': routingJson});
  static Future<void> setRouteList(String name, String items) =>
      _m.invokeMethod('setRouteList', {'name': name, 'items': items});
  static Future<int> activeOutbound() async => (await _m.invokeMethod<int>('activeOutbound')) ?? -1;
  static Future<void> resetTraffic() => _m.invokeMethod('resetTraffic');
  static Future<List<Map<dynamic, dynamic>>> installedApps() async =>
      ((await _m.invokeMethod<List<dynamic>>('installedApps')) ?? []).cast<Map<dynamic, dynamic>>();
  static Future<void> openVpnSettings() => _m.invokeMethod('openVpnSettings');
  static Future<void> keepScreenOn(bool on) => _m.invokeMethod('keepScreenOn', {'on': on});
}
