import 'dart:convert';
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// Connection test: runs the selected config through DNS, the TCP connection,
/// the payload and the server's reply, TLS, the SSH banner and a real request,
/// one stage at a time, and shows what each one answered.
class DiagnosePage extends StatelessWidget {
  const DiagnosePage({super.key, required this.profile});
  final Profile? profile;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connection test')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            child: profile == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(child: Text('Select a config first', style: Theme.of(context).textTheme.bodySmall)),
                  )
                : _DiagnoseBody(profile!),
          ),
        ),
      );
}

class _DiagnoseBody extends StatefulWidget {
  const _DiagnoseBody(this.p);
  final Profile p;
  @override
  State<_DiagnoseBody> createState() => _DiagnoseBodyState();
}

class _DiagnoseBodyState extends State<_DiagnoseBody> {
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _rep;

  Future<void> _run() async {
    final st = StoreScope.of(context);
    setState(() {
      _busy = true;
      _err = null;
      _rep = null;
    });
    try {
      _rep = jsonDecode(await Bridge.diagnose(st.buildConfig(widget.p), 60)) as Map<String, dynamic>;
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _box(String text, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(16)),
        child: SelectableText(text, style: mono(12.5, color: color)),
      );

  Widget _line(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SelectableText(text, style: mono(12, color: color)),
      );

  Widget _stage(Map<String, dynamic> s) {
    final good = s['ok'] == true;
    final detail = '${s['detail'] ?? ''}';
    final raw = '${s['raw'] ?? ''}'.replaceAll('\r', '').trimRight();
    final error = '${s['error'] ?? ''}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(good ? Icons.check_circle_rounded : Icons.cancel_rounded, color: good ? googleGreen : googleRed, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${s['name']}'.toUpperCase(), style: mono(13, color: textPrimary))),
          Text('${s['ms'] ?? 0} ms', style: mono(12, color: textMuted)),
        ]),
        if (detail.isNotEmpty) _line(detail, textMuted),
        if (raw.isNotEmpty) _line(raw, textPrimary),
        if (error.isNotEmpty) _line(error, googleRed),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = ((_rep?['stages'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final ok = _rep?['ok'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Config: ${widget.p.name}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Text(
        'Tests DNS, the TCP connection, the payload and the server reply, TLS, the SSH banner and a real request, one at a time. It opens a few extra connections to the server.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _run,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow_rounded),
        label: Text(_busy ? 'Testing…' : 'Run test'),
      ),
      if (_err != null) _box(_err!, googleRed),
      if (_rep != null) _box('${_rep!['summary']}', ok ? googleGreen : googleRed),
      for (final s in stages) _stage(s),
    ]);
  }
}
