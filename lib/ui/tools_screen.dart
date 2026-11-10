import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'dashboard_screen.dart' show fmtBytes;
import 'diagnose_screen.dart';
import 'theme.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final p = st.selected;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final tiles = <(IconData, String, String, VoidCallback)>[
      (Icons.troubleshoot_rounded, 'Connection test', 'Test each layer of the selected config and see what the server answers', () => open(DiagnosePage(profile: p))),
      (Icons.speed_rounded, 'Speed test', 'Download speed through the selected config', () => open(_Page('Speed test', _SpeedTool(p)))),
      (Icons.radar_rounded, 'Host scanner', 'Find bug hosts a network lets through', () => open(_Page('Host scanner', _ScanTool(p)))),
      (Icons.code_rounded, 'Payload lab', 'Preview and validate payload templates', () => open(_Page('Payload lab', _PayloadTool(p)))),
      (Icons.alt_route_rounded, 'Route explainer', 'See how a connection would be routed', () => open(_Page('Route explainer', const _RouteTool()))),
      (Icons.rule_rounded, 'Live routing rules', 'Edit routing without reconnecting', () => open(_Page('Live routing rules', const _LiveRoutingTool()))),
      (Icons.list_alt_rounded, 'Route lists', 'Feed list:NAME, geoip:XX and geosite:XX entries', () => open(_Page('Route lists', const _RouteListTool()))),
      (Icons.backup_rounded, 'Backup and restore', 'Copy or paste configs, subscriptions and settings', () => open(_Page('Backup and restore', const _BackupTool()))),
      (Icons.shield_moon_outlined, 'System VPN settings', 'Always-on VPN and block connections without VPN', () => Bridge.openVpnSettings()),
      (Icons.restart_alt_rounded, 'Reset traffic counters', 'Zero the upload and download totals', () => Bridge.resetTraffic()),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Text('Tools', style: serif(30)),
        const SizedBox(height: 14),
        for (final t in tiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: st.settings.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                  child: Icon(t.$1, color: st.settings.accent),
                ),
                title: Text(t.$2),
                subtitle: Text(t.$3),
                trailing: const Icon(Icons.chevron_right_rounded, color: textMuted),
                onTap: t.$4,
              ),
            ),
          ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const _Page(this.title, this.child);
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), child: child)),
      );
}

Widget _out(String text, {bool error = false}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(16)),
      child: SelectableText(text, style: mono(12.5, color: error ? googleRed : textPrimary)),
    );

class _NeedsConfig extends StatelessWidget {
  const _NeedsConfig();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: Text('Select a config first', style: Theme.of(context).textTheme.bodySmall)),
      );
}

class _SpeedTool extends StatefulWidget {
  const _SpeedTool(this.p);
  final Profile? p;
  @override
  State<_SpeedTool> createState() => _SpeedToolState();
}

class _SpeedToolState extends State<_SpeedTool> {
  String? _res;
  bool _err = false, _busy = false;
  @override
  Widget build(BuildContext context) {
    if (widget.p == null) return const _NeedsConfig();
    final st = StoreScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Config: ${widget.p!.name}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() { _busy = true; _res = null; });
                try {
                  final m = jsonDecode(await Bridge.speedTest(st.buildConfig(widget.p!), 10)) as Map<String, dynamic>;
                  _res = '${(m['bps'] / 1e6).toStringAsFixed(2)} Mbit/s\n${fmtBytes(m['bytes'])} in 10 s';
                  _err = false;
                } catch (e) {
                  _res = e.toString();
                  _err = true;
                }
                if (mounted) setState(() => _busy = false);
              },
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
        label: Text(_busy ? 'Measuring…' : 'Start'),
      ),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}

class _ScanTool extends StatefulWidget {
  const _ScanTool(this.p);
  final Profile? p;
  @override
  State<_ScanTool> createState() => _ScanToolState();
}

class _ScanToolState extends State<_ScanTool> {
  final _hosts = TextEditingController();
  final _target = TextEditingController(text: 'https://www.gstatic.com/generate_204');
  String _field = 'payload.host';
  bool _busy = false;
  List<Map<String, dynamic>> _res = [];
  String? _err;

  @override
  Widget build(BuildContext context) {
    if (widget.p == null) return const _NeedsConfig();
    final st = StoreScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: _field,
        decoration: const InputDecoration(labelText: 'Field to replace'),
        items: const ['payload.host', 'tls.sni', 'ws.host', 'payload.proxy', 'server']
            .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => setState(() => _field = v!),
      ),
      const SizedBox(height: 10),
      TextField(controller: _target, decoration: const InputDecoration(labelText: 'Target (URL or host:port)')),
      const SizedBox(height: 10),
      TextField(controller: _hosts, minLines: 5, maxLines: 10, style: mono(12.5), decoration: const InputDecoration(labelText: 'Hosts, one per line')),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() { _busy = true; _err = null; _res = []; });
                try {
                  final r = jsonDecode(await Bridge.scanHosts(st.buildConfig(widget.p!), _field, _hosts.text, _target.text.trim(), 3, 15)) as List;
                  _res = r.cast<Map<String, dynamic>>()..sort((a, b) {
                    if (a['ok'] != b['ok']) return a['ok'] == true ? -1 : 1;
                    return ((a['ms'] ?? 0) as num).compareTo((b['ms'] ?? 0) as num);
                  });
                } catch (e) {
                  _err = e.toString();
                }
                if (mounted) setState(() => _busy = false);
              },
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar_rounded),
        label: Text(_busy ? 'Scanning…' : 'Scan'),
      ),
      if (_err != null) _out(_err!, error: true),
      for (final r in _res)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(r['ok'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, color: r['ok'] == true ? googleGreen : googleRed),
          title: Text('${r['value']}', style: mono(13, color: textPrimary)),
          subtitle: r['ok'] == true ? null : Text('${r['error'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: r['ok'] == true ? Text('${r['ms']} ms', style: mono(12, color: textMuted)) : null,
        ),
    ]);
  }
}

class _PayloadTool extends StatefulWidget {
  const _PayloadTool(this.p);
  final Profile? p;
  @override
  State<_PayloadTool> createState() => _PayloadToolState();
}

class _PayloadToolState extends State<_PayloadTool> {
  final _tpl = TextEditingController(
      text: 'CONNECT [server_host_port] [protocol][crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]');
  final _host = TextEditingController(text: 'bug.example.com');
  final _server = TextEditingController(text: 'ssh.example.com');
  String? _res;
  bool _err = false;

  Future<void> _preview() async {
    try {
      final bad = await Bridge.validatePayload(_tpl.text);
      if (bad.isNotEmpty) throw bad;
      _res = await Bridge.previewPayload(_tpl.text, _host.text, _server.text, 443);
      _err = false;
    } catch (e) {
      _res = e.toString();
      _err = true;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _tpl, minLines: 3, maxLines: 8, style: mono(12.5), decoration: const InputDecoration(labelText: 'Template')),
      const SizedBox(height: 10),
      TextField(controller: _host, decoration: const InputDecoration(labelText: 'Host (bug host, [host])')),
      const SizedBox(height: 10),
      TextField(controller: _server, decoration: const InputDecoration(labelText: 'Server ([server])')),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: FilledButton(onPressed: _preview, child: const Text('Preview'))),
        if (widget.p != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                try {
                  _res = await Bridge.payloadPreview(StoreScope.of(context).buildConfig(widget.p!));
                  _err = false;
                } catch (e) {
                  _res = e.toString();
                  _err = true;
                }
                if (mounted) setState(() {});
              },
              child: const Text('From config'),
            ),
          ),
        ],
      ]),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}

class _RouteTool extends StatefulWidget {
  const _RouteTool();
  @override
  State<_RouteTool> createState() => _RouteToolState();
}

class _RouteToolState extends State<_RouteTool> {
  final _addr = TextEditingController(text: 'example.com:443');
  String _net = 'tcp', _proto = '';
  String? _res;
  bool _err = false;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Works while connected.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(controller: _addr, decoration: const InputDecoration(labelText: 'host:port')),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'tcp', label: Text('TCP')), ButtonSegment(value: 'udp', label: Text('UDP'))],
        selected: {_net},
        onSelectionChanged: (v) => setState(() => _net = v.first),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _proto,
        decoration: const InputDecoration(labelText: 'Sniffed protocol'),
        items: const ['', 'http', 'tls', 'bittorrent', 'ssh'].map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? 'none' : e))).toList(),
        onChanged: (v) => setState(() => _proto = v ?? ''),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () async {
          try {
            _res = const JsonEncoder.withIndent('  ').convert(jsonDecode(await Bridge.explainRoute(_net, _addr.text.trim(), _proto)));
            _err = false;
          } catch (e) {
            _res = e.toString();
            _err = true;
          }
          if (mounted) setState(() {});
        },
        child: const Text('Explain'),
      ),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}

class _LiveRoutingTool extends StatefulWidget {
  const _LiveRoutingTool();
  @override
  State<_LiveRoutingTool> createState() => _LiveRoutingToolState();
}

class _LiveRoutingToolState extends State<_LiveRoutingTool> {
  final _c = TextEditingController(
      text: '{\n  "default": "proxy",\n  "bypassLan": true,\n  "rules": [\n    {"action": "block", "domain": ["keyword:ads."]}\n  ]\n}');
  String? _res;
  bool _err = false;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Applies to the running tunnel. It lasts until the next connect, which uses your Settings again.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(controller: _c, minLines: 10, maxLines: 18, style: mono(12.5), autocorrect: false, decoration: const InputDecoration(labelText: 'routing JSON')),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () async {
          try {
            jsonDecode(_c.text);
            await Bridge.updateRouting(_c.text);
            _res = 'Applied';
            _err = false;
          } catch (e) {
            _res = e.toString();
            _err = true;
          }
          if (mounted) setState(() {});
        },
        child: const Text('Apply now'),
      ),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}

class _RouteListTool extends StatefulWidget {
  const _RouteListTool();
  @override
  State<_RouteListTool> createState() => _RouteListToolState();
}

class _RouteListToolState extends State<_RouteListTool> {
  final _name = TextEditingController(text: 'list:local-sites');
  final _items = TextEditingController();
  String? _res;
  bool _err = false;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('One entry per line: domain:x.com, full:a.b.com, keyword:ads, or CIDRs. Connect first.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'List name (list:NAME, geoip:XX, geosite:XX)')),
      const SizedBox(height: 10),
      TextField(controller: _items, minLines: 8, maxLines: 16, style: mono(12.5), autocorrect: false, decoration: const InputDecoration(labelText: 'Entries')),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () async {
          try {
            await Bridge.setRouteList(_name.text.trim(), _items.text);
            _res = 'Loaded';
            _err = false;
          } catch (e) {
            _res = e.toString();
            _err = true;
          }
          if (mounted) setState(() {});
        },
        child: const Text('Load list'),
      ),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}

class _BackupTool extends StatefulWidget {
  const _BackupTool();
  @override
  State<_BackupTool> createState() => _BackupToolState();
}

class _BackupToolState extends State<_BackupTool> {
  String? _res;
  bool _err = false;
  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('The backup holds config passwords and keys in plain text. Keep it private.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 14),
      FilledButton.icon(
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copy backup'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: st.exportBackup()));
          setState(() { _res = 'Copied to the clipboard'; _err = false; });
        },
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.content_paste_rounded),
        label: const Text('Restore from clipboard'),
        onPressed: () async {
          try {
            final t = (await Clipboard.getData('text/plain'))?.text ?? '';
            st.importBackup(t);
            _res = 'Restored ${st.profiles.length} configs';
            _err = false;
          } catch (e) {
            _res = 'The clipboard does not hold a V2-TUN backup';
            _err = true;
          }
          if (mounted) setState(() {});
        },
      ),
      if (_res != null) _out(_res!, error: _err),
    ]);
  }
}
