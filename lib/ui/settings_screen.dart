import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/store.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final s = st.settings;
    void save() => st.saveSettings();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        _Group('Appearance', [
          _AccentPicker(st: st),
          _Switch('Reduce motion', 'Stop the rotating ring and pulses', s.reduceMotion, (v) { s.reduceMotion = v; save(); }),
          _Switch('Haptic feedback', null, s.haptics, (v) { s.haptics = v; save(); }),
          _Switch('Keep screen on', 'While the app is open', s.keepScreenOn, (v) { s.keepScreenOn = v; save(); Bridge.keepScreenOn(v); }),
        ]),
        _Group('Tunneling', [
          _Choice<String>('Mode', s.mode, const {'tun': 'TUN (system-wide)', 'socks': 'Local SOCKS5'}, (v) { s.mode = v; save(); }),
          if (s.mode == 'tun') ...[
            _Num('MTU', s.mtu, 576, 9000, (v) { s.mtu = v; save(); }),
            _Text('DNS inside the tunnel', s.dns, (v) { s.dns = v; save(); }, hint: '1.1.1.1:53'),
            _Switch('Fake-IP DNS', 'Lets domain rules work for DNS-based apps', s.fakeDns, (v) { s.fakeDns = v; save(); }),
            _Switch('Sniff traffic', 'Needed for protocol rules (http, tls, bittorrent, ssh)', s.sniff, (v) { s.sniff = v; save(); }),
          ] else ...[
            _Text('Listen address', s.socksListen, (v) { s.socksListen = v; save(); }, hint: '127.0.0.1:10808'),
            _Text('Username', s.socksUser, (v) { s.socksUser = v; save(); }),
            _Text('Password', s.socksPass, (v) { s.socksPass = v; save(); }, obscure: true),
            const _Note('Without a username and password, every app on the device can use the listener.'),
          ],
          _Text('Direct DNS (never tunneled)', s.directDns, (v) { s.directDns = v; save(); }, hint: '1.1.1.1:53'),
        ]),
        _Group('Routing', [
          _Choice<String>('Default action', s.routeDefault, const {'proxy': 'Proxy', 'direct': 'Direct'}, (v) { s.routeDefault = v; save(); }),
          _Choice<String>('Domain strategy', s.domainStrategy,
              const {'asis': 'As is', 'ipifnonmatch': 'IP if no match', 'ipondemand': 'IP on demand'}, (v) { s.domainStrategy = v; save(); }),
          _Switch('Bypass LAN', null, s.bypassLan, (v) { s.bypassLan = v; save(); }),
          _Switch('Block QUIC', 'Forces HTTP/3 apps back to TCP', s.blockQuic, (v) { s.blockQuic = v; save(); }),
          _Switch('Block BitTorrent', 'Needs "Sniff traffic"', s.blockBittorrent, (v) { s.blockBittorrent = v; save(); }),
          _Choice<String>('Split tunneling', s.splitMode, const {'off': 'Off', 'bypass': 'Bypass listed', 'only': 'Only listed'}, (v) { s.splitMode = v; save(); }),
          if (s.splitMode != 'off') ...[
            _Text('Domains', s.splitDomains, (v) { s.splitDomains = v; save(); }, hint: 'domain:example.com, keyword:ads', lines: 3),
            _Text('IPs / CIDRs', s.splitIps, (v) { s.splitIps = v; save(); }, hint: '10.0.0.0/8', lines: 3),
          ],
        ]),
        if (s.mode == 'tun')
          _Group('Per-app VPN', [
            _Choice<String>('Apps', s.appMode, const {'all': 'All apps', 'allow': 'Only selected', 'disallow': 'All except selected'}, (v) { s.appMode = v; save(); }),
            if (s.appMode != 'all')
              ListTile(
                title: const Text('Choose apps'),
                subtitle: Text('${s.apps.length} selected'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AppPicker())),
              ),
            _Switch('Exclude V2-TUN itself', 'Recommended', s.excludeSelf, (v) { s.excludeSelf = v; save(); }),
            _Switch('Mark network as metered', null, s.metered, (v) { s.metered = v; save(); }),
          ]),
        _Group('Reliability', [
          _Switch('Pick the fastest config on connect', 'Pings every config first', s.autoFastest, (v) { s.autoFastest = v; save(); }),
          _Switch('Use other configs as backups', 'Failover to up to 4 other configs if this one fails', s.useBackups, (v) { s.useBackups = v; save(); }),
          _Switch('Connection check after connecting', 'Dials through the whole chain and logs the result', s.connectionCheck, (v) { s.connectionCheck = v; save(); }),
          _Num('Update subscriptions every (h, 0 = off)', s.subRefreshHours, 0, 168, (v) { s.subRefreshHours = v; save(); }),
          _Num('Failover timeout (s)', s.failoverTimeoutSec, 3, 120, (v) { s.failoverTimeoutSec = v; save(); }),
          _Num('Latency sort every (s, 0 = off)', s.latencySortSec, 0, 3600, (v) { s.latencySortSec = v; save(); }),
          _Num('WebSocket ping every (s, 0 = off)', s.wsPingSec, 0, 600, (v) { s.wsPingSec = v; save(); }),
          _Num('Idle timeout (s, 0 = off)', s.idleTimeoutSec, 0, 3600, (v) { s.idleTimeoutSec = v; save(); }),
        ]),
        _Group('App behavior', [
          _Switch('Connect on launch', null, s.autoConnect, (v) { s.autoConnect = v; save(); }),
          _Switch('Reconnect when dropped', null, s.reconnectOnDrop, (v) { s.reconnectOnDrop = v; save(); }),
          if (s.reconnectOnDrop) _Num('Reconnect delay (s)', s.reconnectDelaySec, 1, 120, (v) { s.reconnectDelaySec = v; save(); }),
          _Text('Latency test URL', s.pingUrl, (v) { s.pingUrl = v; save(); }),
          _Num('Log lines kept', s.logLimit, 50, 5000, (v) { s.logLimit = v; save(); }),
          ListTile(
            title: const Text('Always-on VPN and kill switch'),
            subtitle: const Text('Android only lets you turn these on in system settings'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 20),
            onTap: Bridge.openVpnSettings,
          ),
        ]),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 0, 8), child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
          Card(child: Column(children: children)),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _Switch extends StatelessWidget {
  const _Switch(this.title, this.sub, this.value, this.onChanged);
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title),
        subtitle: sub == null ? null : Text(sub!),
        value: value,
        onChanged: onChanged,
      );
}

class _Choice<T> extends StatelessWidget {
  const _Choice(this.title, this.value, this.options, this.onChanged);
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(options[value] ?? '$value'),
        trailing: const Icon(Icons.unfold_more_rounded, size: 20),
        onTap: () async {
          final r = await showModalBottomSheet<T>(
            context: context,
            showDragHandle: true,
            backgroundColor: surface,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final e in options.entries)
                  ListTile(
                    title: Text(e.value),
                    trailing: e.key == value ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
              ]),
            ),
          );
          if (r != null) onChanged(r);
        },
      );
}

Future<String?> _prompt(BuildContext context, String title, String initial, {String? hint, bool number = false, bool obscure = false, int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: surface,
      title: Text(title),
      content: TextField(
        controller: c, autofocus: true, obscureText: obscure, maxLines: lines, minLines: 1,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class _Text extends StatelessWidget {
  const _Text(this.title, this.value, this.onChanged, {this.hint, this.obscure = false, this.lines = 1});
  final String title, value;
  final String? hint;
  final bool obscure;
  final int lines;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(value.isEmpty ? (hint ?? 'Not set') : (obscure ? '••••••••' : value), maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () async {
          final r = await _prompt(context, title, value, hint: hint, obscure: obscure, lines: lines);
          if (r != null) onChanged(r);
        },
      );
}

class _Num extends StatelessWidget {
  const _Num(this.title, this.value, this.min, this.max, this.onChanged);
  final String title;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: Text('$value', style: mono(14, color: textPrimary)),
        onTap: () async {
          final r = await _prompt(context, title, '$value', number: true);
          final n = int.tryParse(r ?? '');
          if (n != null) onChanged(n.clamp(min, max));
        },
      );
}

// ---- accent picker ---------------------------------------------------------

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.st});
  final AppStore st;
  @override
  Widget build(BuildContext context) {
    final s = st.settings;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Accent', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(s.accentIndex == customIndex ? 'Custom' : accents[s.accentIndex].name, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < accents.length; i++)
            _Swatch(
              selected: s.accentIndex == i,
              color: accents[i].color,
              google: i == 0,
              onTap: () { s.accentIndex = i; st.saveSettings(); },
            ),
          _Swatch(
            selected: s.accentIndex == customIndex,
            color: Color(s.customAccent),
            custom: true,
            onTap: () async {
              final c = await showModalBottomSheet<Color>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                backgroundColor: surface,
                builder: (_) => _CustomColorSheet(initial: Color(s.customAccent)),
              );
              if (c != null) {
                s.customAccent = c.toARGB32();
                s.accentIndex = customIndex;
                st.saveSettings();
              }
            },
          ),
        ]),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.selected, required this.color, required this.onTap, this.google = false, this.custom = false});
  final bool selected, google, custom;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 44, height: 44,
          padding: EdgeInsets.all(selected ? 4 : 0),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? color : Colors.transparent, width: 2)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: google || custom ? null : color,
              gradient: google ? const SweepGradient(colors: [...googleColors, googleBlue]) : null,
            ),
            child: custom
                ? DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                    child: const Icon(Icons.colorize_rounded, size: 18, color: Colors.black87))
                : (selected ? const Icon(Icons.check_rounded, size: 20, color: Colors.black87) : null),
          ),
        ),
      );
}

class _CustomColorSheet extends StatefulWidget {
  const _CustomColorSheet({required this.initial});
  final Color initial;
  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final hex = TextEditingController(text: _hex(widget.initial));

  static String _hex(Color c) => c.toARGB32().toRadixString(16).substring(2).toUpperCase();

  void _set(HSVColor v) => setState(() {
        hsv = v;
        hex.text = _hex(v.toColor());
      });

  @override
  Widget build(BuildContext context) {
    final c = hsv.toColor();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 74,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: Text('V2-TUN', style: serif(26, color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white)),
        ),
        const SizedBox(height: 18),
        _Slider('Hue', hsv.hue, 360, (v) => _set(hsv.withHue(v)),
            track: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]),
        _Slider('Saturation', hsv.saturation, 1, (v) => _set(hsv.withSaturation(v)),
            track: [HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(), HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor()]),
        _Slider('Brightness', hsv.value, 1, (v) => _set(hsv.withValue(v)),
            track: [Colors.black, HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor()]),
        const SizedBox(height: 8),
        TextField(
          controller: hex,
          maxLength: 6,
          decoration: const InputDecoration(prefixText: '#', labelText: 'Hex', counterText: ''),
          onChanged: (t) {
            final v = int.tryParse(t, radix: 16);
            if (t.length == 6 && v != null) setState(() => hsv = HSVColor.fromColor(Color(0xFF000000 | v)));
          },
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, c), child: const Text('Use this accent'))),
      ]),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider(this.label, this.value, this.max, this.onChanged, {required this.track});
  final String label;
  final double value, max;
  final ValueChanged<double> onChanged;
  final List<Color> track;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 14, activeTrackColor: Colors.transparent, inactiveTrackColor: Colors.transparent),
            child: Stack(alignment: Alignment.center, children: [
              Container(
                height: 14, margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: track)),
              ),
              Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
            ]),
          ),
        ),
      ]);
}

// ---- per-app picker --------------------------------------------------------

class _AppPicker extends StatefulWidget {
  const _AppPicker();
  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  List<Map<dynamic, dynamic>>? _apps;
  String _q = '';
  @override
  void initState() {
    super.initState();
    Bridge.installedApps().then((v) => mounted ? setState(() => _apps = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final sel = st.settings.apps;
    final list = (_apps ?? []).where((a) => '${a['label']}'.toLowerCase().contains(_q.toLowerCase()) || '${a['package']}'.contains(_q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Apps (${sel.length})')),
      body: _apps == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search')),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final pkg = list[i]['package'] as String;
                    return CheckboxListTile(
                      value: sel.contains(pkg),
                      title: Text('${list[i]['label']}'),
                      subtitle: Text(pkg, style: mono(11, color: textMuted)),
                      onChanged: (v) {
                        v == true ? sel.add(pkg) : sel.remove(pkg);
                        st.saveSettings();
                      },
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
