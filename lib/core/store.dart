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
  int upBytes = 0, downBytes = 0;
  double upBps = 0, downBps = 0;
  DateTime? connectedAt;
  Timer? _reconnect;
  bool _userStopped = true;
  int _lastUp = 0, _lastDown = 0;

  static Future<AppStore> load() async {
    final p = await SharedPreferences.getInstance();
    final s = Settings.fromMap(jsonDecode(p.getString('settings') ?? '{}'));
    final profiles = ((jsonDecode(p.getString('profiles') ?? '[]')) as List)
        .map((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
    final subs = ((jsonDecode(p.getString('subs') ?? '[]')) as List)
        .map((e) => Subscription.fromMap(e as Map<String, dynamic>))
        .toList();
    final st = AppStore._(p, s, profiles, p.getString('selected'), subs);
    st.lifetimeBytes = p.getInt('lifetime') ?? 0;
    st._day = p.getString('usageDay') ?? '';
    st.todayBytes = st._day == st._today() ? (p.getInt('usageToday') ?? 0) : 0;
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

  // ---- persistence -------------------------------------------------------
  void saveSettings() {
    _prefs.setString('settings', jsonEncode(settings.toMap()));
    notifyListeners();
  }

  void _saveProfiles() {
    _prefs.setString('profiles', jsonEncode(profiles.map((e) => e.toMap()).toList()));
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

  void sortByPing() {
    int k(Profile p) => p.pingMs == null ? 1 << 30 : (p.pingMs! < 0 ? 1 << 29 : p.pingMs!);
    profiles.sort((a, b) => k(a).compareTo(k(b)));
    _saveProfiles();
  }

  /// Pings every config, then selects the quickest. Returns it, or null when none answered.
  Future<Profile?> pickFastest() async {
    Profile? best;
    for (final p in List.of(profiles)) {
      try {
        p.pingMs = await Bridge.ping(buildConfig(p), settings.pingUrl);
      } catch (_) {
        p.pingMs = -1;
      }
      if (p.pingMs! >= 0 && (best == null || p.pingMs! < best.pingMs!)) best = p;
      notifyListeners();
    }
    if (best != null) selectedId = best.id;
    _saveProfiles();
    return best;
  }

  // ---- subscriptions ---------------------------------------------------------
  void _saveSubs() {
    _prefs.setString('subs', jsonEncode(subs.map((e) => e.toMap()).toList()));
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
      final fresh = <Profile>[];
      for (final line in body.split(RegExp(r'\s+')).where((e) => e.contains('://'))) {
        try {
          final m = jsonDecode(await Bridge.parseLink(line)) as Map<String, dynamic>;
          final name = (m.remove('name') as String?)?.trim();
          fresh.add(Profile(
              id: '${sub.id}-${fresh.length}',
              name: name?.isNotEmpty == true ? name! : '${sub.name} ${fresh.length + 1}',
              json: jsonEncode(m),
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
    _prefs.setString('settings', jsonEncode(settings.toMap()));
    _prefs.setString('subs', jsonEncode(subs.map((e) => e.toMap()).toList()));
    _saveProfiles();
  }

  /// Dials through the config's whole chain to check it really works, as Hiddify users asked for.
  Future<void> _healthCheck(Profile p, String cfg) async {
    if (!settings.connectionCheck) return;
    try {
      final ms = await Bridge.ping(cfg, settings.pingUrl);
      log('I', 'Connection check passed (${ms} ms)');
      setPing(p, ms);
    } catch (e) {
      log('W', 'Connection check failed: $e. The tunnel is up but this config may not be passing traffic');
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
    _userStopped = false;
    error = null;
    state = ConnState.connecting;
    notifyListeners();
    try {
      if (settings.autoFastest && profiles.length > 1) {
        log('I', 'Picking the fastest config');
        final f = await pickFastest();
        if (f != null) log('I', 'Fastest: "${f.name}" (${f.pingMs} ms)');
      }
      if (settings.mode == 'tun' && !await Bridge.prepareVpn()) {
        throw 'VPN permission was not granted';
      }
      final p = selected!;
      final cfg = buildConfig(p);
      final bad = await Bridge.validate(cfg);
      if (bad.isNotEmpty) throw bad;
      log('I', 'Connecting with "${p.name}" (${p.protocol}) in ${settings.mode} mode');
      await Bridge.start(cfg, nativeOptions());
      unawaited(_afterConnect(p, cfg));
    } catch (e) {
      state = ConnState.disconnected;
      error = e.toString();
      log('E', error!);
      notifyListeners();
    }
  }

  Future<void> _afterConnect(Profile p, String cfg) async {
    for (var i = 0; i < 20 && state != ConnState.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (state == ConnState.connected) await _healthCheck(p, cfg);
  }

  Future<void> disconnect() async {
    _userStopped = true;
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
          } else if (state == ConnState.disconnected) {
            // Only a tunnel that was really connected has "dropped". A connect attempt that failed its
            // traffic check must not start a reconnect loop.
            final wasConnected = connectedAt != null;
            connectedAt = null;
            upBps = downBps = 0;
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
