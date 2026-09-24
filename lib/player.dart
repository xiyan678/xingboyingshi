import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
import 'desktop_mizhi_player.dart';

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

class _PlayerState extends State<Player> {
  final session = PlaybackSession.instance;
  bool _fullscreenOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isWindows) open();
    });
  }

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> open() =>
      session.open(widget.film, widget.episode, widget.library,
          resume: widget.resumeSeconds,
          line: widget.lineName,
          index: widget.episodeIndex,
          onCompleted: widget.onNext);
  @override
  void dispose() {
    if (!_isWindows) {
      unawaited(SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]));
    }
    if (!_isWindows &&
        !session.pipActive &&
        session.episode?.url == widget.episode.url) {
      unawaited(session.pauseAndSave());
    }
    super.dispose();
  }

  Future<void> showFullscreen() async {
    if (_fullscreenOpen) return;
    _fullscreenOpen = true;
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
  Widget build(BuildContext context) => _isWindows
      ? Column(children: [
          AspectRatio(
              aspectRatio: 16 / 9,
              child: DesktopMizhiPlayer(
                  film: widget.film, episode: widget.episode)),
          const Advertising(slot: 'player_bottom'),
        ])
      : AnimatedBuilder(
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
                                ? const Center(
                                    child: CircularProgressIndicator())
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
  static const accent = Color(0xFF00C7B2);
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

  Widget textAction(String label, VoidCallback onPressed) => Tooltip(
      message: label,
      child: TextButton(
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(44, 40)),
          onPressed: onPressed,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))));

  Future<void> showMore(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xF21D2025),
        builder: (_) => SafeArea(
                child: Wrap(children: [
              const ListTile(
                  title: Text('播放设置',
                      style: TextStyle(fontWeight: FontWeight.w700))),
              ListTile(
                  leading: const Icon(Icons.picture_in_picture_alt_outlined),
                  title: const Text('画中画'),
                  onTap: () => Navigator.pop(context, 'pip')),
              ListTile(
                  leading: const Icon(Icons.content_cut),
                  title: const Text('片头片尾'),
                  onTap: () => Navigator.pop(context, 'skip')),
              ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('定时关闭'),
                  onTap: () => Navigator.pop(context, 'sleep')),
            ])));
    if (!context.mounted || selected == null) return;
    if (selected == 'skip') {
      await showSkipSettings(context);
    } else if (selected == 'sleep') {
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) =>
              SleepTimerSheet(timer: PlaybackSession.instance.sleepTimer));
    } else if (selected == 'pip') {
      try {
        await PlaybackSession.instance.enterSystemPip();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('画中画未能开启，请在系统设置中允许画中画权限')));
        }
      }
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
                                      if (fullscreen) textAction('正常模式', () {}),
                                      if (fullscreen)
                                        IconButton(
                                            tooltip: '投屏',
                                            onPressed: () =>
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                        const SnackBar(
                                                            content: Text(
                                                                '当前版本暂不支持投屏'))),
                                            icon:
                                                const Icon(Icons.tv_outlined)),
                                      IconButton(
                                          tooltip: '更多',
                                          onPressed: () => showMore(context),
                                          icon: const Icon(Icons.more_horiz)),
                                    ]))),
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
                                                        playedColor: accent,
                                                        bufferedColor:
                                                            Color(0x88FFFFFF),
                                                        backgroundColor:
                                                            Color(0x55FFFFFF))),
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
                                            if (fullscreen &&
                                                onNext != null &&
                                                !mini)
                                              IconButton(
                                                  tooltip: '下一集',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: onNext,
                                                  icon: const Icon(
                                                      Icons.skip_next)),
                                            if (!mini)
                                              AnimatedBuilder(
                                                  animation:
                                                      DanmakuSettings.instance,
                                                  builder: (context, _) =>
                                                      IconButton(
                                                          tooltip:
                                                              DanmakuSettings
                                                                      .instance
                                                                      .enabled
                                                                  ? '关闭弹幕'
                                                                  : '开启弹幕',
                                                          onPressed: () {
                                                            final settings =
                                                                DanmakuSettings
                                                                    .instance;
                                                            settings.enabled =
                                                                !settings
                                                                    .enabled;
                                                            settings.persist();
                                                          },
                                                          icon: Icon(
                                                              Icons
                                                                  .subtitles_outlined,
                                                              color: DanmakuSettings
                                                                      .instance
                                                                      .enabled
                                                                  ? accent
                                                                  : Colors
                                                                      .white70))),
                                            if (fullscreen && !mini)
                                              IconButton(
                                                  tooltip: '弹幕设置',
                                                  onPressed: () =>
                                                      showDanmakuSettings(
                                                          context),
                                                  icon: const Icon(
                                                      Icons.tune_outlined)),
                                            if (fullscreen && !mini)
                                              Expanded(
                                                  flex: 2,
                                                  child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                      onTap: onSendDanmaku,
                                                      child: Container(
                                                          height: 36,
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 14),
                                                          decoration: BoxDecoration(
                                                              color: Colors
                                                                  .white12,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      20)),
                                                          child: const Text('发弹幕',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white60,
                                                                  fontSize:
                                                                      13))))),
                                            if (fullscreen && !mini)
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
                                                              8),
                                                      child: Text(v
                                                                  .playbackSpeed ==
                                                              1
                                                          ? '倍速'
                                                          : '${v.playbackSpeed}x'))),
                                            if (fullscreen && !mini)
                                              textAction(
                                                  '自动',
                                                  () => ScaffoldMessenger.of(
                                                          context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              '当前播放源将自动选择可用清晰度')))),
                                            if (!mini &&
                                                onSelectEpisode != null)
                                              textAction('选集',
                                                  () => selectEpisode(context)),
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
