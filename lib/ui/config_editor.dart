import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

part 'config_editor_more.dart';

/// One choice in a picker dialog.
class _Opt {
  const _Opt(this.value, this.label);
  final String value, label;
}

// Protocols, transports and options below follow the Config struct and the
// proxy/transport code of CipherTun/V2-TUN on branch fix/review-20261104,
// the branch setup.sh builds the app against.
const _protocols = <_Opt>[
  _Opt('vless', 'VLESS'),
  _Opt('vmess', 'VMess'),
  _Opt('trojan', 'Trojan'),
  _Opt('shadowsocks', 'Shadowsocks'),
  _Opt('ssh', 'SSH'),
  _Opt('socks5', 'SOCKS5'),
  _Opt('socks4', 'SOCKS4'),
  _Opt('http', 'HTTP proxy'),
  _Opt('https', 'HTTPS proxy'),
  _Opt('hysteria2', 'Hysteria 2'),
  _Opt('hysteria', 'Hysteria 1'),
];

const _networks = <_Opt>[
  _Opt('tcp', 'TCP'),
  _Opt('kcp', 'mKCP'),
  _Opt('ws', 'WebSocket'),
  _Opt('httpupgrade', 'HTTP Upgrade'),
  _Opt('h2', 'HTTP/2'),
  _Opt('xhttp', 'XHTTP'),
  _Opt('grpc', 'gRPC'),
  _Opt('quic', 'QUIC'),
];

const _securities = <_Opt>[
  _Opt('none', 'None'),
  _Opt('tls', 'TLS'),
  _Opt('reality', 'REALITY'),
];

const _flows = <_Opt>[
  _Opt('', 'None'),
  _Opt('xtls-rprx-vision', 'XTLS-RPRX-Vision'),
  _Opt('xtls-rprx-vision-udp443', 'XTLS-RPRX-Vision-UDP443'),
];

const _fingerprints = <_Opt>[
  _Opt('', 'Default'),
  _Opt('chrome', 'chrome'),
  _Opt('firefox', 'firefox'),
  _Opt('safari', 'safari'),
  _Opt('ios', 'ios'),
  _Opt('android', 'android'),
  _Opt('edge', 'edge'),
  _Opt('random', 'random'),
];

const _vmessMethods = <_Opt>[
  _Opt('auto', 'auto'),
  _Opt('aes-128-gcm', 'aes-128-gcm'),
  _Opt('chacha20-poly1305', 'chacha20-poly1305'),
  _Opt('none', 'none'),
];

const _ssMethods = <_Opt>[
  _Opt('aes-128-gcm', 'aes-128-gcm'),
  _Opt('aes-192-gcm', 'aes-192-gcm'),
  _Opt('aes-256-gcm', 'aes-256-gcm'),
  _Opt('chacha20-ietf-poly1305', 'chacha20-ietf-poly1305'),
  _Opt('aes-128-cfb', 'aes-128-cfb'),
  _Opt('aes-192-cfb', 'aes-192-cfb'),
  _Opt('aes-256-cfb', 'aes-256-cfb'),
  _Opt('aes-128-ctr', 'aes-128-ctr'),
  _Opt('aes-192-ctr', 'aes-192-ctr'),
  _Opt('aes-256-ctr', 'aes-256-ctr'),
  _Opt('rc4-md5', 'rc4-md5'),
  _Opt('chacha20-ietf', 'chacha20-ietf'),
];

const _xhttpModes = <_Opt>[
  _Opt('auto', 'Auto'),
  _Opt('packet-up', 'Packet up'),
  _Opt('stream-up', 'Stream up'),
  _Opt('stream-one', 'Stream one'),
];

/// The library accepts a few aliases; the editor always works with one name.
String _canonProtocol(String p) => switch (p.toLowerCase()) {
      'ss' => 'shadowsocks',
      'socks' => 'socks5',
      'socks4a' => 'socks4',
      'hy2' => 'hysteria2',
      'hy' || 'hysteria1' => 'hysteria',
      final v => v,
    };

String _canonNetwork(String n) => switch (n.toLowerCase()) {
      '' => 'tcp',
      'websocket' => 'ws',
      'http' => 'h2',
      'splithttp' => 'xhttp',
      'mkcp' => 'kcp',
      final v => v,
    };

String _label(List<_Opt> opts, String v) {
  for (final o in opts) {
    if (o.value == v) return o.label;
  }
  return v;
}

String _mask(String v) => v.isEmpty ? '\u2022' * (v.length > 12 ? 12 : v.length) : '';

// ---- what each protocol uses -----------------------------------------------------
// The editor keeps the config clean: when the protocol changes, every setting
// the new protocol does not use is removed instead of being hidden.

bool _isHysteria(String p) => p == 'hysteria' || p == 'hysteria2';

/// Protocols that take a transport (WebSocket, HTTP/2, gRPC, XHTTP, QUIC, mKCP).
/// SSH, SOCKS and the HTTP proxies run over TCP, optionally with TLS and a
/// payload: the library's share links, presets and tests never put a transport
/// under them, and Hysteria has its own QUIC.
bool _hasTransport(String p) => p == 'vless' || p == 'vmess' || p == 'trojan' || p == 'shadowsocks';

/// Top-level keys that belong to particular protocols.
const _protocolKeys = <String>[
  'uuid',
  'flow',
  'alterId',
  'method',
  'password',
  'username',
  'privateKey',
  'passphrase',
  'proxyHeaders',
  'mux',
  'hysteria',
  'advanced',
];

const _transportKeys = <String>['network', 'ws', 'grpcService', 'grpcMulti', 'xhttpMode', 'xhttp', 'quic', 'kcp'];

const _keyNames = <String, String>{
  'uuid': 'user ID',
  'flow': 'flow',
  'alterId': 'alter ID',
  'method': 'encryption method',
  'password': 'password',
  'username': 'username',
  'privateKey': 'private key',
  'passphrase': 'key passphrase',
  'proxyHeaders': 'proxy headers',
  'mux': 'Mux',
  'hysteria': 'Hysteria settings',
  'advanced': 'SSH settings',
};

/// The [_protocolKeys] that protocol [p] uses.
Set<String> _keysFor(String p) => switch (p) {
      'vless' => {'uuid', 'flow', 'mux'},
      'vmess' => {'uuid', 'alterId', 'method', 'mux'},
      'trojan' => {'password', 'mux'},
      'shadowsocks' => {'method', 'password', 'mux'},
      'ssh' => {'username', 'password', 'privateKey', 'passphrase', 'advanced'},
      'socks5' => {'username', 'password'},
      'socks4' => {'username'},
      'http' || 'https' => {'username', 'password', 'proxyHeaders'},
      'hysteria' || 'hysteria2' => {'password', 'hysteria'},
      _ => <String>{},
    };

// ---- dialogs and row tiles shared by the editor and its sub pages --------------
ShapeBorder get _dlgShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));

/// Returns null on Cancel, the text (possibly empty) on OK.
Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  TextInputType keyboard = TextInputType.text,
  int maxLines = 1,
  bool trim = true,
  bool monospace = false,
}) {
  final c = TextEditingController(text: initial);
  String done() => trim ? c.text.trim() : c.text;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: surfaceHigh,
      shape: _dlgShape,
      title: Text(title, style: serif(22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(hint, style: Theme.of(ctx).textTheme.bodySmall),
            ),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: keyboard,
            minLines: 1,
            maxLines: maxLines,
            autocorrect: false,
            enableSuggestions: false,
            style: monospace ? mono(13) : null,
            onSubmitted: maxLines == 1 ? (_) => Navigator.pop(ctx, done()) : null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, done()), child: const Text('OK')),
      ],
    ),
  );
}

/// Radio list: a tap picks and closes. Returns null on Cancel.
Future<String?> _choiceDialog(BuildContext context, String title, List<_Opt> opts, String current) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final accent = Theme.of(ctx).colorScheme.primary;
      return AlertDialog(
        backgroundColor: surfaceHigh,
        shape: _dlgShape,
        title: Text(title, style: serif(22)),
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final o in opts)
                ListTile(
                  leading: Icon(
                    o.value == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: o.value == current ? accent : textMuted,
                  ),
                  title: Text(o.label),
                  onTap: () => Navigator.pop(ctx, o.value),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      );
    },
  );
}

Future<bool> _confirmDialog(BuildContext context, String title, String body,
    {required String yes, required String no}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: surfaceHigh,
      shape: _dlgShape,
      title: Text(title, style: serif(22)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}

Widget _headerTile(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Text(t, style: sans(12.5, w: FontWeight.w600, color: Theme.of(context).colorScheme.primary, spacing: 0.4)),
    );

Widget _rowTile(BuildContext context, String label, String value, VoidCallback onTap, {bool monospace = false}) {
  final shown = value.isEmpty ? 'Not set' : value;
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (monospace && value.isNotEmpty) ? mono(12.5, color: textMuted) : Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Settings-style editor for one config: rows with the current value, a tap
/// opens a picker or a text dialog. It edits a working copy of the config JSON
/// and keeps every key it does not show (routing, backups ...), except the
/// settings of another protocol or transport, which it removes on a switch.
class ConfigEditorScreen extends StatefulWidget {
  const ConfigEditorScreen({super.key, this.profile});

  /// null creates a new config.
  final Profile? profile;

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  late Map<String, dynamic> _m;
  late String _name;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _name = widget.profile?.name ?? '';
    _m = _initial();
  }

  Map<String, dynamic> _initial() {
    final p = widget.profile;
    if (p != null) {
      try {
        final d = jsonDecode(p.json);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {'protocol': 'vless', 'server': '', 'port': 443};
  }

  // ---- reading and writing the working copy ---------------------------------
  String _str(String k) => (_m[k] ?? '').toString();

  dynamic _get(String obj, String k) {
    final v = _m[obj];
    return v is Map ? v[k] : null;
  }

  String _gs(String obj, String k) => (_get(obj, k) ?? '').toString();

  int _intOf(String k) {
    final v = _m[k];
    return v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
  }

  int _intIn(String obj, String k) {
    final v = _get(obj, k);
    return v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
  }

  /// The live nested object under [k], created when missing.
  Map<String, dynamic> _objOf(String k) {
    final v = _m[k];
    if (v is Map<String, dynamic>) return v;
    final fresh = <String, dynamic>{};
    if (v is Map) fresh.addAll(v.cast<String, dynamic>());
    _m[k] = fresh;
    return fresh;
  }

  bool _empty(Object? v) =>
      v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

  void _set(String k, Object? v) => setState(() {
        if (_empty(v)) {
          _m.remove(k);
        } else {
          _m[k] = v;
        }
        _dirty = true;
      });

  void _setIn(String obj, String k, Object? v, {bool prune = true}) => setState(() {
        final o = _objOf(obj);
        if (_empty(v)) {
          o.remove(k);
        } else {
          o[k] = v;
        }
        if (prune && o.isEmpty) _m.remove(obj);
        _dirty = true;
      });

  String _security() {
    if (_m['reality'] is Map) return 'reality';
    final t = _m['tls'];
    if (t is Map && t['enabled'] == true) return 'tls';
    return 'none';
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---- keeping the config clean -----------------------------------------------
  /// What switching to protocol [v] would remove, as readable names.
  List<String> _removedBy(String v) {
    final keep = _keysFor(v);
    final names = <String>{};
    for (final k in _protocolKeys) {
      if (!keep.contains(k) && !_empty(_m[k])) names.add(_keyNames[k]!);
    }
    if (!_hasTransport(v) && _transportKeys.any((k) => !_empty(_m[k]))) names.add('transport');
    if (_isHysteria(v)) {
      if (_m['reality'] is Map) names.add('REALITY');
      if (!_empty(_m['payload'])) names.add('payload');
      if (!_empty(_m['fragment'])) names.add('fragment');
    }
    return names.toList();
  }

  /// Removes every setting that protocol [v] does not use. Call inside setState.
  void _prune(String v) {
    final keep = _keysFor(v);
    for (final k in _protocolKeys) {
      if (!keep.contains(k)) _m.remove(k);
    }
    if (!_hasTransport(v)) {
      for (final k in _transportKeys) {
        _m.remove(k);
      }
    }
    if (_isHysteria(v)) {
      // Hysteria brings its own QUIC and TLS and only reads the name and the insecure flag.
      for (final k in ['reality', 'payload', 'fragment']) {
        _m.remove(k);
      }
      final tls = _m['tls'];
      if (tls is Map) {
        tls.removeWhere((k, _) => k != 'sni' && k != 'allowInsecure');
        if (tls.isEmpty) _m.remove('tls');
      }
    }
  }

  /// Removes the settings of every transport except [v]. Call inside setState.
  void _pruneTransport(String v) {
    if (v != 'grpc') {
      _m.remove('grpcService');
      _m.remove('grpcMulti');
    }
    if (v != 'xhttp') {
      _m.remove('xhttpMode');
      _m.remove('xhttp');
    }
    if (v != 'quic') _m.remove('quic');
    if (v != 'kcp') _m.remove('kcp');
    final ws = _m['ws'];
    if (ws is Map) {
      if (v == 'tcp' || v == 'quic' || v == 'kcp') {
        _m.remove('ws'); // host, path and headers only exist for the HTTP based transports
      } else {
        if (v != 'ws') {
          ws.remove('maxEarlyData');
          ws.remove('pingSec');
        }
        if (v == 'grpc') {
          ws.remove('path'); // gRPC uses the host and the service name only
          ws.remove('headers');
        }
        if (ws.isEmpty) _m.remove('ws');
      }
    }
    if (v == 'quic') {
      // the library rejects a pin or verify name with QUIC, and QUIC takes no fingerprint
      final t = _m['tls'];
      if (t is Map) {
        t.remove('pinSha256');
        t.remove('verifyName');
        t.remove('fingerprint');
        if (t.isEmpty) _m.remove('tls');
      }
    }
  }

  // ---- dialogs (thin wrappers over the shared ones) ---------------------------
  Future<String?> _askText({
    required String title,
    required String initial,
    String? hint,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool trim = true,
    bool monospace = false,
  }) =>
      _textDialog(context,
          title: title,
          initial: initial,
          hint: hint,
          keyboard: keyboard,
          maxLines: maxLines,
          trim: trim,
          monospace: monospace);

  Future<String?> _askChoice(String title, List<_Opt> opts, String current) =>
      _choiceDialog(context, title, opts, current);

  Future<bool> _confirm(String title, String body, {required String yes, required String no}) =>
      _confirmDialog(context, title, body, yes: yes, no: no);

  Future<int?> _askInt(String title, int current,
      {String? hint, required int min, required int max, bool allowEmpty = false}) async {
    final v = await _askText(
      title: title,
      hint: hint,
      initial: (current == 0 && allowEmpty) ? '' : '$current',
      keyboard: TextInputType.number,
    );
    if (v == null) return null;
    if (v.isEmpty && allowEmpty) return 0;
    final n = int.tryParse(v);
    if (n == null || n < min || n > max) {
      if (mounted) _toast('$title must be a number from $min to $max');
      return null;
    }
    return n;
  }

  // ---- row editors ------------------------------------------------------------
  Future<void> _editTop(String key, String title, {String? hint, int maxLines = 1, bool trim = true}) async {
    final v = await _askText(
        title: title, hint: hint, initial: _str(key), maxLines: maxLines, trim: trim, monospace: true);
    if (v != null) _set(key, v);
  }

  Future<void> _editIn(String obj, String key, String title,
      {String? hint, bool prune = true, bool trim = true}) async {
    final v = await _askText(title: title, hint: hint, initial: _gs(obj, key), trim: trim, monospace: true);
    if (v != null) _setIn(obj, key, v, prune: prune);
  }

  Future<void> _editList(String obj, String key, String title, {String? hint}) async {
    final cur = _get(obj, key);
    final v = await _askText(
        title: title, hint: hint, initial: cur is List ? cur.join(', ') : '', monospace: true);
    if (v == null) return;
    _setIn(obj, key, v.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).toList());
  }

  /// Picker for a key inside a nested object such as tls or reality.
  Future<void> _pickIn(String obj, String key, String title, List<_Opt> opts, {bool prune = true}) async {
    final v = await _askChoice(title, opts, _gs(obj, key).toLowerCase());
    if (v != null) _setIn(obj, key, v, prune: prune);
  }

  /// Picker for a top-level key such as method.
  Future<void> _pickTop(String key, String title, List<_Opt> opts) async {
    final v = await _askChoice(title, opts, _str(key).toLowerCase());
    if (v != null) _set(key, v);
  }

  Future<void> _editName() async {
    final v = await _askText(title: 'Name', initial: _name);
    if (v != null) {
      setState(() {
        _name = v;
        _dirty = true;
      });
    }
  }

  Future<void> _editHost() async {
    final v = await _askText(
        title: 'Host', hint: 'Server address: a domain name or an IP.', initial: _str('server'), monospace: true);
    if (v != null) {
      setState(() {
        _m['server'] = v;
        _dirty = true;
      });
    }
  }

  Future<void> _editPort() async {
    final n = await _askInt('Server port', _intOf('port'), min: 1, max: 65535);
    if (n != null) {
      setState(() {
        _m['port'] = n;
        _dirty = true;
      });
    }
  }

  Future<void> _editAlterId() async {
    final n = await _askInt('Alter ID', _intOf('alterId'),
        hint: '0 for current servers. Above 0 uses the legacy VMess header.', min: 0, max: 65535);
    if (n != null) _set('alterId', n == 0 ? null : n);
  }

  Future<void> _editMbps(String key, String title, {String? hint}) async {
    final n = await _askInt(title, _intIn('hysteria', key), hint: hint, min: 0, max: 100000, allowEmpty: true);
    if (n != null) _setIn('hysteria', key, n == 0 ? null : n);
  }

  Future<void> _editShortId() async {
    final v = await _askText(
        title: 'Short ID',
        hint: '0 to 16 hex characters, an even number of them.',
        initial: _gs('reality', 'shortId'),
        monospace: true);
    if (v == null) return;
    if (!RegExp(r'^([0-9a-fA-F]{2}){0,8}$').hasMatch(v)) {
      _toast('Short ID must be 0 to 16 hex characters, an even number of them');
      return;
    }
    _setIn('reality', 'shortId', v, prune: false);
  }

  Future<void> _pickProtocol() async {
    final cur = _canonProtocol(_str('protocol'));
    final v = await _askChoice('Protocol', _protocols, cur);
    if (v == null || v == cur) return;
    final removed = _removedBy(v);
    if (removed.isNotEmpty) {
      final name = _label(_protocols, v);
      final ok = await _confirm(
        'Switch to $name?',
        '$name does not use these settings, so they will be removed: ${removed.join(', ')}.',
        yes: 'Continue',
        no: 'Cancel',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      _dirty = true;
      _m['protocol'] = v;
      _prune(v);
      final method = _str('method').toLowerCase();
      if (v == 'shadowsocks' && !_ssMethods.any((o) => o.value == method)) _m['method'] = 'aes-128-gcm';
      if (v == 'vmess' && !_vmessMethods.any((o) => o.value == method)) _m['method'] = 'auto';
      // An https proxy needs a TLS layer in the dial chain.
      if (v == 'https') _objOf('tls')['enabled'] = true;
    });
  }

  Future<void> _pickNetwork() async {
    final cur = _canonNetwork(_str('network'));
    final v = await _askChoice('Network type', _networks, cur);
    if (v == null || v == cur) return;
    if ((v == 'quic' || v == 'kcp') && _m['reality'] is Map) {
      _toast("REALITY can't be combined with QUIC or mKCP");
      return;
    }
    if ((v == 'quic' || v == 'kcp') && _canonProtocol(_str('protocol')) == 'https') {
      _toast("An HTTPS proxy needs TLS, which QUIC and mKCP don't use");
      return;
    }
    var droppedFlow = false;
    var droppedTls = false;
    var droppedOld = false;
    setState(() {
      _dirty = true;
      if (v == 'tcp') {
        _m.remove('network');
      } else {
        _m['network'] = v;
      }
      final before = jsonEncode(_m);
      _pruneTransport(v);
      droppedOld = before != jsonEncode(_m);
      if (v != 'tcp' && _str('flow').isNotEmpty) {
        _m.remove('flow');
        droppedFlow = true;
      }
      if (v == 'kcp') {
        // mKCP runs over UDP and does not use TLS
        final t = _m['tls'];
        if (t is Map) {
          if (t['enabled'] == true) droppedTls = true;
          t.remove('enabled');
          t.remove('pinSha256');
          t.remove('verifyName');
          if (t.isEmpty) _m.remove('tls');
        }
      }
    });
    final notes = <String>[
      if (droppedOld) 'Settings of the previous transport were removed',
      if (droppedFlow) 'Flow removed: XTLS Vision needs the TCP transport',
      if (droppedTls) 'TLS turned off: mKCP does not use it',
    ];
    if (notes.isNotEmpty) _toast(notes.join('. '));
  }

  Future<void> _pickFlow() async {
    final cur = _str('flow').toLowerCase();
    final v = await _askChoice('Flow', _flows, cur);
    if (v == null || v == cur) return;
    if (v.isNotEmpty && _get('mux', 'enabled') == true) {
      _toast('XTLS Vision cannot be used with Mux. Turn Mux off first');
      return;
    }
    final notes = <String>[];
    setState(() {
      _dirty = true;
      if (v.isEmpty) {
        _m.remove('flow');
        return;
      }
      _m['flow'] = v;
      if (_canonNetwork(_str('network')) != 'tcp') {
        _m.remove('network');
        _pruneTransport('tcp');
        notes.add('Transport set to TCP, which XTLS Vision needs');
      }
    });
    if (v.isNotEmpty && _security() == 'none') notes.add('Set Security to TLS or REALITY');
    if (notes.isNotEmpty) _toast(notes.join('. '));
  }

  Future<void> _pickSecurity(String net) async {
    final cur = _security();
    // An https proxy needs TLS in the chain, so "None" is not offered for it.
    final isHttps = _canonProtocol(_str('protocol')) == 'https';
    final v = await _askChoice(
        'Security', isHttps ? _securities.where((o) => o.value != 'none').toList() : _securities, cur);
    if (v == null || v == cur) return;
    if (v == 'reality' && net == 'quic') {
      _toast("REALITY can't be used with the QUIC transport");
      return;
    }
    var droppedFlow = false;
    var droppedFragment = false;
    setState(() {
      _dirty = true;
      final tls = _objOf('tls');
      if (v == 'tls') {
        _m.remove('reality');
        tls['enabled'] = true;
      } else {
        // the library rejects a pin or verify name when TLS is not in use
        tls.remove('enabled');
        tls.remove('pinSha256');
        tls.remove('verifyName');
        if (v == 'reality') {
          tls.remove('allowInsecure'); // REALITY does its own verification
          final r = _objOf('reality');
          if ((r['serverName'] ?? '').toString().isEmpty && _gs('tls', 'sni').isNotEmpty) {
            r['serverName'] = tls['sni'];
          }
        } else {
          _m.remove('reality');
          // Fragment only splits a TLS ClientHello, and a payload stage of
          // "after TLS" means nothing without TLS.
          if (_m.remove('fragment') != null) droppedFragment = true;
          final pl = _m['payload'];
          if (pl is Map) pl.remove('stage');
          if (_str('flow').isNotEmpty) {
            _m.remove('flow');
            droppedFlow = true;
          }
        }
      }
      if (tls.isEmpty) _m.remove('tls');
    });
    final notes = <String>[
      if (droppedFlow) 'Flow removed: XTLS Vision needs TLS or REALITY',
      if (droppedFragment) 'Fragment removed: it only splits a TLS handshake',
    ];
    if (notes.isNotEmpty) _toast(notes.join('. '));
  }

  Future<void> _openJson() async {
    final text = const JsonEncoder.withIndent('  ').convert(_m);
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _JsonPage(initial: text)),
    );
    if (res == null || !mounted) return;
    try {
      final d = jsonDecode(res);
      if (d is Map<String, dynamic>) {
        setState(() {
          _m = d;
          _dirty = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_m)));
    if (mounted) _toast('Config JSON copied');
  }

  void _leave() {
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _save() async {
    final st = StoreScope.of(context);
    final json = jsonEncode(_m);
    var err = '';
    try {
      err = await Bridge.validate(json);
    } catch (e) {
      err = e.toString();
    }
    if (!mounted) return;
    if (err.isNotEmpty) {
      final anyway = await _confirm('This config has a problem', err, yes: 'Save anyway', no: 'Keep editing');
      if (!anyway || !mounted) return;
    }
    final name = _name.trim().isEmpty ? 'Config ${st.profiles.length + 1}' : _name.trim();
    final p = widget.profile;
    if (p == null) {
      st.addProfile(name, json);
    } else {
      st.updateProfile(p, name: name, json: json);
    }
    _leave();
  }

  // ---- row widgets ------------------------------------------------------------
  Widget _header(String t) => _headerTile(context, t);

  Widget _divider() => const Divider(height: 1, thickness: 1, color: outline);

  Widget _row(String label, String value, VoidCallback onTap, {bool monospace = false}) =>
      _rowTile(context, label, value, onTap, monospace: monospace);

  Widget _switch(String label, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: Text(sub, style: Theme.of(context).textTheme.bodySmall),
        value: value,
        onChanged: onChanged,
      );

  Widget _insecureSwitch() => _switch(
        'Allow insecure certificates',
        'Skips certificate checks. Only for servers you trust.',
        _get('tls', 'allowInsecure') == true,
        (v) => _setIn('tls', 'allowInsecure', v ? true : null),
      );

  Widget _sniRow() => _row(
        'Server name (SNI)',
        _gs('tls', 'sni'),
        () => _editIn('tls', 'sni', 'Server name (SNI)', hint: 'Server name sent in the TLS handshake.'),
        monospace: true,
      );

  Widget _alpnRow() => _row(
        'ALPN',
        (_get('tls', 'alpn') is List) ? (_get('tls', 'alpn') as List).join(', ') : '',
        () => _editList('tls', 'alpn', 'ALPN', hint: 'Comma separated, for example h2, http/1.1.'),
        monospace: true,
      );

  // ---- sections ---------------------------------------------------------------
  List<Widget> _authRows(String proto) {
    switch (proto) {
      case 'vless':
        return [
          _row('User ID', _mask(_str('uuid')), () => _editTop('uuid', 'User ID', hint: 'The UUID from your server.'),
              monospace: true),
          _row('Flow', _label(_flows, _str('flow').toLowerCase()), _pickFlow),
        ];
      case 'vmess':
        return [
          _row('User ID', _mask(_str('uuid')), () => _editTop('uuid', 'User ID', hint: 'The UUID from your server.'),
              monospace: true),
          _row('Alter ID', _m['alterId'] == null ? '0' : '${_intOf('alterId')}', _editAlterId),
          _row('Encryption', _label(_vmessMethods, _str('method').toLowerCase()),
              () => _pickTop('method', 'Encryption', _vmessMethods)),
        ];
      case 'trojan':
        return [
          _row('Password', _mask(_str('password')),
              () => _editTop('password', 'Password', trim: false), monospace: true),
        ];
      case 'shadowsocks':
        return [
          _row('Method', _label(_ssMethods, _str('method').toLowerCase()),
              () => _pickTop('method', 'Method', _ssMethods)),
          _row('Password', _mask(_str('password')),
              () => _editTop('password', 'Password', trim: false), monospace: true),
        ];
      case 'ssh':
        final key = _str('privateKey');
        return [
          _row('Username', _str('username'), () => _editTop('username', 'Username'), monospace: true),
          _row('Password', _mask(_str('password')),
              () => _editTop('password', 'Password', trim: false), monospace: true),
          _row(
            'Private key',
            key.contains('PRIVATE KEY') ? 'Key stored' : key,
            () => _editTop('privateKey', 'Private key',
                hint: 'PEM text, or a file path on this phone. Leave empty to log in with the password.',
                maxLines: 8),
            monospace: true,
          ),
          _row('Key passphrase', _mask(_str('passphrase')),
              () => _editTop('passphrase', 'Key passphrase', hint: 'Only for an encrypted private key.', trim: false),
              monospace: true),
          _row(
            'Host key pin',
            _gs('advanced', 'sshHostKey'),
            () => _editIn('advanced', 'sshHostKey', 'Host key pin',
                hint: 'SHA256:... as printed by ssh-keygen -l, or 64 hex characters. Empty accepts any key.'),
            monospace: true,
          ),
        ];
      case 'socks4':
        // SOCKS4 has a user id and no password.
        return [
          _row('User ID', _str('username'),
              () => _editTop('username', 'User ID', hint: 'Optional. SOCKS4 has no password.'),
              monospace: true),
        ];
      case 'socks5':
      case 'http':
      case 'https':
        return [
          _row('Username', _str('username'),
              () => _editTop('username', 'Username', hint: 'Leave empty if the server needs no login.'),
              monospace: true),
          _row('Password', _mask(_str('password')),
              () => _editTop('password', 'Password', trim: false), monospace: true),
          if (proto == 'http' || proto == 'https') _headersRow(null, 'proxyHeaders'),
        ];
      case 'hysteria2':
        return [
          _row('Password', _mask(_str('password')),
              () => _editTop('password', 'Password', trim: false), monospace: true),
        ];
      case 'hysteria':
        return [
          _row('Auth string', _mask(_str('password')),
              () => _editTop('password', 'Auth string', trim: false), monospace: true),
        ];
      default:
        return [];
    }
  }

  List<Widget> _hysteriaRows(String proto) {
    final hy2 = proto == 'hysteria2';
    return [
      _row(
        'Obfuscation password',
        _mask(_gs('hysteria', 'obfs')),
        () => _editIn('hysteria', 'obfs', 'Obfuscation password',
            hint: hy2 ? 'Salamander password. Leave empty for none.' : 'xplus password. Leave empty for none.',
            trim: false),
        monospace: true,
      ),
      if (hy2)
        _row(
          'Certificate pin (SHA-256)',
          _gs('hysteria', 'pinSha256'),
          () => _editIn('hysteria', 'pinSha256', 'Certificate pin (SHA-256)',
              hint: 'Hex SHA-256 of the server certificate. Replaces CA verification.'),
          monospace: true,
        ),
      if (!hy2)
        _row(
          'ALPN',
          _gs('hysteria', 'alpn'),
          () => _editIn('hysteria', 'alpn', 'ALPN', hint: 'Leave empty for the default, hysteria.'),
          monospace: true,
        ),
      if (!hy2)
        _row(
          'Upload speed (Mbps)',
          _intIn('hysteria', 'upMbps') == 0 ? '' : '${_intIn('hysteria', 'upMbps')}',
          () => _editMbps('upMbps', 'Upload speed (Mbps)', hint: 'Sent to the server. Empty uses 10.'),
        ),
      _row(
        'Download speed (Mbps)',
        _intIn('hysteria', 'downMbps') == 0 ? '' : '${_intIn('hysteria', 'downMbps')}',
        () => _editMbps('downMbps', 'Download speed (Mbps)',
            hint: hy2 ? 'Advertised receive rate. Empty lets the server decide.' : 'The server sends at this rate. Empty uses 50.'),
      ),
      _sniRow(),
      _insecureSwitch(),
    ];
  }

  List<Widget> _transportRows(String net) {
    final http = net == 'ws' || net == 'httpupgrade' || net == 'h2' || net == 'xhttp';
    return [
      _row('Network type', _label(_networks, net), _pickNetwork),
      if (http) ...[
        _row('HTTP host', _gs('ws', 'host'),
            () => _editIn('ws', 'host', 'HTTP host', hint: 'Host header sent with the request.'),
            monospace: true),
        _row('HTTP path', _gs('ws', 'path'),
            () => _editIn('ws', 'path', 'HTTP path', hint: 'Client and server must have the same value.'),
            monospace: true),
        _headersRow('ws', 'headers'),
      ],
      if (net == 'ws') ..._wsRows(),
      if (net == 'xhttp') ...[
        _row('XHTTP mode', _label(_xhttpModes, _str('xhttpMode')),
            () => _pickTop('xhttpMode', 'XHTTP mode', _xhttpModes)),
        ..._xhttpRows(),
      ],
      if (net == 'grpc') ...[
        _row('Host', _gs('ws', 'host'),
            () => _editIn('ws', 'host', 'Host', hint: 'Authority sent with the request.'),
            monospace: true),
        _row('Service name', _str('grpcService'),
            () => _editTop('grpcService', 'Service name', hint: 'The gRPC service name set on the server.'),
            monospace: true),
        ..._grpcRows(),
      ],
      if (net == 'quic') ..._quicRows(),
      if (net == 'kcp') ..._kcpRows(),
    ];
  }

  List<Widget> _securityRows(String net) {
    if (net == 'quic') {
      // QUIC carries its own TLS, so there is no on/off switch here.
      return [_sniRow(), _alpnRow(), _insecureSwitch()];
    }
    final sec = _security();
    return [
      _row('Security', _label(_securities, sec), () => _pickSecurity(net)),
      if (sec == 'tls') ...[
        _sniRow(),
        _alpnRow(),
        _row('Fingerprint', _label(_fingerprints, _gs('tls', 'fingerprint').toLowerCase()),
            () => _pickIn('tls', 'fingerprint', 'Fingerprint', _fingerprints)),
        _insecureSwitch(),
        _row('Certificate pin (SHA-256)',
            (_get('tls', 'pinSha256') is List) ? (_get('tls', 'pinSha256') as List).join(', ') : '',
            () => _editList('tls', 'pinSha256', 'Certificate pin (SHA-256)',
                hint: 'Hex SHA-256 of the server certificate. Separate several with commas.'),
            monospace: true),
        // The library skips the name check when insecure certificates are allowed.
        if (_get('tls', 'allowInsecure') != true)
          _row('Verify name', _gs('tls', 'verifyName'),
              () => _editIn('tls', 'verifyName', 'Verify name',
                  hint: 'Check the server certificate for this name instead of the SNI.'),
              monospace: true),
      ],
      if (sec == 'reality') ...[
        _row('Public key', _gs('reality', 'publicKey'),
            () => _editIn('reality', 'publicKey', 'Public key',
                hint: 'Server X25519 public key, base64url.', prune: false),
            monospace: true),
        _row('Short ID', _gs('reality', 'shortId'), _editShortId, monospace: true),
        _row('Server name', _gs('reality', 'serverName'),
            () => _editIn('reality', 'serverName', 'Server name',
                hint: 'SNI of the cover site. Empty uses the TLS server name, then the server host.',
                prune: false),
            monospace: true),
        _row('Fingerprint', _label(_fingerprints, _gs('reality', 'fingerprint').toLowerCase()),
            () => _pickIn('reality', 'fingerprint', 'Fingerprint', _fingerprints, prune: false)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final proto = _canonProtocol(_str('protocol'));
    final net = _canonNetwork(_str('network'));
    final hy = _isHysteria(proto);
    // SSH, SOCKS and HTTP proxies have no transport. A config that already has
    // one (imported JSON) still shows it, so nothing active is ever hidden.
    final showTransport = _hasTransport(proto) || net != 'tcp';

    final children = <Widget>[
      _row('Name', _name, _editName),
      _row('Protocol', _label(_protocols, proto), _pickProtocol),
      _divider(),
      _header('Server'),
      _row('Host', _str('server'), _editHost, monospace: true),
      _row('Server port', _m['port'] == null ? '' : '${_intOf('port')}', _editPort),
      ..._authRows(proto),
    ];
    if (hy) {
      children
        ..add(_divider())
        ..add(_header('Hysteria'))
        ..addAll(_hysteriaRows(proto));
    } else {
      if (showTransport) {
        children
          ..add(_divider())
          ..add(_header('Transport'))
          ..addAll(_transportRows(net));
      }
      if (net != 'kcp') {
        children
          ..add(_divider())
          ..add(_header('Transport layer encryption'))
          ..addAll(_securityRows(net));
      }
      if (net != 'quic' && net != 'kcp') {
        children
          ..add(_divider())
          ..add(_header('Payload'))
          ..addAll(_payloadRows());
        // Fragment only splits a TLS ClientHello, so it needs TLS or REALITY.
        if (_security() != 'none') {
          children
            ..add(_divider())
            ..add(_header('Fragment'))
            ..addAll(_fragmentRows());
        }
      }
      if (_muxable(proto)) {
        children
          ..add(_divider())
          ..add(_header('Multiplexing'))
          ..addAll(_muxRows());
      }
    }
    children
      ..add(_divider())
      ..add(_header('Advanced'))
      ..addAll(_advancedRows());

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirm('Discard changes?', 'Your edits to this config will be lost.',
            yes: 'Discard', no: 'Keep editing');
        if (discard && mounted) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.profile == null ? 'New config' : 'Edit config', style: serif(22)),
          actions: [
            IconButton(tooltip: 'Edit as JSON', icon: const Icon(Icons.data_object_rounded), onPressed: _openJson),
            IconButton(tooltip: 'Copy config JSON', icon: const Icon(Icons.content_copy_rounded), onPressed: _copy),
            IconButton(
              tooltip: 'Save',
              icon: Icon(Icons.save_rounded, color: Theme.of(context).colorScheme.primary),
              onPressed: _save,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32),
          children: children,
        ),
      ),
    );
  }
}

/// Raw JSON editor, the same editing the app had before the form existed.
class _JsonPage extends StatefulWidget {
  const _JsonPage({required this.initial});
  final String initial;

  @override
  State<_JsonPage> createState() => _JsonPageState();
}

class _JsonPageState extends State<_JsonPage> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parse() {
    try {
      final d = jsonDecode(_c.text);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return null;
  }

  Future<void> _validate() async {
    if (_parse() == null) {
      setState(() => _err = 'Not valid JSON');
      return;
    }
    final r = await Bridge.validate(_c.text);
    if (!mounted) return;
    setState(() => _err = r.isEmpty ? null : r);
    if (r.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Config is valid')));
    }
  }

  void _apply() {
    if (_parse() == null) {
      setState(() => _err = 'Not valid JSON');
      return;
    }
    Navigator.pop(context, _c.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Config JSON', style: serif(22)),
        actions: [
          IconButton(tooltip: 'Validate', icon: const Icon(Icons.fact_check_outlined), onPressed: _validate),
          IconButton(
            tooltip: 'Apply',
            icon: Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary),
            onPressed: _apply,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
        child: TextField(
          controller: _c,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          style: mono(12.5),
          decoration: InputDecoration(errorText: _err, errorMaxLines: 4),
          onChanged: (_) {
            if (_err != null) setState(() => _err = null);
          },
        ),
      ),
    );
  }
}
