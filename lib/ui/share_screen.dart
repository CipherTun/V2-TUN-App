import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/bridge.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// Shows a config (or any link) as a QR code, with Copy and Share.
///
/// For a config there are two links. The standard one (vless://, vmess://, trojan://, ss://, ...)
/// opens in v2rayNG, Hiddify and most other clients; not every config has one. The V2-TUN link
/// works for every config and keeps all its settings, but only V2-TUN reads it.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.title, this.profile, this.link});
  final String title;
  final Profile? profile;
  final String? link; // used when there is no profile (a subscription URL)

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  String? _standard;
  String? _why;
  bool _native = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    if (p == null) {
      _loading = false;
    } else {
      Bridge.shareLink(p.json, p.name).then((l) {
        if (mounted) setState(() { _standard = l; _loading = false; });
      }).catchError((Object e) {
        if (mounted) {
          setState(() {
            _why = e is PlatformException ? (e.message ?? '$e') : '$e';
            _native = true;
            _loading = false;
          });
        }
      });
    }
  }

  String get _current {
    final p = widget.profile;
    if (p == null) return widget.link ?? '';
    return _native || _standard == null ? AppStore.encodeNativeLink(p) : _standard!;
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final link = _loading ? '' : _current;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        if (p != null) ...[
          Center(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: const Text('Standard link'), enabled: _standard != null),
                const ButtonSegment(value: true, label: Text('V2-TUN link')),
              ],
              selected: {_native || _standard == null},
              onSelectionChanged: (s) => setState(() => _native = s.first),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _loading
                ? ''
                : (_native || _standard == null
                    ? (_why == null
                        ? 'Only V2-TUN can import this link. It keeps every setting of the config.'
                        : 'This config has no standard link ($_why). The V2-TUN link keeps every setting, but only V2-TUN can import it.')
                    : 'Opens in v2rayNG, Hiddify and most other clients.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
        ],
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: SizedBox(
              width: 240,
              height: 240,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : QrImageView(
                      data: link,
                      size: 240,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      errorStateBuilder: (_, __) => Center(
                        child: Text('Too long for a QR code.\nUse Copy or Share.',
                            textAlign: TextAlign.center, style: sans(13, color: Colors.black87)),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onLongPress: link.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: link)).then((_) => _toast('Link copied')),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(link, maxLines: 4, overflow: TextOverflow.ellipsis, style: mono(11.5, color: textMuted)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: link.isEmpty ? null : () async {
                await Clipboard.setData(ClipboardData(text: link));
                _toast('Link copied');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: link.isEmpty ? null : () => Bridge.shareText(link, title: widget.title),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share'),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: warn, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This link holds the server address and its password or key. Anyone who gets it can use the server, so share it only with people you trust.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Builds one link per config (the standard link when there is one) and offers Copy and Share.
Future<void> shareAllConfigs(BuildContext context, AppStore st) async {
  if (st.profiles.isEmpty) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Share all configs?'),
      content: Text('The ${st.profiles.length} links hold server addresses and their passwords or keys. Share them only with people you trust.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final lines = <String>[];
  for (final p in st.profiles) {
    lines.add(await st.standardLink(p) ?? AppStore.encodeNativeLink(p));
  }
  if (!context.mounted) return;
  final text = lines.join('\n');
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy to clipboard'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${lines.length} links copied')));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Share'),
          onTap: () {
            Navigator.pop(ctx);
            Bridge.shareText(text, title: 'V2-TUN configs');
          },
        ),
      ]),
    ),
  );
}
