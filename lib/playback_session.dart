import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:native_picture_in_picture/native_picture_in_picture.dart';
import 'package:native_picture_in_picture/pip_event.dart';
import 'api.dart';
import 'library.dart';
import 'service.dart';
import 'ad_free_source.dart';
import 'ios_shared_pip.dart';
import 'package:flutter/foundation.dart';

class PlaybackSession extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = PlaybackSession();
  final pip = NativePictureInPicture();
  final _iosPip = IosSharedPip();
  bool get _usesSharedPip => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  VideoPlayerController? controller;
  AdFreeSource? _playbackSource;
  Duration sourcePosition(Duration position) =>
      _playbackSource?.toSource(position) ?? position;
  Film? film;
  Episode? episode;
  Library? library;
  String lineName = '';
  int episodeIndex = 1;
  String? _ownerId;
  bool pipActive = false, ready = false;
  String? error;
  int _generation = 0, _lastSaved = -1;
  bool _playReported = false;
  VoidCallback? _onCompleted;
  bool _completionHandled = false;
  String? _autoAdvanceFilmId;
  Future<void> reportPlay() async {
    try { await AppService.instance.call('play_event', body: {'vod_id': film!.id}); } catch (_) {}
  }
  StreamSubscription<PipEvent>? _pipEvents;
  Timer? _pipSave;
  bool _pipReturning = false;
  bool _pipStarting = false;
  PlaybackSession() {
    WidgetsBinding.instance.addObserver(this);
    _iosPip.onStopped = (id, restore) {
      // Pinned video_player 2.14 exposes the native ID for this local bridge.
      // ignore: invalid_use_of_visible_for_testing_member
      if (controller?.playerId != id) return;
      pipActive = false;
      if (!restore) unawaited(pauseAndSave());
      save(force: true);
      notifyListeners();
    };
  }
  Future<void> open(Film f, Episode e, Library lib,
      {int resume = 0, String line = '', int index = 1,
      VoidCallback? onCompleted}) async {
    if (film?.id == f.id &&
        _ownerId == lib.accountId &&
        episode?.url == e.url &&
        controller != null &&
        ready) {
      _onCompleted = onCompleted;
  
      notifyListeners();
      return;
    }
    final playAutomatically = _autoAdvanceFilmId == f.id;
    _autoAdvanceFilmId = null;
    final generation = ++_generation;
    await close(increment: false);
    if (generation != _generation) return;
    film = f;
    episode = e;
    library = lib;
    _ownerId = lib.accountId;
    lineName = line;
    episodeIndex = index;

    error = null;
    ready = false;
    _lastSaved = -1;
    _playReported = false;
    _completionHandled = false;
    _onCompleted = onCompleted;
    if (Uri.tryParse(e.url)?.scheme != 'https') {
      error = '此线路不是 HTTPS 视频地址，请切换线路';
      notifyListeners();
      return;
    }
    notifyListeners();
    final prepared = await prepareAdFreeSource(Uri.parse(e.url));
    if (generation != _generation) {
      await prepared.dispose();
      return;
    }
    _playbackSource = prepared;
    final c = VideoPlayerController.networkUrl(prepared.uri,
        formatHint: prepared.playlist != null ? VideoFormat.hls : null,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true));
    controller = c;
    notifyListeners();
    try {
      await c.initialize().timeout(const Duration(seconds: 30));
      if (generation != _generation) return;
      final resumePosition = playAutomatically ? Duration.zero :
          prepared.toPlayback(Duration(seconds: resume));
      if (resumePosition > Duration.zero &&
          resumePosition < c.value.duration - const Duration(seconds: 5)) {
        await c.seekTo(resumePosition);
      }
      if (generation != _generation) return;
      c.addListener(_tick);
      ready = true;
      if (playAutomatically) await c.play();
      if (generation != _generation) return;
      notifyListeners();
    } catch (_) {
      if (generation == _generation) {
        error = '此线路无法播放，请重试或切换线路';
        notifyListeners();
      }
    }
  }

  void _tick() {
    final c = controller;
    if (c == null) return;
    if (ready && c.value.isCompleted && !c.value.hasError &&
        !_completionHandled && _onCompleted != null &&
        (!pipActive || _usesSharedPip)) {
      _completionHandled = true;
      final generation = _generation;
      final advance = _onCompleted!;
      scheduleMicrotask(() {
        if (generation != _generation || controller != c) return;
        save(force: true);
        _autoAdvanceFilmId = film?.id;
        advance();
      });
    }
    if (c.value.isPlaying && !_playReported && film != null) {
      _playReported = true;
      unawaited(reportPlay());
    }
    if (c.value.hasError && error == null) {
      error = '播放中断，请切换线路';
      notifyListeners();
    }
    if ((!pipActive || _usesSharedPip) &&
        c.value.isInitialized &&
        (c.value.position.inSeconds - _lastSaved).abs() >= 5) {
      _lastSaved = c.value.position.inSeconds;
      save();
    }
  }

  void save({int? seconds, bool force = false}) {
    final f = film, e = episode, lib = library, c = controller;
    if (f == null ||
        e == null ||
        lib == null ||
        c == null ||
        !c.value.isInitialized) {
      return;
    }
    if (lib.accountId != _ownerId) return;
    final pos = sourcePosition(seconds == null
            ? c.value.position
            : Duration(seconds: seconds))
        .inSeconds;
    if (pos <= 0) return;
    unawaited(lib.remember(
        WatchRecord(f, e.url, e.name, pos,
            lineName: lineName, episodeIndex: episodeIndex),
        forceSync: force));
  }

  Future<void> pauseAndSave() async {
    await controller?.pause();
    save(force: true);
  }

  Future<void> enterSystemPip() async {
    if (pipActive || _pipStarting) return;
    final c = controller, e = episode;
    if (c == null || e == null || !ready) return;
    if (_usesSharedPip) {
      final generation = _generation;
      final wasPlaying = c.value.isPlaying;
      _pipStarting = true;
      try {
        await c.play();
        if (generation != _generation) return;
        // Same native ID is used by the vendored AVFoundation player registry.
        // ignore: invalid_use_of_visible_for_testing_member
        await _iosPip.start(c.playerId);
        if (generation != _generation) return;
        pipActive = true;
        notifyListeners();
      } catch (_) {
        if (!wasPlaying && generation == _generation) await c.pause();
        rethrow;
      } finally {
        _pipStarting = false;
      }
      return;
    }
    if (!await pip.isPipSupported()) {
      throw ServiceError('当前设备不支持系统画中画');
    }
    final generation = _generation;
    final wasPlaying = c.value.isPlaying;
    _pipStarting = true;
    try {
      await pip.initialize((_playbackSource?.uri ?? Uri.parse(e.url)).toString());
      if (generation != _generation) {
        await pip.dispose();
        return;
      }
      await pip.setAutoPipEnabled(false);
      await _pipEvents?.cancel();
      _pipEvents = pip.onPipEvent.listen((event) {
        if (event == PipEvent.restoreUI || event == PipEvent.didStop) {
          unawaited(_restorePip(generation, resume: event == PipEvent.restoreUI));
        }
      });
      await pip.seekTo(c.value.position);
      if (generation != _generation) {
        await pip.dispose();
        return;
      }
      pipActive = true;
      await c.pause();
      await pip.startPiP();
      await pip.play();
      _pipSave = Timer.periodic(const Duration(seconds: 10), (_) async {
        try {
          final position = await pip.getPosition();
          if (generation == _generation && pipActive) {
            save(seconds: position.inSeconds, force: true);
          }
        } catch (_) {}
      });
      notifyListeners();
    } catch (e) {
      pipActive = false;
      try {
        await pip.dispose();
      } catch (_) {}
      if (wasPlaying && generation == _generation) await c.play();
      rethrow;
    } finally {
      _pipStarting = false;
    }
  }

  Future<void> _restorePip(int generation, {bool resume = false}) async {
    if (_pipReturning || !pipActive || generation != _generation) return;
    _pipReturning = true;
    _pipSave?.cancel();
    try {
      final pos = await pip.getPosition();
      await pip.pause();
      if (generation != _generation) return;
      await controller?.seekTo(pos);
      save(seconds: pos.inSeconds, force: true);
      if (resume) await controller?.play();
    } catch (_) {
    } finally {
      if (generation == _generation) {
        pipActive = false;
        _pipReturning = false;
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (pipActive && !_usesSharedPip) unawaited(_checkPipReturn());
    } else if (!pipActive && !_pipStarting) {
      unawaited(pauseAndSave());
    }
  }

  Future<void> _checkPipReturn() async {
    try {
      if (!await pip.isPipActive()) await _restorePip(_generation, resume: true);
    } catch (_) {}
  }

  Future<void> close({bool increment = true}) async {
    if (increment) {
      _generation++;
      _autoAdvanceFilmId = null;
    }
    _onCompleted = null;
    save(force: true);
    _pipSave?.cancel();
    await _pipEvents?.cancel();
    _pipEvents = null;
    if (_usesSharedPip) {
      await _iosPip.close();
    } else if (pipActive) {
      try {
        save(seconds: (await pip.getPosition()).inSeconds, force: true);
        await pip.stopPiP();
        await pip.dispose();
      } catch (_) {}
    }
    final old = controller;
    final oldSource = _playbackSource;
    _playbackSource = null;
    controller = null;
    old?.removeListener(_tick);
    ready = false;

    pipActive = false;
    _pipReturning = false;
    if (old != null) await old.dispose();
    await oldSource?.dispose();
    notifyListeners();
  }
}

