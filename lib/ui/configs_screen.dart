import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'config_editor.dart';
import 'theme.dart';

class ConfigsScreen extends StatefulWidget {
  const ConfigsScreen({super.key});
  @override
  State<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends State<ConfigsScreen> {
  bool _testing = false;
  String _q = '';

  Future<void> _pingAll(AppStore st) async {
    setState(() => _testing = true);
    for (final p in List.of(st.profiles)) {
      try {
        st.setPing(p, await Bridge.ping(st.buildConfig(p), st.settings.pingUrl));
      } catch (_) {
        st.setPing(p, -1);
      }
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _importClipboard(AppStore st) async {
    final text = (await Clipboard.getData('text/plain'))?.text?.trim() ?? '';
    if (text.isEmpty) return _toast('Clipboard is empty');
    var added = 0;
    var handled = false;
    // A whole JSON config (also pretty-printed over many lines) or a JSON list of configs.
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final v = jsonDecode(text);
        final items = v is List ? v : [v];
        for (final item in items) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final name = (m.remove('name') as String?)?.trim();
          st.addProfile(name?.isNotEmpty == true ? name! : 'Config ${st.profiles.length + 1}', jsonEncode(m));
          added++;
        }
        handled = true;
      } catch (_) {
        // not one JSON value: fall back to one entry per line below
      }
    }
    if (!handled) {
      for (final line in text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty)) {
        try {
          if (line.startsWith('{')) {
            jsonDecode(line);
            st.addProfile('Config ${st.profiles.length + 1}', line);
          } else {
            final m = jsonDecode(await Bridge.parseLink(line)) as Map<String, dynamic>;
            final name = (m.remove('name') as String?)?.trim();
            st.addProfile(name?.isNotEmpty == true ? name! : 'Config ${st.profiles.length + 1}', jsonEncode(m));
          }
          added++;
        } catch (e) {
          st.log('W', 'Import skipped: $e');
        }
      }
    }
    _toast(added == 0 ? 'Nothing importable in the clipboard' : 'Imported $added config${added == 1 ? '' : 's'}');
  }

  bool _match(Profile p) => _q.isEmpty || p.name.toLowerCase().contains(_q) || p.server.toLowerCase().contains(_q);

  Future<void> _addSub(BuildContext context, AppStore st) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Add subscription'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    try {
      final n = await st.addSubscription(name.text.trim().isEmpty ? 'Subscription ${st.subs.length + 1}' : name.text.trim(), url.text.trim());
      _toast('Added $n configs');
    } catch (e) {
      _toast('Could not read the subscription: $e');
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
        child: Row(children: [
          Text('Configs', style: serif(30)),
          const Spacer(),
          IconButton(
            tooltip: 'Test latency',
            onPressed: _testing || st.profiles.isEmpty ? null : () => _pingAll(st),
            icon: _testing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_rounded),
            tooltip: 'Add',
            color: surfaceHigh,
            onSelected: (v) async {
              switch (v) {
                case 'clip':
                  await _importClipboard(st);
                case 'sub':
                  await _addSub(context, st);
                case 'manual':
                  await _editForm(context, st, null);
                case 'json':
                  await _edit(context, st, null);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clip', child: Text('Import from clipboard')),
              PopupMenuItem(value: 'sub', child: Text('Add subscription URL')),
              PopupMenuItem(value: 'manual', child: Text('New config')),
              PopupMenuItem(value: 'json', child: Text('Write JSON')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            color: surfaceHigh,
            onSelected: (v) async {
              switch (v) {
                case 'fast':
                  setState(() => _testing = true);
                  final f = await st.pickFastest();
                  if (mounted) {
                    setState(() => _testing = false);
                    _toast(f == null ? 'No config answered' : 'Selected "${f.name}" (${f.pingMs} ms)');
                  }
                case 'sort':
                  st.sortByPing();
                case 'refresh':
                  for (final sub in List.of(st.subs)) {
                    try {
                      await st.refreshSubscription(sub);
                    } catch (e) {
                      _toast('${sub.name}: $e');
                    }
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'fast', child: Text('Select fastest')),
              const PopupMenuItem(value: 'sort', child: Text('Sort by latency')),
              if (st.subs.isNotEmpty) const PopupMenuItem(value: 'refresh', child: Text('Update subscriptions')),
            ],
          ),
        ]),
      ),
      if (st.profiles.length > 4)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search configs'),
          ),
        ),
      if (st.subs.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final sub in st.subs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  avatar: const Icon(Icons.rss_feed_rounded, size: 16),
                  label: Text(sub.name),
                  onPressed: () async {
                    try {
                      final n = await st.refreshSubscription(sub);
                      _toast('${sub.name}: $n configs');
                    } catch (e) {
                      _toast('${sub.name}: $e');
                    }
                  },
                  onDeleted: () => st.removeSubscription(sub),
                ),
              ),
          ]),
        ),
      Expanded(
        child: st.profiles.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.dns_outlined, size: 56, color: textMuted),
                  const SizedBox(height: 12),
                  Text('No configs yet', style: serif(22)),
                  const SizedBox(height: 4),
                  Text('Copy a share link (vless, vmess, trojan, ss, ssh,\nsocks, http, hysteria) and tap import.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: () => _importClipboard(st), icon: const Icon(Icons.content_paste_go_rounded), label: const Text('Import from clipboard')),
                ]),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                itemCount: st.profiles.where(_match).length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = st.profiles.where(_match).elementAt(i);
                  final sel = st.selected?.id == p.id;
                  return Dismissible(
                    key: ValueKey(p.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(color: googleRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(22)),
                      child: const Icon(Icons.delete_rounded, color: googleRed),
                    ),
                    onDismissed: (_) {
                      final index = st.profiles.indexOf(p);
                      final wasSelected = st.selected?.id == p.id;
                      st.removeProfile(p);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Deleted "${p.name}"'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => st.restoreProfile(p, index, select: wasSelected),
                        ),
                      ));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: surface, borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: sel ? st.settings.accent : outline, width: sel ? 1.6 : 1),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        contentPadding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
                        onTap: () => st.select(p),
                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${p.protocol.toUpperCase()} \u00b7 ${p.server}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (p.pingMs != null)
                            Text(p.pingMs! < 0 ? 'timeout' : '${p.pingMs} ms',
                                style: mono(12, color: p.pingMs! < 0 ? googleRed : (p.pingMs! < 300 ? googleGreen : googleYellow))),
                          IconButton(icon: const Icon(Icons.copy_all_outlined), tooltip: 'Duplicate', onPressed: () => st.duplicateProfile(p)),
                          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => _editForm(context, st, p)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  /// Opens the row-based editor. A config whose JSON is not an object (or does
  /// not parse) falls back to the raw JSON editor so it can still be repaired.
  Future<void> _editForm(BuildContext context, AppStore st, Profile? p) async {
    if (p != null) {
      var ok = false;
      try {
        ok = jsonDecode(p.json) is Map;
      } catch (_) {}
      if (!ok) {
        _toast('This config is not a JSON object, opening the raw editor');
        return _edit(context, st, p);
      }
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ConfigEditorScreen(profile: p)),
    );
  }

  Future<void> _edit(BuildContext context, AppStore st, Profile? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final json = TextEditingController(
        text: p == null ? '{\n  "protocol": "vless",\n  "server": "",\n  "port": 443\n}' : const JsonEncoder.withIndent('  ').convert(jsonDecode(p.json)));
    String? err;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: surface,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p == null ? 'New config' : 'Edit config', style: serif(24)),
            const SizedBox(height: 14),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(
              controller: json, minLines: 8, maxLines: 14, style: mono(12.5), autocorrect: false, enableSuggestions: false,
              decoration: InputDecoration(labelText: 'Config JSON', errorText: err),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final r = await Bridge.validate(json.text);
                    set(() => err = r.isEmpty ? null : r);
                    if (r.isEmpty && ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Config is valid')));
                    }
                  },
                  child: const Text('Validate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    try {
                      jsonDecode(json.text);
                    } catch (e) {
                      set(() => err = 'Not valid JSON');
                      return;
                    }
                    final n = name.text.trim().isEmpty ? 'Config ${st.profiles.length + 1}' : name.text.trim();
                    p == null ? st.addProfile(n, json.text) : st.updateProfile(p, name: n, json: json.text);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
            ]),
          ]),
        );
      }),
    );
  }
}
