import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'settings_screen.dart';
import 'theme.dart';

String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble(), i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenConfigs});
  final VoidCallback onOpenConfigs;

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final p = st.selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Row(children: [
          // Settings, top left.
          IconButton.filledTonal(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 14),
          Text('V2-TUN', style: serif(26)),
          const Spacer(),
          _ModeChip(mode: st.settings.mode),
        ]),
        const SizedBox(height: 28),
        const Center(child: ConnectOrb()),
        const SizedBox(height: 22),
        Center(child: _StatusText(st: st)),
        const SizedBox(height: 26),
        _ProfileCard(profile: p, onTap: onOpenConfigs),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat(icon: Icons.south_rounded, label: 'Download', value: st.downBps, total: st.downBytes, color: googleGreen)),
          const SizedBox(width: 12),
          Expanded(child: _Stat(icon: Icons.north_rounded, label: 'Upload', value: st.upBps, total: st.upBytes, color: googleBlue)),
        ]),
        const SizedBox(height: 12),
        _Uptime(since: st.connectedAt),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              const Icon(Icons.data_usage_rounded, size: 20, color: textMuted),
              const SizedBox(width: 10),
              Text('Usage', style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              Text('today ${fmtBytes(st.todayBytes)}  ·  all ${fmtBytes(st.lifetimeBytes)}', style: mono(12.5, color: textPrimary)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});
  final String mode;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(20), border: Border.all(color: outline)),
      child: Text(mode == 'tun' ? 'TUN · system-wide' : 'SOCKS5 · local', style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.st});
  final AppStore st;
  @override
  Widget build(BuildContext context) {
    final (title, sub) = switch (st.state) {
      ConnState.connected => ('Protected', 'Traffic is flowing through the tunnel'),
      ConnState.connecting => ('Connecting', 'Building the tunnel'),
      ConnState.disconnecting => ('Disconnecting', 'Closing the tunnel'),
      ConnState.disconnected => ('Not connected', st.error ?? 'Tap to connect'),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Column(key: ValueKey('$title$sub'), children: [
        Text(title, style: serif(30)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(sub, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: st.error != null && st.state == ConnState.disconnected ? googleRed : null)),
        ),
      ]),
    );
  }
}

/// The big connect button: a rotating ring (Google colors by default), pulsing rings while connected.
class ConnectOrb extends StatefulWidget {
  const ConnectOrb({super.key});
  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _down = false;

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final s = st.settings;
    final on = st.state == ConnState.connected;
    final busy = st.state == ConnState.connecting || st.state == ConnState.disconnecting;
    final calm = s.reduceMotion;
    final colors = ringColors(s);
    final glow = s.isGoogle ? googleBlue : s.accent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        if (s.haptics) HapticFeedback.mediumImpact();
        st.toggle();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 260, height: 260,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _pulse]),
            builder: (context, _) {
              final speed = busy ? 4.0 : (on ? 1.0 : 0.0);
              final angle = calm ? 0.0 : _spin.value * 2 * math.pi * (speed == 0 ? 0.15 : speed);
              return Stack(alignment: Alignment.center, children: [
                if (on && !calm)
                  for (final o in [0.0, 0.5])
                    Builder(builder: (_) {
                      final t = (_pulse.value + o) % 1;
                      return Opacity(
                        opacity: (1 - t) * 0.35,
                        child: Container(
                          width: 190 + 70 * t, height: 190 + 70 * t,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: glow, width: 2)),
                        ),
                      );
                    }),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 206, height: 206,
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                    BoxShadow(color: glow.withValues(alpha: on ? 0.38 : 0.12), blurRadius: on ? 56 : 30, spreadRadius: on ? 4 : 0),
                  ]),
                ),
                SweepRing(angle: angle, size: 206, stroke: 6, colors: colors, opacity: on || busy ? 1 : 0.55),
                Container(
                  width: 176, height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [surfaceHigh, surface], center: const Alignment(-0.3, -0.4)),
                    border: Border.all(color: outline),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                    child: busy
                        ? SizedBox(key: const ValueKey('busy'), width: 44, height: 44,
                            child: CircularProgressIndicator(strokeWidth: 3, color: s.accent))
                        : Icon(Icons.power_settings_new_rounded, key: ValueKey(on), size: 68, color: on ? s.accent : textMuted),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onTap});
  final Profile? profile;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.vpn_key_rounded, color: t.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile?.name ?? 'No config yet', style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(profile == null ? 'Open Configs to add one' : '${profile!.protocol.toUpperCase()} · ${profile!.server}',
                    style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (profile?.pingMs != null) Text(profile!.pingMs! < 0 ? 'timeout' : '${profile!.pingMs} ms', style: mono(12, color: textMuted)),
            const Icon(Icons.chevron_right_rounded, color: textMuted),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.total, required this.color});
  final IconData icon;
  final String label;
  final double value;
  final int total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: t.labelMedium),
          ]),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text('${fmtBytes(v)}/s', style: serif(24)),
          ),
          const SizedBox(height: 2),
          Text('${fmtBytes(total)} total', style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _Uptime extends StatefulWidget {
  const _Uptime({required this.since});
  final DateTime? since;
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          const Icon(Icons.timer_outlined, size: 20, color: textMuted),
          const SizedBox(width: 10),
          Text('Session time', style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          Text('${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}', style: mono(16, color: textPrimary)),
        ]),
      ),
    );
  }
}
