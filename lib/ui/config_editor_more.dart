part of 'config_editor.dart';

// New library features in the form: mKCP, QUIC options, gRPC multi mode,
// WebSocket early data, XHTTP tuning, custom headers, fragment, Mux.Cool and
// the HTTP payload. They live here to keep config_editor.dart readable; this
// file shares its private members through `part of`.

const _kcpHeaders = <_Opt>[
  _Opt('none', 'none'),
  _Opt('srtp', 'srtp (video call)'),
  _Opt('utp', 'utp (BitTorrent)'),
  _Opt('wechat-video', 'wechat-video'),
  _Opt('dtls', 'dtls'),
  _Opt('wireguard', 'wireguard'),
];

extension _EditorMore on _ConfigEditorScreenState {
  /// Protocols the library can wrap in Mux.Cool.
  bool _muxable(String proto) =>
      proto == 'vless' || proto == 'vmess' || proto == 'trojan' || proto == 'shadowsocks';

  // ---- small helpers ------------------------------------------------------------
  String _numShown(String obj, String key, {String empty = 'Default'}) {
    final n = _intIn(obj, key);
    return n == 0 ? empty : '$n';
  }

  Future<void> _editNum(String obj, String key, String title, {String? hint, int max = 1000000}) async {
    final n = await _askInt(title, _intIn(obj, key), hint: hint, min: 0, max: max, allowEmpty: true);
    if (n != null) _setIn(obj, key, n == 0 ? null : n);
  }

  Future<void> _editTopNum(String key, String title, {String? hint, int max = 3600}) async {
    final n = await _askInt(title, _intOf(key), hint: hint, min: 0, max: max, allowEmpty: true);
    if (n != null) _set(key, n == 0 ? null : n);
  }

  String _rangeShown(String obj, String key, {String empty = ''}) {
    final v = _get(obj, key);
    if (v is List && v.length == 2 && (v[0] != 0 || v[1] != 0)) {
      return v[0] == v[1] ? '${v[0]}' : '${v[0]}-${v[1]}';
    }
    return empty;
  }

  /// A [min, max] pair typed as "100-200" (or one number for both).
  Future<void> _editRange(String obj, String key, String title, {String? hint}) async {
    final v = await _askText(
      title: title,
      hint: hint ?? 'Two numbers as min-max, or one number. Empty clears it.',
      initial: _rangeShown(obj, key),
      monospace: true,
    );
    if (v == null) return;
    if (v.isEmpty) {
      _setIn(obj, key, null);
      return;
    }
    final m = RegExp(r'^(\d+)\s*(?:-\s*(\d+))?$').firstMatch(v);
    if (m == null) {
      _toast('Use min-max, for example 100-200');
      return;
    }
    final a = int.parse(m.group(1)!);
    final b = m.group(2) == null ? a : int.parse(m.group(2)!);
    if (b < a) {
      _toast('The second number must not be smaller than the first');
      return;
    }
    _setIn(obj, key, [a, b]);
  }

  String _headersShown(Object? v) {
    if (v is! Map || v.isEmpty) return '';
    return v.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  /// Header map stored at obj.key, or at the top level when obj is null.
  Future<void> _editHeaders(String? obj, String key, String title) async {
    final cur = obj == null ? _m[key] : _get(obj, key);
    final initial = (cur is Map) ? cur.entries.map((e) => '${e.key}: ${e.value}').join('\n') : '';
    final v = await _askText(
      title: title,
      hint: 'One header per line, as Name: value.',
      initial: initial,
      maxLines: 6,
      monospace: true,
    );
    if (v == null) return;
    final out = <String, String>{};
    for (final line in v.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf(':');
      if (i <= 0) {
        _toast('Each line needs the form Name: value');
        return;
      }
      out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
    }
    if (obj == null) {
      _set(key, out);
    } else {
      _setIn(obj, key, out);
    }
  }

  Widget _headersRow(String? obj, String key) => _row(
        'Custom headers',
        _headersShown(obj == null ? _m[key] : _get(obj, key)),
        () => _editHeaders(obj, key, 'Custom headers'),
        monospace: true,
      );

  // ---- transports ---------------------------------------------------------------
  List<Widget> _wsRows() => [
        _row(
          'Early data (bytes)',
          _numShown('ws', 'maxEarlyData', empty: 'Off'),
          () => _editNum('ws', 'maxEarlyData', 'Early data (bytes)',
              hint: 'Sends up to this many bytes of the first write inside the upgrade request, the ed= of share links. Empty turns it off.'),
        ),
      ];

  List<Widget> _xhttpRows() => [
        _row(
          'Padding bytes',
          _rangeShown('xhttp', 'xPaddingBytes', empty: 'Default (100-1000)'),
          () => _editRange('xhttp', 'xPaddingBytes', 'Padding bytes',
              hint: 'Random padding length as min-max. Empty uses 100-1000.'),
        ),
        _row(
          'Max POST size (bytes)',
          _numShown('xhttp', 'scMaxEachPostBytes', empty: 'Default (1000000)'),
          () => _editNum('xhttp', 'scMaxEachPostBytes', 'Max POST size (bytes)', hint: 'Empty uses 1000000.'),
        ),
        _row(
          'Min POST interval (ms)',
          _numShown('xhttp', 'scMinPostsIntervalMs', empty: 'Default (30)'),
          () => _editNum('xhttp', 'scMinPostsIntervalMs', 'Min POST interval (ms)', hint: 'Empty uses 30.'),
        ),
      ];

  List<Widget> _grpcRows() => [
        _switch(
          'Multi mode',
          'Uses the TunMulti service. The server must use the same mode.',
          _m['grpcMulti'] == true,
          (v) => _set('grpcMulti', v ? true : null),
        ),
      ];

  List<Widget> _quicRows() => [
        _switch(
          'Multi-stream',
          'Reuses one QUIC connection and opens a stream for each connection.',
          _get('quic', 'multiStream') == true,
          (v) => _setIn('quic', 'multiStream', v ? true : null),
        ),
        _row(
          'Keep-alive (s)',
          _numShown('quic', 'keepAliveSec'),
          () => _editNum('quic', 'keepAliveSec', 'Keep-alive (s)',
              hint: 'Seconds between keep-alive packets. Empty uses the default.', max: 3600),
        ),
        _row(
          'Max idle (s)',
          _numShown('quic', 'maxIdleSec'),
          () => _editNum('quic', 'maxIdleSec', 'Max idle (s)',
              hint: 'Seconds without traffic before the connection closes. Empty uses the default.', max: 86400),
        ),
      ];

  List<Widget> _kcpRows() => [
        _row(
          'Header type',
          _label(_kcpHeaders, _gs('kcp', 'header').toLowerCase()),
          () => _pickIn('kcp', 'header', 'Header type', _kcpHeaders),
        ),
        _row(
          'Seed',
          _mask(_gs('kcp', 'seed')),
          () => _editIn('kcp', 'seed', 'Seed',
              hint: 'Must match the server. Empty uses the classic authentication, a value switches to AES-GCM.',
              trim: false),
          monospace: true,
        ),
        _row(
          'MTU',
          _numShown('kcp', 'mtu', empty: 'Default (1350)'),
          () => _editNum('kcp', 'mtu', 'MTU', hint: 'Empty uses 1350.', max: 1500),
        ),
        _row(
          'TTI (ms)',
          _numShown('kcp', 'tti', empty: 'Default (50)'),
          () => _editNum('kcp', 'tti', 'TTI (ms)', hint: 'Time between transmissions. Empty uses 50.', max: 1000),
        ),
        _row(
          'Uplink capacity (MB/s)',
          _numShown('kcp', 'uplinkCapacity', empty: 'Default (5)'),
          () => _editNum('kcp', 'uplinkCapacity', 'Uplink capacity (MB/s)', hint: 'Empty uses 5.'),
        ),
        _row(
          'Downlink capacity (MB/s)',
          _numShown('kcp', 'downlinkCapacity', empty: 'Default (20)'),
          () => _editNum('kcp', 'downlinkCapacity', 'Downlink capacity (MB/s)', hint: 'Empty uses 20.'),
        ),
        _switch(
          'Congestion control',
          'Slows down when the link is congested.',
          _get('kcp', 'congestion') == true,
          (v) => _setIn('kcp', 'congestion', v ? true : null),
        ),
        _row(
          'Read buffer (MB)',
          _numShown('kcp', 'readBufferSize', empty: 'Default (2)'),
          () => _editNum('kcp', 'readBufferSize', 'Read buffer (MB)', hint: 'Empty uses 2.'),
        ),
        _row(
          'Write buffer (MB)',
          _numShown('kcp', 'writeBufferSize', empty: 'Default (2)'),
          () => _editNum('kcp', 'writeBufferSize', 'Write buffer (MB)', hint: 'Empty uses 2.'),
        ),
      ];

  // ---- payload, fragment, mux, advanced ------------------------------------------
  List<Widget> _payloadRows() {
    final p = _m['payload'];
    final tpl = p is Map ? (p['template'] ?? '').toString() : '';
    return [
      _row('HTTP payload', tpl.isEmpty ? 'Off' : tpl.replaceAll('\n', ' '), _openPayload, monospace: true),
    ];
  }

  Future<void> _openPayload() async {
    final p = _m['payload'];
    final init = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _PayloadPage(initial: init, server: _str('server'), port: _intOf('port')),
      ),
    );
    if (res == null || !mounted) return;
    if ((res['template'] ?? '').toString().isEmpty) {
      _set('payload', null);
    } else {
      _set('payload', res);
    }
  }

  List<Widget> _fragmentRows() => [
        _row(
          'Fragment length (bytes)',
          _rangeShown('fragment', 'length', empty: 'Off'),
          () => _editRange('fragment', 'length', 'Fragment length (bytes)',
              hint: 'Splits the TLS ClientHello into pieces of this size, as min-max. Empty turns fragmenting off.'),
        ),
        _row(
          'Fragment interval (ms)',
          _rangeShown('fragment', 'interval', empty: 'Off'),
          () => _editRange('fragment', 'interval', 'Fragment interval (ms)',
              hint: 'Pause between the pieces, as min-max.'),
        ),
      ];

  List<Widget> _muxRows() {
    final on = _get('mux', 'enabled') == true;
    return [
      _switch(
        'Mux.Cool',
        'Carries many connections over one tunnel connection.',
        on,
        (v) {
          if (v && _str('flow').isNotEmpty) {
            _toast('Mux cannot be used with XTLS Vision. Set Flow to None first');
            return;
          }
          _setIn('mux', 'enabled', v ? true : null);
        },
      ),
      if (on)
        _row(
          'Concurrency',
          _numShown('mux', 'concurrency'),
          () => _editNum('mux', 'concurrency', 'Concurrency',
              hint: 'How many connections share one tunnel connection. Empty uses the default.', max: 1024),
        ),
    ];
  }

  List<Widget> _advancedRows() => [
        _row(
          'Connect timeout (s)',
          _m['timeoutSec'] == null ? 'Default (15)' : '${_intOf('timeoutSec')}',
          () => _editTopNum('timeoutSec', 'Connect timeout (s)', hint: 'Empty uses 15.', max: 600),
        ),
        _row('Edit as JSON', 'Backups, SSH algorithms, XHTTP download settings and any other field', _openJson),
      ];
}

/// Editor for the HTTP payload (HTTP-Injector style): template, host, stage
/// and remote proxy. Response checks (expectCodes, responseMap ...) stay in
/// the config untouched and are edited as JSON.
class _PayloadPage extends StatefulWidget {
  const _PayloadPage({required this.initial, required this.server, required this.port});
  final Map<String, dynamic> initial;
  final String server;
  final int port;

  @override
  State<_PayloadPage> createState() => _PayloadPageState();
}

class _PayloadPageState extends State<_PayloadPage> {
  late final Map<String, dynamic> _p = Map<String, dynamic>.from(widget.initial);

  String _s(String k) => (_p[k] ?? '').toString();

  void _put(String k, String v) => setState(() {
        if (v.isEmpty) {
          _p.remove(k);
        } else {
          _p[k] = v;
        }
      });

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _err(Object e) => e is PlatformException ? (e.message ?? e.toString()) : e.toString();

  Future<void> _editTemplate() async {
    final v = await _textDialog(
      context,
      title: 'Payload template',
      hint: 'Sent right after the connection is made. Tags such as [host] and [crlf] are filled in. A preset name starts with @.',
      initial: _s('template'),
      maxLines: 8,
      trim: false,
      monospace: true,
    );
    if (v != null) _put('template', v);
  }

  Future<void> _pickPreset() async {
    var names = <String>[];
    try {
      names = await Bridge.payloadPresets();
    } catch (_) {}
    if (!mounted) return;
    if (names.isEmpty) {
      _toast('No presets available');
      return;
    }
    final opts = [for (final n in names) _Opt(n.startsWith('@') ? n : '@$n', n)];
    final v = await _choiceDialog(context, 'Presets', opts, _s('template'));
    if (v != null) _put('template', v);
  }

  Future<void> _editHost() async {
    final v = await _textDialog(
      context,
      title: 'Host',
      hint: 'Value for [host] and [host_port]. Empty uses the server host.',
      initial: _s('host'),
      monospace: true,
    );
    if (v != null) _put('host', v);
  }

  Future<void> _pickStage() async {
    const opts = <_Opt>[_Opt('pre-tls', 'Before TLS'), _Opt('post-tls', 'After TLS')];
    final v = await _choiceDialog(context, 'Stage', opts, _s('stage').isEmpty ? 'pre-tls' : _s('stage'));
    if (v != null) _put('stage', v == 'pre-tls' ? '' : v);
  }

  Future<void> _editProxy() async {
    final v = await _textDialog(
      context,
      title: 'Remote proxy',
      hint: 'host:port. The connection goes to this proxy and the payload names the real server in [host_port]. Needs the Before TLS stage.',
      initial: _s('proxy'),
      monospace: true,
    );
    if (v == null) return;
    if (v.isNotEmpty && !RegExp(r'^[^:\s]+:\d+$').hasMatch(v)) {
      _toast('Use host:port, for example 10.0.0.1:8080');
      return;
    }
    _put('proxy', v);
  }

  Future<void> _preview() async {
    final t = _s('template');
    if (t.isEmpty) {
      _toast('Write a template first');
      return;
    }
    final host = _s('host').isNotEmpty ? _s('host') : widget.server;
    try {
      final r = await Bridge.previewPayload(t, host, widget.port);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: surfaceHigh,
          shape: _dlgShape,
          title: Text('What is sent', style: serif(22)),
          content: SingleChildScrollView(child: SelectableText(r, style: mono(12.5))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (mounted) _toast(_err(e));
    }
  }

  Future<void> _apply() async {
    final t = _s('template');
    if (t.isNotEmpty) {
      var err = '';
      try {
        err = await Bridge.validatePayload(t);
      } catch (e) {
        err = _err(e);
      }
      if (!mounted) return;
      if (err.isNotEmpty) {
        final ok = await _confirmDialog(context, 'This payload has a problem', err,
            yes: 'Apply anyway', no: 'Keep editing');
        if (!ok || !mounted) return;
      }
    }
    Navigator.pop(context, Map<String, dynamic>.from(_p));
  }

  @override
  Widget build(BuildContext context) {
    final stage = _s('stage') == 'post-tls' ? 'After TLS' : 'Before TLS';
    return Scaffold(
      appBar: AppBar(
        title: Text('HTTP payload', style: serif(22)),
        actions: [
          IconButton(tooltip: 'Preview', icon: const Icon(Icons.visibility_outlined), onPressed: _preview),
          IconButton(
            tooltip: 'Remove payload',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => Navigator.pop(context, <String, dynamic>{}),
          ),
          IconButton(
            tooltip: 'Apply',
            icon: Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary),
            onPressed: _apply,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32),
        children: [
          _rowTile(context, 'Template', _s('template').replaceAll('\n', ' '), _editTemplate, monospace: true),
          _rowTile(context, 'Presets', 'Pick a built-in template such as @ssh-ws', _pickPreset),
          const Divider(height: 1, thickness: 1, color: outline),
          _headerTile(context, 'Options'),
          _rowTile(context, 'Host', _s('host'), _editHost, monospace: true),
          _rowTile(context, 'Stage', stage, _pickStage),
          _rowTile(context, 'Remote proxy', _s('proxy'), _editProxy, monospace: true),
        ],
      ),
    );
  }
}
