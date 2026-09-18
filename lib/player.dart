import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';
import 'library.dart';
import 'playback_session.dart';
import 'danmaku.dart';
import 'service.dart';
import 'account.dart';
import 'advertising.dart';
import 'episode_picker.dart';
import 'immersive_controls.dart';
import 'fullscreen_player.dart';
import 'player_gestures.dart';
import 'player_options.dart';
import 'playback_rules.dart';

class Player extends StatefulWidget {
  final Film film;
  final Episode episode;
  final Library library;
  final int resumeSeconds, episodeIndex;
  final String lineName;
  final VoidCallback? onNext;
  final void Function(int line, int episode)? onSelectEpisode;
  const Player(
      {super.key,
      required this.film,
      required this.episode,
      required this.library,
      this.resumeSeconds = 0,
      this.episodeIndex = 1,
      this.lineName = '',
      this.onNext,
      this.onSelectEpisode});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> with WidgetsBindingObserver {
  final session = PlaybackSession.instance;
  bool _fullscreenOpen = false;
  bool _landscapeHandled = false;
  bool _autoFullscreenSuppressed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) open();
    });
  }

  Future<void> open() =>
      session.open(widget.film, widget.episode, widget.library,
          resume: widget.resumeSeconds,
          line: widget.lineName,
          index: widget.episodeIndex,
          onCompleted: widget.onNext);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    if (!session.pipActive && session.episode?.url == widget.episode.url) {
      unawaited(session.pauseAndSave());
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      if (size.width <= size.height) {
        _landscapeHandled = false;
      } else if (!_landscapeHandled &&
          !_autoFullscreenSuppressed &&
          !_fullscreenOpen &&
          session.ready &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _landscapeHandled = true;
        unawaited(showFullscreen());
      }
    });
  }

  Future<void> showFullscreen() async {
    if (_fullscreenOpen) return;
    _fullscreenOpen = true;
    _landscapeHandled = true;
    final select = widget.onSelectEpisode;
    try {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => FullscreenPlayer(
                  builder: (ctx) => AnimatedBuilder(
                      animation: session,
                      builder: (surfaceContext, child) => VideoSurface(
                          onSelectEpisode: select,
                          onNext: fullscreenNext(select),
                          fullscreen: true,
                          onSendDanmaku: () => send(ctx),
                          onFullscreen: () => FullscreenPlayer.exit(ctx))))));
    } finally {
      // An explicit exit must win over the phone still being held sideways.
      // Manual fullscreen remains available from the player button.
      _autoFullscreenSuppressed = true;
      _fullscreenOpen = false;
    }
  }

  VoidCallback? fullscreenNext(void Function(int, int)? select) {
    if (select == null) return null;
    final lines = session.film?.lines ?? <PlayLine>[];
    for (var line = 0; line < lines.length; line++) {
      if (lines[line].name != session.lineName) continue;
      final index = lines[line]
          .episodes
          .indexWhere((episode) => episode.url == session.episode?.url);
      if (index >= 0 && index + 1 < lines[line].episodes.length) {
        return () => select(line, index + 1);
      }
    }
    return null;
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
                                onSelectEpisode: widget.onSelectEpisode,
                                onNext: widget.onNext,
                                onSendDanmaku: () => send(context),
                                onFullscreen: showFullscreen))),
            const Advertising(slot: 'player_bottom'),
          ]));
  Future<void> send(BuildContext context) async {
    final service = AppService.instance;
    if (!service.loggedIn) {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const AccountPage()));
      return;
    }
    final filmId = session.film?.id, episode = session.episodeIndex;
    if (filmId == null) return;
    final position = session
        .sourcePosition(session.controller?.value.position ?? Duration.zero)
        .inMilliseconds;
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

class VideoSurface extends StatefulWidget {
  final void Function(int line, int episode)? onSelectEpisode;
  final VoidCallback? onNext;
  final VoidCallback? onSendDanmaku;
  final VoidCallback onFullscreen;
  final bool fullscreen, mini;
  const VideoSurface(
      {super.key,
      this.onNext,
      this.onSelectEpisode,
      this.onSendDanmaku,
      required this.onFullscreen,
      this.fullscreen = false,
      this.mini = false});
  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  bool locked = false;
  bool get mini => widget.mini;
  bool get fullscreen => widget.fullscreen;
  VoidCallback get onFullscreen => widget.onFullscreen;
  VoidCallback? get onNext => widget.onNext;
  VoidCallback? get onSendDanmaku => widget.onSendDanmaku;
  void Function(int, int)? get onSelectEpisode => widget.onSelectEpisode;
  String clock(Duration d) =>
      '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Future<void> selectEpisode(BuildContext context) async {
    final session = PlaybackSession.instance;
    final lines = session.film?.lines ?? <PlayLine>[];
    if (lines.isEmpty) return;
    final choice = await showModalBottomSheet<EpisodeChoice>(
        context: context,
        isScrollControlled: true,
        builder: (_) => EpisodePicker(
            lines: lines,
            currentUrl: session.episode?.url ?? '',
            currentLine: session.lineName));
    if (choice != null && context.mounted) {
      onSelectEpisode?.call(choice.line, choice.episode);
    }
  }

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

  Future<void> showSkipSettings(BuildContext context) async {
    final session = PlaybackSession.instance;
    final filmId = session.film?.id;
    final settings = await showModalBottomSheet<SkipSettings>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SkipSettingsSheet(settings: session.skipSettings));
    if (settings != null && context.mounted && session.film?.id == filmId) {
      await action(context, () => session.updateSkipSettings(settings));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = PlaybackSession.instance, c = session.controller;
    if (c == null) return const SizedBox();
    return PopScope(
        canPop: !locked,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && locked) setState(() => locked = false);
        },
        child: ImmersiveControls(
            playback: c,
            builder: (context, controlsVisible, toggleControls) =>
                ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, v, _) =>
                        Stack(alignment: Alignment.center, children: [
                          Center(
                              child: AspectRatio(
                                  aspectRatio: v.aspectRatio > 0
                                      ? v.aspectRatio
                                      : 16 / 9,
                                  child: VideoPlayer(c))),
                          if (!mini && session.film != null)
                            Positioned.fill(
                                child: DanmakuLayer(
                                    key: ValueKey(
                                        '${session.film!.id}:${session.episodeIndex}'),
                                    filmId: session.film!.id,
                                    episode: session.episodeIndex,
                                    controller: c,
                                    sourcePosition: session.sourcePosition)),
                          if (v.isBuffering) const CircularProgressIndicator(),
                          Positioned.fill(
                              child: locked
                                  ? GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: toggleControls,
                                      child: const SizedBox.expand())
                                  : PlayerGestures(
                                      key: ObjectKey(c),
                                      controller: c,
                                      onTap: toggleControls)),
                          if (fullscreen && controlsVisible)
                            Positioned(
                                left: MediaQuery.paddingOf(context).left + 12,
                                top: 70,
                                child: IconButton.filledTonal(
                                    tooltip: locked ? '解锁' : '锁定屏幕',
                                    onPressed: () =>
                                        setState(() => locked = !locked),
                                    icon: Icon(locked
                                        ? Icons.lock
                                        : Icons.lock_open))),
                          if (!mini && controlsVisible && !locked)
                            Positioned(
                                top: fullscreen
                                    ? MediaQuery.paddingOf(context).top
                                    : 0,
                                left: fullscreen
                                    ? MediaQuery.paddingOf(context).left
                                    : 0,
                                right: fullscreen
                                    ? MediaQuery.paddingOf(context).right
                                    : 0,
                                child: Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(8, 6, 8, 18),
                                    decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                          Colors.black87,
                                          Colors.transparent
                                        ])),
                                    child: Row(children: [
                                      IconButton(
                                          tooltip: '返回',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: fullscreen
                                              ? onFullscreen
                                              : () =>
                                                  Navigator.maybePop(context),
                                          icon: const Icon(Icons.arrow_back)),
                                      Expanded(
                                          child: Text(
                                              '${session.film?.name ?? ''}  ${session.episode?.name ?? ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                    ]))),
                          if (!mini &&
                              v.isPlaying &&
                              controlsVisible &&
                              !locked)
                            Positioned(
                                left: 18,
                                child: IconButton(
                                    tooltip: '快退 10 秒',
                                    onPressed: () => action(
                                        context,
                                        () => c.seekTo(v.position -
                                            const Duration(seconds: 10))),
                                    icon:
                                        const Icon(Icons.replay_10, size: 32))),
                          if (!mini &&
                              v.isPlaying &&
                              controlsVisible &&
                              !locked)
                            Positioned(
                                right: 18,
                                child: IconButton(
                                    tooltip: '快进 10 秒',
                                    onPressed: () => action(
                                        context,
                                        () => c.seekTo(v.position +
                                            const Duration(seconds: 10))),
                                    icon: const Icon(Icons.forward_10,
                                        size: 32))),
                          if (!v.isPlaying &&
                              !v.isBuffering &&
                              controlsVisible &&
                              !locked)
                            IconButton.filled(
                                tooltip: '播放',
                                iconSize: mini ? 24 : 40,
                                onPressed: () => action(context, c.play),
                                icon: const Icon(Icons.play_arrow)),
                          if ((controlsVisible || mini) && !locked)
                            Positioned(
                                bottom: fullscreen
                                    ? MediaQuery.paddingOf(context).bottom
                                    : 0,
                                left: fullscreen
                                    ? MediaQuery.paddingOf(context).left
                                    : 0,
                                right: fullscreen
                                    ? MediaQuery.paddingOf(context).right
                                    : 0,
                                child: Container(
                                    decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                          Colors.transparent,
                                          Colors.black54
                                        ])),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!mini)
                                            VideoProgressIndicator(c,
                                                allowScrubbing: true,
                                                padding: const EdgeInsets.only(
                                                    top: 10, bottom: 4),
                                                colors:
                                                    const VideoProgressColors(
                                                        playedColor:
                                                            Color(0xFFFFD16A))),
                                          Row(children: [
                                            IconButton(
                                                tooltip:
                                                    v.isPlaying ? '暂停' : '播放',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () => action(
                                                    context,
                                                    () => v.isPlaying
                                                        ? c.pause()
                                                        : c.play()),
                                                icon: Icon(v.isPlaying
                                                    ? Icons.pause
                                                    : Icons.play_arrow)),
                                            Expanded(
                                                child: Text(
                                                    mini
                                                        ? (session.episode
                                                                ?.name ??
                                                            '')
                                                        : '${clock(v.position)} / ${clock(v.duration)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 11))),
                                            if (!mini)
                                              PopupMenuButton<double>(
                                                  tooltip: '倍速',
                                                  onSelected: (s) => action(
                                                      context,
                                                      () => c.setPlaybackSpeed(
                                                          s)),
                                                  itemBuilder: (_) => [
                                                        0.75,
                                                        1.0,
                                                        1.25,
                                                        1.5,
                                                        2.0
                                                      ]
                                                          .map((s) =>
                                                              PopupMenuItem(
                                                                  value: s,
                                                                  child: Text(
                                                                      '${s}x')))
                                                          .toList(),
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              6),
                                                      child: Text(
                                                          '${v.playbackSpeed}x',
                                                          style: const TextStyle(
                                                              fontSize: 12)))),
                                            if (onNext != null && !mini)
                                              IconButton(
                                                  tooltip: '下一集',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: onNext,
                                                  icon: const Icon(
                                                      Icons.skip_next)),
                                            if (!mini &&
                                                onSelectEpisode != null)
                                              IconButton(
                                                  tooltip: '选集',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () =>
                                                      selectEpisode(context),
                                                  icon: const Icon(
                                                      Icons.playlist_play)),
                                            if (!mini)
                                              PopupMenuButton<String>(
                                                  tooltip: '更多',
                                                  onSelected: (value) async {
                                                    if (value == 'skip') {
                                                      await showSkipSettings(
                                                          context);
                                                    } else if (value ==
                                                        'sleep') {
                                                      await showModalBottomSheet<
                                                              void>(
                                                          context: context,
                                                          isScrollControlled:
                                                              true,
                                                          builder: (_) =>
                                                              SleepTimerSheet(
                                                                  timer: session
                                                                      .sleepTimer));
                                                    } else if (value ==
                                                        'danmaku') {
                                                      showDanmakuSettings(
                                                          context);
                                                    } else if (value ==
                                                        'send') {
                                                      onSendDanmaku?.call();
                                                    } else if (value ==
                                                        'mini') {
                                                      try {
                                                        await session
                                                            .enterSystemPip();
                                                      } catch (_) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          '桌面小窗未能开启，请检查系统画中画权限后重试')));
                                                        }
                                                      }
                                                    }
                                                  },
                                                  itemBuilder: (_) => const [
                                                        PopupMenuItem(
                                                            value: 'skip',
                                                            child:
                                                                Text('片头片尾')),
                                                        PopupMenuItem(
                                                            value: 'sleep',
                                                            child:
                                                                Text('定时关闭')),
                                                        PopupMenuItem(
                                                            value: 'danmaku',
                                                            child:
                                                                Text('弹幕设置')),
                                                        PopupMenuItem(
                                                            value: 'send',
                                                            child: Text('发弹幕')),
                                                        PopupMenuItem(
                                                            value: 'mini',
                                                            child: Text(
                                                                '画中画（桌面小窗）')),
                                                      ],
                                                  icon: const Icon(
                                                      Icons.more_horiz)),
                                            IconButton(
                                                tooltip: fullscreen
                                                    ? '退出全屏'
                                                    : mini
                                                        ? '返回详情'
                                                        : '全屏',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: onFullscreen,
                                                icon: Icon(fullscreen
                                                    ? Icons.fullscreen_exit
                                                    : Icons.fullscreen))
                                          ])
                                        ])))
                        ]))));
  }
}
