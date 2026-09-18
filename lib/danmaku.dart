import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'service.dart';

class DanmakuNote {
  final int id, timeMs;
  final String text;
  DanmakuNote(this.id, this.timeMs, this.text);
  factory DanmakuNote.fromJson(Map<String, dynamic> j) => DanmakuNote(
      int.parse('${j['id']}'),
      int.parse('${j['position_ms']}'),
      '${j['content']}');
}

List<DanmakuNote> visibleDanmaku(
        List<DanmakuNote> notes, int positionMs, int durationMs) =>
    notes
        .where(
            (n) => positionMs >= n.timeMs && positionMs < n.timeMs + durationMs)
        .toList();

class DanmakuSettings extends ChangeNotifier {
  static final instance = DanmakuSettings();
  bool enabled = true;
  double opacity = 0.85, size = 18, duration = 8;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('dm.enabled') ?? true;
    opacity = (p.getDouble('dm.opacity') ?? 0.85).clamp(0.2, 1);
    size = (p.getDouble('dm.size') ?? 18).clamp(12, 28);
    duration = (p.getDouble('dm.duration') ?? 8).clamp(4, 12);
    notifyListeners();
  }

  Future<void> persist() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('dm.enabled', enabled);
    await p.setDouble('dm.opacity', opacity);
    await p.setDouble('dm.size', size);
    await p.setDouble('dm.duration', duration);
  }
}

class DanmakuLayer extends StatefulWidget {
  final String filmId;
  final int episode;
  final VideoPlayerController controller;
  final Duration Function(Duration)? sourcePosition;
  const DanmakuLayer(
      {super.key,
      required this.filmId,
      required this.episode,
      required this.controller,
      this.sourcePosition});
  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer> {
  List<DanmakuNote> notes = [];
  Timer? timer;
  int window = -1, lastPoll = 0;
  bool fetching = false;
  int request = 0;
  int get positionMs {
    final position = widget.controller.value.position;
    return (widget.sourcePosition?.call(position) ?? position).inMilliseconds;
  }
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      poll();
      if (mounted) setState(() {});
    });
    poll();
  }

  Future<void> poll() async {
    if (!AppService.instance.available ||
        !DanmakuSettings.instance.enabled ||
        fetching) {
      return;
    }
    final position = positionMs;
    final from = math.max(0, (position ~/ 30000) * 30000 - 15000);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (from == window && now - lastPoll < 15000) return;
    final seq = ++request;
    fetching = true;
    lastPoll = now;
    try {
      final r = await AppService.instance.call('danmaku', query: {
        'vod_id': widget.filmId,
        'episode': '${widget.episode}',
        'from_ms': '$from'
      });
      if (mounted && seq == request) {
        setState(() {
          notes = (r['list'] as List)
              .map((j) => DanmakuNote.fromJson(Map<String, dynamic>.from(j)))
              .toList();
          window = from;
        });
      }
    } catch (_) {
      /* Playback continues when the optional danmaku service is offline. */
    } finally {
      fetching = false;
    }
  }

  @override
  void dispose() {
    request++;
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: DanmakuSettings.instance,
      builder: (context, _) {
        final settings = DanmakuSettings.instance;
        if (!settings.enabled) return const SizedBox.shrink();
        final position = positionMs;
        return IgnorePointer(
            child: ClipRect(child: LayoutBuilder(builder: (context, c) {
          final visible = visibleDanmaku(
              notes, position, (settings.duration * 1000).round());
          final lanes = math
              .max(1, ((c.maxHeight - 70) / (settings.size + 10)).floor())
              .clamp(1, 5);
          return Opacity(
              opacity: settings.opacity,
              child: Stack(
                  children: visible.take(30).map((n) {
                final width = n.text.runes.length * settings.size;
                final elapsed =
                    (position - n.timeMs) / (settings.duration * 1000);
                return Positioned(
                    left: c.maxWidth - (c.maxWidth + width) * elapsed,
                    top: 8 + (n.id % lanes) * (settings.size + 10),
                    child: Text(n.text,
                        softWrap: false,
                        style: TextStyle(
                            fontSize: settings.size,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                  blurRadius: 3,
                                  color: Colors.black,
                                  offset: Offset(1, 1))
                            ])));
              }).toList()));
        })));
      });
}

Future<void> showDanmakuSettings(BuildContext context) async {
  final s = DanmakuSettings.instance;
  await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
          animation: s,
          builder: (ctx, _) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SwitchListTile(
                        title: const Text('显示弹幕'),
                        value: s.enabled,
                        onChanged: (v) {
                          s.enabled = v;
                          s.persist();
                        }),
                    const Text('透明度'),
                    Slider(
                        value: s.opacity,
                        min: 0.2,
                        max: 1,
                        onChanged: (v) {
                          s.opacity = v;
                          s.persist();
                        }),
                    const Text('字号'),
                    Slider(
                        value: s.size,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        onChanged: (v) {
                          s.size = v;
                          s.persist();
                        }),
                    const Text('飘过时长（越短越快）'),
                    Slider(
                        value: s.duration,
                        min: 4,
                        max: 12,
                        divisions: 8,
                        label: '${s.duration.round()}秒',
                        onChanged: (v) {
                          s.duration = v;
                          s.persist();
                        })
                  ])))));
}
