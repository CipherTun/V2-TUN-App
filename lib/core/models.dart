import 'dart:convert';
import 'dart:ui';

class Subscription {
  Subscription({required this.id, required this.name, required this.url, this.updated});
  final String id;
  String name, url;
  DateTime? updated;
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'url': url, 'updated': updated?.toIso8601String()};
  factory Subscription.fromMap(Map<String, dynamic> m) => Subscription(
      id: m['id'], name: m['name'], url: m['url'], updated: m['updated'] == null ? null : DateTime.tryParse(m['updated']));
}

enum ConnState { disconnected, connecting, connected, disconnecting }

class Profile {
  Profile({required this.id, required this.name, required this.json, this.pingMs, this.subId});
  final String id;
  String name;
  String json; // a config for the tunnel library
  int? pingMs;
  String? subId; // set when the config came from a subscription

  String get protocol {
    try {
      return (jsonDecode(json)['protocol'] ?? '?').toString();
    } catch (_) {
      return '?';
    }
  }

  String get server {
    try {
      final m = jsonDecode(json);
      return '${m['server']}:${m['port']}';
    } catch (_) {
      return '';
    }
  }

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'json': json, 'ping': pingMs, 'sub': subId};
  factory Profile.fromMap(Map<String, dynamic> m) =>
      Profile(id: m['id'], name: m['name'], json: m['json'], pingMs: m['ping'], subId: m['sub']);
}

class LogLine {
  LogLine(this.level, this.text) : time = DateTime.now();
  final String level; // I, W, E
  final String text;
  final DateTime time;
}

/// Everything the Settings screen edits. Persisted as one JSON blob.
class Settings {
  Settings({
    this.accentIndex = 0,
    this.customAccent = 0xFF8AB4F8,
    // tunnel library
    this.mode = 'tun', // tun | socks
    this.mtu = 1500,
    this.dns = '1.1.1.1:53',
    this.fakeDns = false,
    this.sniff = false,
    this.socksListen = '127.0.0.1:10808',
    this.socksUser = '',
    this.socksPass = '',
    this.bypassLan = true,
    this.blockQuic = false,
    this.blockBittorrent = false,
    this.routeDefault = 'proxy',
    this.domainStrategy = 'ipifnonmatch',
    this.splitMode = 'off', // off | bypass | only (domains / ips)
    this.splitDomains = '',
    this.splitIps = '',
    this.directDns = '1.1.1.1:53',
    this.failoverTimeoutSec = 12,
    this.latencySortSec = 0,
    this.wsPingSec = 0,
    this.idleTimeoutSec = 0,
    // android vpn service
    this.appMode = 'all', // all | allow | disallow
    List<String>? apps,
    this.excludeSelf = true,
    this.metered = false,
    // app only
    this.autoConnect = false,
    this.reconnectOnDrop = true,
    this.reconnectDelaySec = 5,
    this.reduceMotion = false,
    this.haptics = true,
    this.keepScreenOn = false,
    this.logLimit = 500,
    this.pingUrl = 'https://www.gstatic.com/generate_204',
    this.autoFastest = false,
    this.useBackups = false,
    this.connectionCheck = true,
    this.subRefreshHours = 12,
  }) : apps = apps ?? <String>[];

  int accentIndex; // 0..6 presets, 7 = custom
  int customAccent;
  String mode;
  int mtu;
  String dns;
  bool fakeDns, sniff;
  String socksListen, socksUser, socksPass;
  bool bypassLan, blockQuic, blockBittorrent;
  String routeDefault, domainStrategy;
  String splitMode, splitDomains, splitIps;
  String directDns;
  int failoverTimeoutSec, latencySortSec, wsPingSec, idleTimeoutSec;
  String appMode;
  final List<String> apps;
  bool excludeSelf, metered;
  bool autoConnect, reconnectOnDrop;
  int reconnectDelaySec;
  bool reduceMotion, haptics, keepScreenOn;
  int logLimit;
  String pingUrl;
  bool autoFastest, useBackups, connectionCheck;
  int subRefreshHours;


  Map<String, Object?> toMap() => {
        'accentIndex': accentIndex, 'customAccent': customAccent, 'mode': mode, 'mtu': mtu, 'dns': dns,
        'fakeDns': fakeDns, 'sniff': sniff, 'socksListen': socksListen, 'socksUser': socksUser,
        'socksPass': socksPass, 'bypassLan': bypassLan, 'blockQuic': blockQuic,
        'blockBittorrent': blockBittorrent, 'routeDefault': routeDefault, 'domainStrategy': domainStrategy,
        'splitMode': splitMode, 'splitDomains': splitDomains, 'splitIps': splitIps, 'directDns': directDns,
        'failoverTimeoutSec': failoverTimeoutSec, 'latencySortSec': latencySortSec, 'wsPingSec': wsPingSec,
        'idleTimeoutSec': idleTimeoutSec, 'appMode': appMode, 'apps': apps, 'excludeSelf': excludeSelf,
        'metered': metered, 'autoConnect': autoConnect, 'reconnectOnDrop': reconnectOnDrop,
        'reconnectDelaySec': reconnectDelaySec, 'reduceMotion': reduceMotion, 'haptics': haptics,
        'keepScreenOn': keepScreenOn, 'logLimit': logLimit, 'pingUrl': pingUrl, 'autoFastest': autoFastest, 'useBackups': useBackups,
        'connectionCheck': connectionCheck, 'subRefreshHours': subRefreshHours,
      };

  factory Settings.fromMap(Map<String, dynamic> m) {
    final d = Settings();
    T g<T>(String k, T def) => m[k] is T ? m[k] as T : def;
    return Settings(
      accentIndex: g('accentIndex', d.accentIndex), customAccent: g('customAccent', d.customAccent),
      mode: g('mode', d.mode), mtu: g('mtu', d.mtu), dns: g('dns', d.dns), fakeDns: g('fakeDns', d.fakeDns),
      sniff: g('sniff', d.sniff), socksListen: g('socksListen', d.socksListen),
      socksUser: g('socksUser', d.socksUser), socksPass: g('socksPass', d.socksPass),
      bypassLan: g('bypassLan', d.bypassLan), blockQuic: g('blockQuic', d.blockQuic),
      blockBittorrent: g('blockBittorrent', d.blockBittorrent), routeDefault: g('routeDefault', d.routeDefault),
      domainStrategy: g('domainStrategy', d.domainStrategy), splitMode: g('splitMode', d.splitMode),
      splitDomains: g('splitDomains', d.splitDomains), splitIps: g('splitIps', d.splitIps),
      directDns: g('directDns', d.directDns), failoverTimeoutSec: g('failoverTimeoutSec', d.failoverTimeoutSec),
      latencySortSec: g('latencySortSec', d.latencySortSec), wsPingSec: g('wsPingSec', d.wsPingSec),
      idleTimeoutSec: g('idleTimeoutSec', d.idleTimeoutSec), appMode: g('appMode', d.appMode),
      apps: ((m['apps'] as List?)?.cast<String>() ?? <String>[]).toList(), excludeSelf: g('excludeSelf', d.excludeSelf),
      metered: g('metered', d.metered), autoConnect: g('autoConnect', d.autoConnect),
      reconnectOnDrop: g('reconnectOnDrop', d.reconnectOnDrop),
      reconnectDelaySec: g('reconnectDelaySec', d.reconnectDelaySec), reduceMotion: g('reduceMotion', d.reduceMotion),
      haptics: g('haptics', d.haptics), keepScreenOn: g('keepScreenOn', d.keepScreenOn),
      logLimit: g('logLimit', d.logLimit), pingUrl: g('pingUrl', d.pingUrl),
      autoFastest: g('autoFastest', d.autoFastest), useBackups: g('useBackups', d.useBackups),
      connectionCheck: g('connectionCheck', d.connectionCheck), subRefreshHours: g('subRefreshHours', d.subRefreshHours),
    );
  }
}
