import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'service.dart';

class Advertising extends StatefulWidget {
  final String slot;
  const Advertising({super.key, required this.slot});
  @override
  State<Advertising> createState() => _AdvertisingState();
}

class _AdvertisingState extends State<Advertising> {
  List<dynamic> ads = [];
  final Set<String> seen = {};
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final data = await AppService.instance.call('ads', query: {'slot': widget.slot});
      if (mounted) setState(() => ads = data['list'] as List? ?? []);
    } catch (_) { /* Optional ads must never block the catalogue. */ }
  }
  Future<void> report(String action, String id) async {
    try { await AppService.instance.call(action, body: {'id': id}); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => Column(children: ads.map((ad) {
    final id = '${ad['id']}';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: InkWell(
      onTap: () async {
        try {
          await const MethodChannel('xingbo/links').invokeMethod<void>('open', '${ad['target_url']}');
          await report('ad_click', id);
        } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此设备无法打开广告链接')));
        }
      },
      child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network('${ad['image_url']}',
          width: double.infinity, height: 100, fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => const SizedBox.shrink(),
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null && seen.add(id)) {
              WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) report('ad_impression', id); });
            }
            return child;
          })),
        const Positioned(right: 6, top: 6, child: ColoredBox(color: Colors.black54, child: Padding(padding: EdgeInsets.all(3), child: Text('广告', style: TextStyle(fontSize: 10))))),
      ]),
    ));
  }).toList());
}
