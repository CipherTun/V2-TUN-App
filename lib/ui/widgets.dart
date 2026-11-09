import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

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

Color latencyColor(int? ms) {
  if (ms == null) return textMuted;
  if (ms < 0) return bad;
  if (ms < 150) return good;
  if (ms < 350) return warn;
  return bad;
}

/// Page background: a steel gradient with two soft blooms. Painted once behind the navigator.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.accent, required this.child});
  final Color accent;
  final Widget child;

  Widget _bloom(Color c, double size, double a) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: a), c.withValues(alpha: 0)]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bg, bgBottom]),
          ),
        ),
        Positioned(top: -140, right: -120, child: _bloom(accent, 440, .26)),
        Positioned(bottom: 40, left: -180, child: _bloom(steel, 520, .34)),
        child,
      ],
    );
  }
}

/// Frosted glass surface.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.onTap,
    this.tint,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            color: tint ?? glass,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: .07), Colors.white.withValues(alpha: 0)],
            ),
            border: Border.all(color: glassStroke),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: br,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(label, style: sans(11.5, w: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GlassPanel(
        radius: 99,
        padding: const EdgeInsets.all(11),
        onTap: onTap,
        child: Icon(icon, size: 21, color: textPrimary),
      ),
    );
  }
}

/// The connect button: a dial of ticks around a lens-like core. It is drawn once and never
/// animates, so nothing sweeps or pulses around it while the tunnel comes up or runs.
class ConnectOrb extends StatefulWidget {
  const ConnectOrb({
    super.key,
    required this.on,
    required this.busy,
    required this.accent,
    required this.onTap,
    this.size = 190,
    this.animate = true,
  });
  final bool on, busy, animate;
  final Color accent;
  final VoidCallback onTap;
  final double size;
  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: w.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: Duration(milliseconds: w.animate ? 140 : 0),
        curve: Curves.easeOut,
        child: SizedBox(
          width: w.size,
          height: w.size,
          child: Stack(alignment: Alignment.center, children: [
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(w.size),
                painter: _OrbPainter(on: w.on, busy: w.busy, hue: w.accent),
              ),
            ),
            w.busy
                ? SizedBox(
                    width: w.size * .15,
                    height: w.size * .15,
                    child: const CircularProgressIndicator(strokeWidth: 2.6, color: textPrimary),
                  )
                : Icon(
                    w.on ? Icons.shield_rounded : Icons.power_settings_new_rounded,
                    size: w.size * .21,
                    color: w.on ? onAccent(w.accent) : textPrimary,
                  ),
          ]),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.on, required this.busy, required this.hue});
  final bool on, busy;
  final Color hue;

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = size.center(Offset.zero);
    final r = size.width / 2;

    // Steady glow.
    final glowA = on ? .36 : (busy ? .22 : .10);
    canvas.drawCircle(
      ctr,
      r * .95,
      Paint()
        ..shader = RadialGradient(colors: [hue.withValues(alpha: (glowA * 1.6).clamp(0.0, 1.0)), hue.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: ctr, radius: r)),
    );

    // Tick dial: all ticks lit while connected, half lit while working, dim otherwise.
    const n = 72;
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi - math.pi / 2;
      final major = i % 6 == 0;
      final r1 = r * (major ? .80 : .84), r2 = r * .91;
      final color = on
          ? hue.withValues(alpha: major ? 1.0 : .75)
          : busy
              ? hue.withValues(alpha: major ? .55 : .35)
              : textMuted.withValues(alpha: major ? .45 : .22);
      canvas.drawLine(
        ctr + Offset(math.cos(a), math.sin(a)) * r1,
        ctr + Offset(math.cos(a), math.sin(a)) * r2,
        Paint()
          ..color = color
          ..strokeWidth = major ? 2.4 : 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(ctr, r * .97, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = textMuted.withValues(alpha: .18));

    // Core lens.
    final core = r * .60;
    final rect = Rect.fromCircle(center: ctr, radius: core);
    final Gradient fill = on
        ? RadialGradient(
            center: const Alignment(-.35, -.4),
            radius: 1.1,
            colors: [Color.lerp(hue, Colors.white, .30)!, hue, Color.lerp(hue, Colors.black, .35)!],
          )
        : const RadialGradient(
            center: Alignment(-.35, -.4),
            radius: 1.1,
            colors: [Color(0xFF34455B), Color(0xFF1B2636), Color(0xFF0E141D)],
          );
    canvas.drawShadow(Path()..addOval(rect), (on ? hue : Colors.black).withValues(alpha: .5), 18, true);
    canvas.drawCircle(ctr, core, Paint()..shader = fill.createShader(rect));
    canvas.drawCircle(
      ctr,
      core,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(colors: [
          Colors.white.withValues(alpha: .5),
          Colors.white.withValues(alpha: .02),
          Colors.white.withValues(alpha: .3),
        ]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter o) => o.on != on || o.busy != busy || o.hue != hue;
}

/// A smooth filled line chart of the last samples.
class Throughput extends StatelessWidget {
  const Throughput(this.values, {super.key, required this.color, this.height = 64});
  final List<double> values;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _ChartPainter(values, color)));
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.v, this.c);
  final List<double> v;
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) return;
    final mx = math.max(v.fold<double>(0, math.max), 1024.0);
    final pts = [for (var i = 0; i < v.length; i++) Offset(i / (v.length - 1) * s.width, s.height - 4 - (v[i] / mx) * (s.height - 10))];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final m = (pts[i - 1] + pts[i]) / 2;
      path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, m.dx, m.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    final fill = Path.from(path)..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
    canvas.drawPath(
      fill,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .35), c.withValues(alpha: 0)]).createShader(Offset.zero & s),
    );
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..color = c);
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.v != v || o.c != c;
}
