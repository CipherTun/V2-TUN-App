import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// Other pages import fmtBytes from here.
export 'widgets.dart' show fmtBytes;

/// The dashboard, ported from the Xray design: brand row, connect dial, status, the selected
/// server, live rates, a throughput chart and the routing choice. The dial does not animate.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenConfigs});
  final VoidCallback onOpenConfigs;

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final s = st.settings;
    final sel = st.selected;
    final accent = s.accent;
    final on = st.state == ConnState.connected;
    final busy = st.state == ConnState.connecting || st.state == ConnState.disconnecting;
    final failed = st.state == ConnState.disconnected && st.error != null;

    final (headline, sub) = switch (st.state) {
      ConnState.connected => ('Protected', ''),
      ConnState.connecting => ('Securing connection', 'Checking that traffic passes'),
      ConnState.disconnecting => ('Disconnecting', 'One moment'),
      ConnState.disconnected => failed
          ? ('Could not connect', st.error!)
          : ('Not protected', sel == null ? 'Add a config to begin' : 'Tap the dial to connect'),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
      children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(colors: [accent, steel]),
                ),
                child: Icon(Icons.bolt_rounded, color: onAccent(accent), size: 21),
              ),
              const SizedBox(width: 10),
              Text('V2-TUN', style: serif(26)),
              const SizedBox(width: 10),
              InfoPill(s.mode == 'tun' ? 'TUN' : 'SOCKS5', color: textMuted),
            ]),
          ),
          GlassIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
        const SizedBox(height: 22),
        Center(
          child: ConnectOrb(
            on: on,
            busy: busy,
            accent: accent,
            animate: !s.reduceMotion,
            onTap: () {
              if (s.haptics) HapticFeedback.mediumImpact();
              st.toggle();
            },
          ),
        ),
        const SizedBox(height: 18),
        Center(child: Text(headline, textAlign: TextAlign.center, style: serif(28))),
        const SizedBox(height: 4),
        Center(
          child: on
              ? _Uptime(since: st.connectedAt, color: accent)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    sub,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, color: failed ? bad : textMuted),
                  ),
                ),
        ),
        const SizedBox(height: 22),
        GlassPanel(
          onTap: onOpenConfigs,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: accent.withValues(alpha: .18), borderRadius: BorderRadius.circular(14)),
              child: Icon(sel?.protocol == 'ssh' ? Icons.terminal_rounded : Icons.public_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sel?.name ?? 'No config selected',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(16, w: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(sel == null ? 'Tap to add one' : '${sel.protocol.toUpperCase()}  ·  ${sel.server}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12.5, color: textMuted)),
              ]),
            ),
            if (sel?.pingMs != null) InfoPill(sel!.pingMs! < 0 ? 'Timeout' : '${sel.pingMs} ms', color: latencyColor(sel.pingMs)),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded, color: textMuted),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Stat(icon: Icons.south_rounded, label: 'Download', value: st.downBps, total: st.downBytes, accent: accent, animate: !s.reduceMotion)),
          const SizedBox(width: 12),
          Expanded(child: _Stat(icon: Icons.north_rounded, label: 'Upload', value: st.upBps, total: st.upBytes, accent: accent, animate: !s.reduceMotion)),
        ]),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Throughput', style: sans(13, w: FontWeight.w700, color: textMuted)),
              const Spacer(),
              Text('last ${st.downHistory.length} s', style: sans(12, color: textMuted)),
            ]),
            const SizedBox(height: 8),
            Throughput(st.downHistory, color: accent),
          ]),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Routing', style: sans(13, w: FontWeight.w700, color: textMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, l) in const [('all', 'Everything'), ('lan', 'Skip local network'), ('direct', 'Direct by default')])
                ChoiceChip(
                  label: Text(l),
                  selected: _route(s) == v,
                  onSelected: (_) {
                    switch (v) {
                      case 'all':
                        s.routeDefault = 'proxy';
                        s.bypassLan = false;
                      case 'lan':
                        s.routeDefault = 'proxy';
                        s.bypassLan = true;
                      case 'direct':
                        s.routeDefault = 'direct';
                    }
                    st.saveSettings();
                    if (st.state == ConnState.connected) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('Routing changes apply the next time you connect.')));
                    }
                  },
                  showCheckmark: false,
                  selectedColor: accent.withValues(alpha: .18),
                  labelStyle: sans(12.5, w: FontWeight.w700, color: _route(s) == v ? accent : textPrimary),
                  side: BorderSide(color: _route(s) == v ? accent.withValues(alpha: .5) : glassStroke),
                  backgroundColor: Colors.transparent,
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            const Icon(Icons.data_usage_rounded, size: 20, color: textMuted),
            const SizedBox(width: 10),
            Text('Usage', style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            Text('today ${fmtBytes(st.todayBytes)}  ·  all ${fmtBytes(st.lifetimeBytes)}', style: mono(12.5, color: textPrimary)),
          ]),
        ),
      ],
    );
  }

  static String _route(Settings s) {
    if (s.routeDefault == 'direct') return 'direct';
    return s.bypassLan ? 'lan' : 'all';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.total, required this.accent, required this.animate});
  final IconData icon;
  final String label;
  final double value;
  final int total;
  final Color accent;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(label, style: sans(12.5, w: FontWeight.w700, color: textMuted)),
        ]),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: Duration(milliseconds: animate ? 600 : 0),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text('${fmtBytes(v)}/s', style: mono(17, color: textPrimary).copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 2),
        Text('Total ${fmtBytes(total)}', style: sans(11.5, color: textMuted)),
      ]),
    );
  }
}

/// Session time, counting up once a second while connected.
class _Uptime extends StatefulWidget {
  const _Uptime({required this.since, required this.color});
  final DateTime? since;
  final Color color;
  @override
  State<_Uptime> createState() => _UptimeState();
}

class _UptimeState extends State<_Uptime> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.since == null ? Duration.zero : DateTime.now().difference(widget.since!);
    String two(int n) => n.toString().padLeft(2, '0');
    return Text('${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}',
        style: mono(16, color: widget.color).copyWith(fontWeight: FontWeight.w600));
  }
}
