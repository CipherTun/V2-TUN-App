import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import 'theme.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _level = 'ALL';
  final _scroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    final lines = st.logs.where((l) => _level == 'ALL' || l.level == _level).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    String two(int n) => n.toString().padLeft(2, '0');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: Row(children: [
          Text('Logs', style: serif(30)),
          const Spacer(),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lines.map((l) => '${l.time.toIso8601String()} ${l.level} ${l.text}').join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied')));
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(tooltip: 'Clear', onPressed: st.clearLogs, icon: const Icon(Icons.delete_sweep_rounded)),
        ]),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: const Text('Detailed logging'),
        subtitle: const Text('Adds every connection, DNS detail and the failover ranking'),
        value: st.logLevel == 'debug',
        onChanged: (v) => st.setLogLevel(v ? 'debug' : 'info'),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          for (final f in const ['ALL', 'D', 'I', 'W', 'E'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(switch (f) { 'D' => 'Debug', 'I' => 'Info', 'W' => 'Warn', 'E' => 'Error', _ => 'All' }),
                selected: _level == f,
                onSelected: (_) => setState(() => _level = f),
              ),
            ),
        ]),
      ),
      Expanded(
        child: lines.isEmpty
            ? Center(child: Text('Nothing logged yet', style: Theme.of(context).textTheme.bodySmall))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final l = lines[i];
                  final c = switch (l.level) { 'E' => googleRed, 'W' => googleYellow, _ => textMuted };
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${two(l.time.hour)}:${two(l.time.minute)}:${two(l.time.second)} ', style: mono(11.5, color: textMuted)),
                      TextSpan(text: '${l.level} ', style: mono(11.5, color: c)),
                      TextSpan(text: l.text, style: mono(11.5, color: textPrimary)),
                    ])),
                  );
                },
              ),
      ),
    ]);
  }
}
