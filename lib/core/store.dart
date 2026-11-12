import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bridge.dart';
import 'models.dart';

class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this.settings, this.profiles, this.selectedId, this.subs);

  final SharedPreferences _prefs;
  Settings settings;
  List<Profile> profiles;
  String? selectedId;
  List<Subscription> subs;
  int todayBytes = 0, lifetimeBytes = 0;
  String _day = '';

  ConnState state = ConnState.disconnected;
  String? error;
  final List<LogLine> logs = [];
  /// How much the tunnel library logs: 'info' (default) or 'debug' (every connection, DNS detail,
  /// the failover ranking). Kept apart from [settings] and applied to the library at once.
  String logLevel = 'info';
  int upBytes = 0, downBytes = 0;
  double upBps = 0, downBps = 0;
  /// The last 48 download rates, one per second, for the dashboard chart.
  final List<double> downHistory = List<double>.filled(48, 0, growable: true);
  DateTime? connectedAt;
  Timer? _reconnect;
  bool _userStopped = true;
  int _connectGen = 0; // changes on every connect and disconnect, so a connect in progress can tell it was cancelled
  int _lastUp = 0, _lastDown = 0;

  /// How long one latency test waits when picking the fastest config.
  static const _pingTimeout = Duration(seconds: 8);

  /// The scheme of a link that only V2-TUN reads and that keeps every setting of a config.
  static const nativeScheme = 'v2tun://';

  static Future<AppStore> load() async {
    final p = await SharedPreferences.getInstance();
    final settingsMap = (jsonDecode(p.getString('settings') ?? '{}') as Map).cast<String, dynamic>();
    final pass = await _readSecret(p, 'socksPass');
    if (pass != null) settingsMap['socksPass'] = pass;
    final s = Settings.fromMap(settingsMap);
    final profiles = ((jsonDecode((await _readSecret(p, 'profiles')) ?? '[]')) as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    final subs = ((jsonDecode((await _readSecret(p, 'subs')) ?? '[]')) as List)
        .map((e) => Subscription.fromMap(e as Map<String, dynamic>))
        .toList();
    final st = AppStore._(p, s, profiles, p.getString('selected'), subs);
    st.lifetimeBytes = p.getInt('lifetime') ?? 0;
    st._day = p.getString('usageDay') ?? '';
    st.todayBytes = st._day == st._today() ? (p.getInt('usageToday') ?? 0) : 0;
    st.logLevel = p.getString('logLevel') == 'debug' ? 'debug' : 'info';
    if (st.logLevel == 'debug') unawaited(Bridge.setLogLevel('debug').catchError((Object _) {}));
    // Moves anything an older version left in plain text into the encrypted store.
    st.saveSettings();
    st._saveSubs();
    st._saveProfiles();
    st._listen();
    unawaited(st._sync());
    unawaited(st.refreshDueSubscriptions());
    return st;
  }

  Profile? get selected {
    for (final p in profiles) {
      if (p.id == selectedId) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  // ---- secret storage ----------------------------------------------------
  // Configs hold passwords and keys, subscription URLs hold tokens, and the SOCKS listener has a
  // password. They are kept in the Android Keystore backed vault, never in plain preferences.

  /// The stored secret, from the vault or, for data an older version saved, from plain preferences.
  static Future<String?> _readSecret(SharedPreferences p, String key) async {
    try {
      final v = await Bridge.vaultGet(key);
      if (v != null) return v;
    } catch (_) {}
    return p.getString(key);
  }

  bool _vaultWarned = false;
  Future<void> _writes = Future<void>.value();

  /// Writes run one after another, so a slow older write can never land after a newer one.
  void _queue(Future<void> Function() job) {
    _writes = _writes.then((_) => job()).catchError((Object _) {});
  }

  Future<void> _writeSecret(String key, String value) async {
    try {
      await Bridge.vaultPut(key, value);
      await _prefs.remove(key); // no plain copy may stay behind
    } catch (e) {
      await _prefs.setString(key, value);
      if (!_vaultWarned) {
        _vaultWarned = true;
        log('W', 'Secure storage is unavailable ($e). Credentials are saved without encryption on this device.');
      }
    }
  }

  // ---- persistence -------------------------------------------------------
  void saveSettings() {
    final m = settings.toMap()..remove('socksPass');
    _prefs.setString('settings', jsonEncode(m));
    final pass = settings.socksPass;
    _queue(() => _writeSecret('socksPass', pass));
    notifyListeners();
  }

  void _saveProfiles() {
    final data = jsonEncode(profiles.map((e) => e.toMap()).toList());
    _queue(() => _writeSecret('profiles', data));
    if (selectedId != null) _prefs.setString('selected', selectedId!);
    notifyListeners();
  }

  void addProfile(String name, String json) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    profiles.add(Profile(id: id, name: name, json: json));
    selectedId ??= id;
    _saveProfiles();
  }

  void updateProfile(Profile p, {String? name, String? json}) {
    if (name != null) p.name = name;
    if (json != null) p.json = json;
    _saveProfiles();
  }

  void removeProfile(Profile p) {
    profiles.remove(p);
    if (selectedId == p.id) selectedId = profiles.isEmpty ? null : profiles.first.id;
    _saveProfiles();
  }

  /// Puts a removed profile back at its old position (the undo of a swipe-delete).
  void restoreProfile(Profile p, int index, {bool select = false}) {
    profiles.insert(index.clamp(0, profiles.length).toInt(), p);
    if (select) selectedId = p.id;
    _saveProfiles();
  }

  void select(Profile p) {
    selectedId = p.id;
    _saveProfiles();
  }

  void setPing(Profile p, int? ms) {
    p.pingMs = ms;
    _saveProfiles();
  }


  // ---- more profile tools ----------------------------------------------------
  void duplicateProfile(Profile p) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    profiles.add(Profile(id: id, name: '${p.name} copy', json: p.json));
    _saveProfiles();
  }

  /// Removes configs that are exactly the same as an earlier one. Returns how many were removed.
  int removeDuplicates() {
    Object? canon(Object? v) {
      if (v is Map) {
        final keys = v.keys.map((e) => '$e').toList()..sort();
        return {for (final k in keys) k: canon(v[k])};
      }
      if (v is List) return [for (final e in v) canon(e)];
      return v;
    }

    final seen = <String>{};
    final drop = <Profile>[];
    for (final p in profiles) {
      String key;
      try {
        key = jsonEncode(canon(jsonDecode(p.json)));
      } catch (_) {
        key = p.json;
      }
      if (!seen.add(key)) drop.add(p);
    }
    if (drop.isEmpty) return 0;
    profiles.removeWhere(drop.contains);
    if (!profiles.any((p) => p.id == selectedId)) selectedId = profiles.isEmpty ? null : profiles.first.id;
    _saveProfiles();
    return drop.length;
  }

  void sortByPing() {
    int k(Profile p) => p.pingMs == null ? 1 << 30 : (p.pingMs! < 0 ? 1 << 29 : p.pingMs!);
    profiles.sort((a, b) => k(a).compareTo(k(b)));
    _saveProfiles();
  }

  /// Pings every config, then selects the quickest. Returns it, or null when none answered
  /// (or [cancelled] said to stop). Each test is cut off after [_pingTimeout].
  Future<Profile?> pickFastest({bool Function()? cancelled}) async {
    Profile? best;
    for (final p in List.of(profiles)) {
      if (cancelled?.call() ?? false) {
        _saveProfiles();
        return null;
      }
      try {
        p.pingMs = await Bridge.ping(buildConfig(p), settings.pingUrl).timeout(_pingTimeout);
      } catch (_) {
        p.pingMs = -1;
      }
      if (p.pingMs! >= 0 && (best == null || p.pingMs! < best.pingMs!)) best = p;
      notifyListeners();
    }
    if (cancelled?.call() ?? false) {
      _saveProfiles();
      return null;
    }
    if (best != null) selectedId = best.id;
    _saveProfiles();
    return best;
  }

  // ---- import and share ---------------------------------------------------
  /// A link only V2-TUN reads: the whole config, with every setting, in one string.
  static String encodeNativeLink(Profile p) {
    final body = jsonEncode({'v': 1, 'name': p.name, 'config': jsonDecode(p.json)});
    return nativeScheme + base64Url.encode(utf8.encode(body)).replaceAll('=', '');
  }

  /// The name and the config JSON inside a V2-TUN link. Throws when it is not one.
  static (String, String) decodeNativeLink(String link) {
    final body = link.trim().substring(nativeScheme.length);
    final m = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body)))) as Map<String, dynamic>;
    final cfg = m['config'];
    if (cfg is! Map) throw 'not a V2-TUN link';
    final name = (m['name'] as String?)?.trim() ?? '';
    return (name.isEmpty ? 'Imported config' : name, jsonEncode(cfg));
  }

  /// The standard share link of a profile (vless://, vmess://, ...), or null when it has none.
  Future<String?> standardLink(Profile p) async {
    try {
      return await Bridge.shareLink(p.json, p.name);
    } catch (_) {
      return null;
    }
  }

  /// Imports what the text holds: share links (also V2-TUN links), or JSON configs, one per
  /// line or one pretty-printed. Returns how many configs were added.
  Future<int> importText(String raw) async {
    final text = raw.trim();
    var added = 0;
    var handled = false;
    // A whole JSON config (also over many lines) or a JSON list of configs.
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final v = jsonDecode(text);
        for (final item in v is List ? v : [v]) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final name = (m.remove('name') as String?)?.trim();
          addProfile(name?.isNotEmpty == true ? name! : 'Config ${profiles.length + 1}', jsonEncode(m));
          added++;
        }
        handled = true;
      } catch (_) {
        // not one JSON value: fall back to one entry per line below
      }
    }
    if (!handled) {
      for (final token in text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty)) {
        try {
          if (token.startsWith('{')) {
            jsonDecode(token);
            addProfile('Config ${profiles.length + 1}', token);
          } else if (token.toLowerCase().startsWith(nativeScheme)) {
            final (name, json) = decodeNativeLink(token);
            addProfile(name, json);
          } else {
            final m = jsonDecode(await Bridge.parseLink(token)) as Map<String, dynamic>;
            final name = (m.remove('name') as String?)?.trim();
            addProfile(name?.isNotEmpty == true ? name! : 'Config ${profiles.length + 1}', jsonEncode(m));
          }
          added++;
        } catch (e) {
          log('W', 'Import skipped: $e');
        }
      }
    }
    return added;
  }

  // ---- subscriptions ---------------------------------------------------------
  void _saveSubs() {
    final data = jsonEncode(subs.map((e) => e.toMap()).toList());
    _queue(() => _writeSecret('subs', data));
    notifyListeners();
  }

  Future<int> addSubscription(String name, String url) async {
    final sub = Subscription(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, url: url);
    subs.add(sub);
    _saveSubs();
    return refreshSubscription(sub);
  }

  void removeSubscription(Subscription s, {bool withConfigs = true}) {
    subs.remove(s);
    if (withConfigs) profiles.removeWhere((p) => p.subId == s.id);
    if (selected == null) selectedId = null;
    _saveSubs();
    _saveProfiles();
  }

  /// A profile id that stays the same for the same share link, so a refresh keeps the selection
  /// and the latency of the servers that are still in the list (FNV-1a of the link).
  String _linkId(String subId, String link) {
    var h = 0x811c9dc5;
    for (final c in link.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return '$subId-${h.toRadixString(16)}';
  }

  /// Downloads a subscription (plain or base64 list of share links) and replaces its configs.
  Future<int> refreshSubscription(Subscription sub) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(Uri.parse(sub.url));
      req.headers.set('User-Agent', 'V2-TUN/1.0');
      final res = await req.close().timeout(const Duration(seconds: 30));
      var body = (await res.transform(utf8.decoder).join()).trim();
      if (!body.contains('://')) {
        try {
          body = utf8.decode(base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))));
        } catch (_) {}
      }
      final oldPing = {for (final p in profiles) if (p.subId == sub.id) p.id: p.pingMs};
      final fresh = <Profile>[];
      for (final line in body.split(RegExp(r'\s+')).where((e) => e.contains('://'))) {
        try {
          final id = _linkId(sub.id, line);
          if (fresh.any((f) => f.id == id)) continue; // the same link twice
          final m = jsonDecode(await Bridge.parseLink(line)) as Map<String, dynamic>;
          final name = (m.remove('name') as String?)?.trim();
          fresh.add(Profile(
              id: id,
              name: name?.isNotEmpty == true ? name! : '${sub.name} ${fresh.length + 1}',
              json: jsonEncode(m),
              pingMs: oldPing[id],
              subId: sub.id));
        } catch (e) {
          log('W', 'Subscription "${sub.name}": skipped a link ($e)');
        }
      }
      if (fresh.isEmpty) throw 'no usable links in the response';
      final oldSel = selectedId;
      profiles.removeWhere((p) => p.subId == sub.id);
      profiles.addAll(fresh);
      if (oldSel != null && !profiles.any((p) => p.id == oldSel)) selectedId = profiles.first.id;
      selectedId ??= profiles.first.id;
      sub.updated = DateTime.now();
      _saveSubs();
      _saveProfiles();
      log('I', 'Subscription "${sub.name}": ${fresh.length} configs');
      return fresh.length;
    } catch (e) {
      log('E', 'Subscription "${sub.name}" failed: $e');
      rethrow;
    } finally {
      c.close();
    }
  }

  Future<void> refreshDueSubscriptions() async {
    final h = settings.subRefreshHours;
    if (h <= 0) return;
    for (final s in List.of(subs)) {
      if (s.updated == null || DateTime.now().difference(s.updated!).inHours >= h) {
        try {
          await refreshSubscription(s);
        } catch (_) {}
      }
    }
  }

  // ---- usage -----------------------------------------------------------------
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  void _addUsage(int bytes) {
    if (bytes <= 0) return;
    if (_day != _today()) {
      _day = _today();
      todayBytes = 0;
    }
    todayBytes += bytes;
    lifetimeBytes += bytes;
    _prefs.setInt('usageToday', todayBytes);
    _prefs.setInt('lifetime', lifetimeBytes);
    _prefs.setString('usageDay', _day);
  }

  // ---- backup ----------------------------------------------------------------
  /// The backup file is plain JSON and holds every password and key: keep it somewhere private.
  String exportBackup() => jsonEncode({
        'v': 1,
        'settings': settings.toMap(),
        'profiles': profiles.map((e) => e.toMap()).toList(),
        'subs': subs.map((e) => e.toMap()).toList(),
      });

  void importBackup(String text) {
    final m = jsonDecode(text) as Map<String, dynamic>;
    settings = Settings.fromMap((m['settings'] as Map?)?.cast<String, dynamic>() ?? {});
    profiles = ((m['profiles'] as List?) ?? []).map((e) => Profile.fromMap((e as Map).cast<String, dynamic>())).toList();
    subs = ((m['subs'] as List?) ?? []).map((e) => Subscription.fromMap((e as Map).cast<String, dynamic>())).toList();
    selectedId = profiles.isEmpty ? null : profiles.first.id;
    saveSettings();
    _saveSubs();
    _saveProfiles();
  }

  /// Measures the latency of the config that just connected and shows it on its row. The
  /// service has already proved that traffic passes before it says "connected".
  Future<void> _healthCheck(Profile p, String cfg) async {
    if (!settings.connectionCheck) return;
    try {
      final ms = await Bridge.ping(cfg, settings.pingUrl);
      log('I', 'Latency test passed (${ms} ms)');
      setPing(p, ms);
    } catch (e) {
      log('W', 'Latency test failed: $e');
    }
  }

  // ---- logs --------------------------------------------------------------
  void log(String level, String text) {
    logs.add(LogLine(level, text));
    if (logs.length > settings.logLimit) logs.removeRange(0, logs.length - settings.logLimit);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  /// Sets how much the tunnel library logs ('info' or 'debug') and remembers it.
  void setLogLevel(String level) {
    logLevel = level == 'debug' ? 'debug' : 'info';
    _prefs.setString('logLevel', logLevel);
    unawaited(Bridge.setLogLevel(logLevel).catchError((Object _) {}));
    notifyListeners();
  }

  // ---- config assembly -----------------------------------------------------
  /// The profile's config with the app's tunnel settings merged in.
  String buildConfig(Profile p) {
    final m = jsonDecode(p.json) as Map<String, dynamic>;
    final s = settings;
    final routing = <String, dynamic>{...(m['routing'] as Map<String, dynamic>? ?? {})};
    routing['default'] = s.routeDefault;
    routing['domainStrategy'] = s.domainStrategy;
    routing['bypassLan'] = s.bypassLan;
    routing['blockQuic'] = s.blockQuic;
    routing['blockBittorrent'] = s.blockBittorrent;
    if (s.splitMode != 'off') {
      List<String> lines(String v) => v.split(RegExp(r'[\n,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      routing['split'] = {'mode': s.splitMode, 'domain': lines(s.splitDomains), 'ip': lines(s.splitIps)};
    }
    m['routing'] = routing; // must exist so UpdateRouting works while connected
    if (s.directDns.isNotEmpty) m['directDns'] = s.directDns;
    if (s.failoverTimeoutSec != 12) m['failoverTimeoutSec'] = s.failoverTimeoutSec;
    if (s.latencySortSec > 0) m['latencySortSec'] = s.latencySortSec;
    if (s.idleTimeoutSec > 0) m['idleTimeoutSec'] = s.idleTimeoutSec;
    if (s.wsPingSec > 0) {
      final ws = <String, dynamic>{...(m['ws'] as Map<String, dynamic>? ?? {})};
      ws['pingSec'] = s.wsPingSec;
      m['ws'] = ws;
    }
    if (s.useBackups) {
      final others = profiles.where((o) => o.id != p.id).take(4);
      final list = <Map<String, dynamic>>[];
      for (final o in others) {
        try {
          final b = jsonDecode(o.json) as Map<String, dynamic>;
          for (final k in ['routing', 'udpgw', 'directDns', 'backups']) {
            b.remove(k);
          }
          list.add(b);
        } catch (_) {}
      }
      if (list.isNotEmpty) m['backups'] = list;
    }
    return jsonEncode(m);
  }

  Map<String, Object?> nativeOptions() => {
        'mode': settings.mode,
        'mtu': settings.mtu,
        'dns': settings.dns,
        'fakeDns': settings.fakeDns,
        'sniff': settings.sniff,
        'listen': settings.socksListen,
        'user': settings.socksUser,
        'pass': settings.socksPass,
        'appMode': settings.appMode,
        'apps': settings.apps,
        'excludeSelf': settings.excludeSelf,
        'metered': settings.metered,
      };

  // ---- connection ----------------------------------------------------------
  Future<void> toggle() async {
    if (state == ConnState.connected || state == ConnState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    if (selected == null) {
      error = 'Add a config first';
      notifyListeners();
      return;
    }
    _reconnect?.cancel();
    final gen = ++_connectGen;
    bool stale() => gen != _connectGen; // disconnect() or a newer connect() ran meanwhile
    _userStopped = false;
    error = null;
    state = ConnState.connecting;
    notifyListeners();
    try {
      if (settings.autoFastest && profiles.length > 1) {
        log('I', 'Picking the fastest config');
        final f = await pickFastest(cancelled: stale);
        if (stale()) return;
        if (f != null) log('I', 'Fastest: "${f.name}" (${f.pingMs} ms)');
      }
      if (settings.mode == 'tun' && !await Bridge.prepareVpn()) {
        throw 'VPN permission was not granted';
      }
      if (stale()) return;
      final p = selected!;
      final cfg = buildConfig(p);
      final bad = await Bridge.validate(cfg);
      if (stale()) return;
      if (bad.isNotEmpty) throw bad;
      log('I', 'Connecting with "${p.name}" (${p.protocol}) in ${settings.mode} mode');
      await Bridge.start(cfg, nativeOptions());
      unawaited(_afterConnect(p, cfg));
    } catch (e) {
      if (stale()) return;
      state = ConnState.disconnected;
      error = e.toString();
      log('E', error!);
      notifyListeners();
    }
  }

  /// Waits for "connected" (the service first checks that traffic passes, up to 20 seconds)
  /// and then measures the latency.
  Future<void> _afterConnect(Profile p, String cfg) async {
    for (var i = 0; i < 70 && state == ConnState.connecting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (state == ConnState.connected) await _healthCheck(p, cfg);
  }

  Future<void> disconnect() async {
    _userStopped = true;
    _connectGen++; // ends a connect that is still preparing
    _reconnect?.cancel();
    state = ConnState.disconnecting;
    notifyListeners();
    await Bridge.stop();
  }

  Future<void> _sync() async {
    if (await Bridge.isRunning()) {
      state = ConnState.connected;
      connectedAt ??= DateTime.now();
      notifyListeners();
    } else if (settings.autoConnect && selected != null) {
      unawaited(connect());
    }
  }

  void _listen() {
    Bridge.events.listen((e) {
      switch (e['type']) {
        case 'state':
          final s = e['state'] as String;
          state = switch (s) {
            'connected' => ConnState.connected,
            'connecting' => ConnState.connecting,
            'disconnecting' => ConnState.disconnecting,
            _ => ConnState.disconnected,
          };
          if (state == ConnState.connected) {
            connectedAt = DateTime.now();
            _lastUp = _lastDown = 0;
          } else if (state == ConnState.connecting) {
            connectedAt = null; // a new attempt, so a failure of it is not a dropped tunnel
          } else if (state == ConnState.disconnected) {
            // Only a tunnel that was really connected has "dropped". A connect attempt that failed its
            // traffic check must not start a reconnect loop.
            final wasConnected = connectedAt != null;
            connectedAt = null;
            upBps = downBps = 0;
            downHistory.fillRange(0, downHistory.length, 0);
            if (e['error'] != null) {
              error = e['error'] as String;
              log('E', error!);
            }
            if (!_userStopped && wasConnected && settings.reconnectOnDrop && selected != null) {
              _reconnect?.cancel();
              _reconnect = Timer(Duration(seconds: settings.reconnectDelaySec), connect);
              log('W', 'Dropped. Reconnecting in ${settings.reconnectDelaySec}s');
            }
          }
          notifyListeners();
        case 'log':
          log(e['level'] as String? ?? 'I', e['text'] as String);
        case 'traffic':
          upBytes = (e['up'] as num).toInt();
          downBytes = (e['down'] as num).toInt();
          _addUsage((upBytes - _lastUp).clamp(0, 1 << 40).toInt() + (downBytes - _lastDown).clamp(0, 1 << 40).toInt());
          upBps = (upBytes - _lastUp).toDouble().clamp(0, double.infinity);
          downBps = (downBytes - _lastDown).toDouble().clamp(0, double.infinity);
          downHistory
            ..removeAt(0)
            ..add(downBps);
          _lastUp = upBytes;
          _lastDown = downBytes;
          notifyListeners();
      }
    });
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);
  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
