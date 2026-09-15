import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';
import 'library.dart';
import 'playback_session.dart';
import 'danmaku.dart';
import 'service.dart';
import 'account.dart';

class Player extends StatefulWidget {
  final Film film;
  final Episode episode;
  final Library library;
  final int resumeSeconds, episodeIndex;
  final String lineName;
  final VoidCallback? onNext;
  const Player(
      {super.key,
      required this.film,
      required this.episode,
      required this.library,
      this.resumeSeconds = 0,
      this.episodeIndex = 1,
      this.lineName = '',
      this.onNext});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  final session = PlaybackSession.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) open();
    });
  }

  Future<void> open() =>
      session.open(widget.film, widget.episode, widget.library,
          resume: widget.resumeSeconds,
          line: widget.lineName,
          index: widget.episodeIndex);
  @override
  void dispose() {
    if (!session.mini &&
        !session.pipActive &&
        session.episode?.url == widget.episode.url) {
      unawaited(session.pauseAndSave());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: session,
      builder: (context, _) => Column(children: [
            Container(
                color: Colors.black,
                child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: session.error != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Text(session.error!,
                                    textAlign: TextAlign.center),
                                TextButton(
                                    onPressed: () async {
                                      await session.close();
                                      await open();
                                    },
                                    child: const Text('重试'))
                              ]))
                        : !session.ready
                            ? const Center(child: CircularProgressIndicator())
                            : VideoSurface(
                                onNext: widget.onNext,
                                onSendDanmaku: () => send(context),
                                onFullscreen: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                        builder: (_) => Scaffold(
                                            backgroundColor: Colors.black,
                                            body: SafeArea(
                                                child: AnimatedBuilder(
                                                    animation: session,
                                                    builder: (ctx, _) =>
                                                        VideoSurface(
                                                            fullscreen: true,
                                                            onSendDanmaku: () => send(ctx),
                                                            onFullscreen: () =>
                                                                Navigator.pop(
                                                                    ctx)))))))))),
          ]));
  Future<void> send(BuildContext context) async {
    final service = AppService.instance;
    if (!service.loggedIn) {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const AccountPage()));
      return;
    }
    final filmId = widget.film.id, episode = widget.episodeIndex;
    final position = session.controller?.value.position.inMilliseconds ?? 0;
    final text = TextEditingController();
    final content = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('发送弹幕'),
                content: TextField(
                    controller: text,
                    maxLength: 80,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '说说你的看法')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, text.text.trim()),
                      child: const Text('发送'))
                ]));
    // Text controller remains alive until the dialog's closing animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    text.dispose();
    if (content == null || content.isEmpty) return;
    try {
      final r = await service.call('danmaku', body: {
        'vod_id': filmId,
        'episode': '$episode',
        'position_ms': '$position',
        'content': content
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${r['msg']}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class VideoSurface extends StatelessWidget {
  final VoidCallback? onNext;
  final VoidCallback? onSendDanmaku;
  final VoidCallback onFullscreen;
  final bool fullscreen, mini;
  const VideoSurface(
      {super.key,
      this.onNext,
      this.onSendDanmaku,
      required this.onFullscreen,
      this.fullscreen = false,
      this.mini = false});
  String clock(Duration d) =>
      '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Future<void> action(
      BuildContext context, Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('播放操作失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = PlaybackSession.instance, c = session.controller;
    if (c == null) return const SizedBox();
    return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, v, _) =>
            Stack(alignment: Alignment.center, children: [
              Center(
                  child: AspectRatio(
                      aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                      child: VideoPlayer(c))),
              if (!mini && session.film != null)
                Positioned.fill(
                    child: DanmakuLayer(
                        key: ValueKey(
                            '${session.film!.id}:${session.episodeIndex}'),
                        filmId: session.film!.id,
                        episode: session.episodeIndex,
                        controller: c)),
              if (v.isBuffering) const CircularProgressIndicator(),
              if (!mini)
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 18),
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black87, Colors.transparent])),
                        child: Row(children: [
                          IconButton(
                              tooltip: '返回',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back)),
                          Expanded(
                              child: Text(
                                  '${session.film?.name ?? ''}  ${session.episode?.name ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600))),
                          IconButton(
                              tooltip: '播放设置',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => showDanmakuSettings(context),
                              icon: const Icon(Icons.more_vert))
                        ]))),
              if (!mini && v.isPlaying)
                Positioned(
                    left: 18,
                    child: IconButton(
                        tooltip: '快退 10 秒',
                        onPressed: () => action(context, () => c.seekTo(v.position - const Duration(seconds: 10))),
                        icon: const Icon(Icons.replay_10, size: 32))),
              if (!mini && v.isPlaying)
                Positioned(
                    right: 18,
                    child: IconButton(
                        tooltip: '快进 10 秒',
                        onPressed: () => action(context, () => c.seekTo(v.position + const Duration(seconds: 10))),
                        icon: const Icon(Icons.forward_10, size: 32))),
              if (!v.isPlaying && !v.isBuffering)
                IconButton.filled(
                    tooltip: '播放',
                    iconSize: mini ? 24 : 40,
                    onPressed: () => action(context, c.play),
                    icon: const Icon(Icons.play_arrow)),
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (!mini)
                          VideoProgressIndicator(c,
                              allowScrubbing: true,
                              padding:
                                  const EdgeInsets.only(top: 10, bottom: 4),
                              colors: const VideoProgressColors(
                                  playedColor: Color(0xFFFFD16A))),
                        Row(children: [
                          IconButton(
                              tooltip: v.isPlaying ? '暂停' : '播放',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => action(context,
                                  () => v.isPlaying ? c.pause() : c.play()),
                              icon: Icon(v.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow)),
                          Expanded(
                              child: Text(
                                  mini
                                      ? (session.episode?.name ?? '')
                                      : '${clock(v.position)} / ${clock(v.duration)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11))),
                          if (!mini)
                            PopupMenuButton<double>(
                                tooltip: '倍速',
                                onSelected: (s) => action(
                                    context, () => c.setPlaybackSpeed(s)),
                                itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                                    .map((s) => PopupMenuItem(
                                        value: s, child: Text('${s}x')))
                                    .toList(),
                                child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text('${v.playbackSpeed}x',
                                        style: const TextStyle(fontSize: 12)))),
                          if (onNext != null && !mini)
                            IconButton(
                                tooltip: '下一集',
                                visualDensity: VisualDensity.compact,
                                onPressed: onNext,
                                icon: const Icon(Icons.skip_next)),
                          if (!mini)
                            PopupMenuButton<String>(
                                tooltip: '更多',
                                onSelected: (value) {
                                  if (value == 'danmaku') {
                                    showDanmakuSettings(context);
                                  } else if (value == 'send') {
                                    onSendDanmaku?.call();
                                  } else if (value == 'mini') {
                                    session.minimize();
                                    Navigator.maybePop(context);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'danmaku', child: Text('弹幕设置')),
                                  PopupMenuItem(
                                      value: 'send', child: Text('发弹幕')),
                                  PopupMenuItem(
                                      value: 'mini', child: Text('应用小窗')),
                                ],
                                icon: const Icon(Icons.more_horiz)),
                          IconButton(
                              tooltip: fullscreen
                                  ? '退出全屏'
                                  : mini
                                      ? '返回详情'
                                      : '全屏',
                              visualDensity: VisualDensity.compact,
                              onPressed: onFullscreen,
                              icon: Icon(fullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen))
                        ])
                      ])))
            ]));
  }
}

class MiniPlayerHost extends StatefulWidget {
  final Widget child;
  final VoidCallback onExpand;
  const MiniPlayerHost(
      {super.key, required this.child, required this.onExpand});
  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<MiniPlayerHost> {
  Offset offset = const Offset(100, 380);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: PlaybackSession.instance,
      builder: (context, _) => LayoutBuilder(builder: (context, c) {
            final session = PlaybackSession.instance;
            final width = (c.maxWidth - 24).clamp(180.0, 260.0);
            final x = offset.dx
                .clamp(0.0, (c.maxWidth - width).clamp(0.0, double.infinity));
            final y = offset.dy
                .clamp(0.0, (c.maxHeight - 210).clamp(0.0, double.infinity));
            return Stack(children: [
              widget.child,
              if (session.mini && session.ready)
                Positioned(
                    left: x,
                    top: y,
                    width: width,
                    child: Material(
                        elevation: 12,
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          GestureDetector(
                              onPanUpdate: (d) => setState(
                                  () => offset = Offset(x, y) + d.delta),
                              child: Row(children: [
                                const Icon(Icons.drag_indicator, size: 20),
                                Expanded(
                                    child: Text(session.film?.name ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12))),
                                IconButton(
                                    tooltip: '关闭小窗',
                                    onPressed: session.close,
                                    icon: const Icon(Icons.close, size: 18))
                              ])),
                          AspectRatio(
                              aspectRatio: 16 / 9,
                              child: VideoSurface(
                                  mini: true, onFullscreen: widget.onExpand))
                        ])))
            ]);
          }));
}
