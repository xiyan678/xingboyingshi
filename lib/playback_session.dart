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
import 'playback_rules.dart';
import 'package:flutter/foundation.dart';

class PlaybackSession extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = PlaybackSession();
  final pip = NativePictureInPicture();
  final _iosPip = IosSharedPip();
  bool get _usesSharedPip =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  VideoPlayerController? controller;
  AdFreeSource? _playbackSource;
  final Future<AdFreeSource> Function(Uri) _prepareSource;
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
  SkipSettings skipSettings = const SkipSettings();
  late final PlaybackSleepTimer sleepTimer;
  bool _introHandled = false;
  bool _sleepStopping = false, _lastPlaying = false;

  Future<void> updateSkipSettings(SkipSettings settings) async {
    final f = film, lib = library;
    if (f == null || lib == null) return;
    skipSettings = settings;
    _introHandled = false;
    notifyListeners();
    await settings.save(lib.prefs, f.id, lib.accountId);
  }

  Future<void> _stopForSleep() async {
    _sleepStopping = true;
    _autoAdvanceFilmId = null;
    _completionHandled = true;
    final generation = _generation;
    try {
      await pauseAndSave();
      if (generation != _generation) return;
      if (pipActive && _usesSharedPip) {
        await _iosPip.close();
        if (generation == _generation) pipActive = false;
      } else if (pipActive) {
        await _restorePip(generation);
        if (generation != _generation) return;
        await pip.stopPiP();
      }
    } catch (_) {
      if (generation == _generation) {
        error = '定时停止未能完成，请手动暂停播放';
      }
    } finally {
      _sleepStopping = false;
    }
    if (generation == _generation) notifyListeners();
  }

  Future<void> reportPlay() async {
    try {
      await AppService.instance.call('play_event', body: {'vod_id': film!.id});
    } catch (_) {}
  }

  StreamSubscription<PipEvent>? _pipEvents;
  Timer? _pipSave;
  bool _pipReturning = false;
  bool _pipStarting = false;
  PlaybackSession({Future<AdFreeSource> Function(Uri)? prepareSource})
      : _prepareSource = prepareSource ?? prepareAdFreeSource {
    sleepTimer = PlaybackSleepTimer(onStop: () => unawaited(_stopForSleep()));
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
      {int resume = 0,
      String line = '',
      int index = 1,
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
    _introHandled = false;
    _lastPlaying = false;
    skipSettings = SkipSettings.load(lib.prefs, f.id, lib.accountId);
    _onCompleted = onCompleted;
    if (Uri.tryParse(e.url)?.scheme != 'https') {
      error = '此线路不是 HTTPS 视频地址，请切换线路';
      notifyListeners();
      return;
    }
    notifyListeners();
    final prepared = await _prepareSource(Uri.parse(e.url));
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
      final resumePosition = playAutomatically
          ? Duration.zero
          : prepared.toPlayback(Duration(seconds: resume));
      if (resumePosition > Duration.zero &&
          resumePosition < c.value.duration - const Duration(seconds: 5)) {
        await c.seekTo(resumePosition);
      }
      if (generation != _generation) return;
      c.addListener(_tick);
      ready = true;
      sleepTimer.checkDeadline();
      if (playAutomatically && !sleepTimer.stopped) await c.play();
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
    final started = c.value.isPlaying && !_lastPlaying;
    _lastPlaying = c.value.isPlaying;
    if (started && sleepTimer.stopped && !_sleepStopping) {
      sleepTimer.cancel();
      _completionHandled = false;
    }
    if (!pipActive || _usesSharedPip) {
      _applyPlaybackRules(c.value.position,
          playing: c.value.isPlaying && !c.value.isBuffering,
          completed: c.value.isCompleted);
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

  void _applyPlaybackRules(Duration position,
      {required bool playing, required bool completed}) {
    final c = controller;
    if (c == null || !ready || c.value.hasError) return;
    sleepTimer.checkDeadline();
    if (sleepTimer.stopped) return;
    final duration =
        _playbackSource?.playlist?.originalDuration ?? c.value.duration;
    final source = sourcePosition(position);
    final skip = skipSettings.appliesTo(duration);
    if (playing && !_introHandled && skip) {
      _introHandled = true;
      final intro = Duration(seconds: skipSettings.introSeconds);
      if (source < intro) {
        final target = _playbackSource?.toPlayback(intro) ?? intro;
        unawaited(_seekIntro(c, target));
        return;
      }
    }
    final atOutro = playing &&
        skip &&
        skipSettings.outroSeconds > 0 &&
        source >= duration - Duration(seconds: skipSettings.outroSeconds);
    if ((!completed && !atOutro) || _completionHandled) return;
    _completionHandled = true;
    final generation = _generation;
    scheduleMicrotask(() async {
      if (generation != _generation || controller != c) return;
      save(force: true);
      final advance = _onCompleted;
      if (sleepTimer.episodeEnded(hasNext: advance != null)) return;
      if (advance != null) {
        _autoAdvanceFilmId = film?.id;
        advance();
      } else if (atOutro) {
        // At the final episode, stop at the credits rather than playing them.
        try {
          if (pipActive && !_usesSharedPip) await pip.pause();
          await c.pause();
        } catch (_) {}
      }
    });
  }

  Future<void> _seekIntro(VideoPlayerController c, Duration target) async {
    try {
      if (pipActive && !_usesSharedPip) {
        await pip.seekTo(target);
      } else {
        await c.seekTo(target);
      }
    } catch (_) {
      // Continue playing if the source cannot seek; never retry in a loop.
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
    final pos = sourcePosition(
            seconds == null ? c.value.position : Duration(seconds: seconds))
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
    if (sleepTimer.stopped) {
      sleepTimer.cancel();
      _completionHandled = false;
    }
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
        if (sleepTimer.stopped) {
          await c.pause();
          await _iosPip.close();
          return;
        }
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
      await pip
          .initialize((_playbackSource?.uri ?? Uri.parse(e.url)).toString());
      if (generation != _generation || sleepTimer.stopped) {
        await pip.dispose();
        return;
      }
      await pip.setAutoPipEnabled(false);
      await _pipEvents?.cancel();
      _pipEvents = pip.onPipEvent.listen((event) {
        if (event == PipEvent.restoreUI || event == PipEvent.didStop) {
          unawaited(
              _restorePip(generation, resume: event == PipEvent.restoreUI));
        }
      });
      await pip.seekTo(c.value.position);
      if (generation != _generation || sleepTimer.stopped) {
        await pip.dispose();
        return;
      }
      pipActive = true;
      await c.pause();
      await pip.startPiP();
      if (generation != _generation || sleepTimer.stopped) {
        await pip.stopPiP();
        if (generation == _generation) pipActive = false;
        return;
      }
      await pip.play();
      if (generation != _generation || sleepTimer.stopped) {
        await pip.stopPiP();
        if (generation == _generation) pipActive = false;
        return;
      }
      var previousPosition = c.value.position;
      var polling = false;
      _pipSave = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (polling) return;
        polling = true;
        try {
          final position = await pip.getPosition();
          if (generation == _generation && pipActive) {
            _applyPlaybackRules(position,
                playing: position > previousPosition,
                completed: c.value.duration > Duration.zero &&
                    position >= c.value.duration);
            previousPosition = position;
            if ((position.inSeconds - _lastSaved).abs() >= 5) {
              _lastSaved = position.inSeconds;
              save(seconds: position.inSeconds, force: true);
            }
          }
        } catch (_) {
        } finally {
          polling = false;
        }
      });
      notifyListeners();
    } catch (e) {
      pipActive = false;
      try {
        await pip.dispose();
      } catch (_) {}
      if (wasPlaying && generation == _generation && !sleepTimer.stopped) {
        await c.play();
      }
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
      if (resume && !sleepTimer.stopped) await controller?.play();
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
      sleepTimer.checkDeadline();
      if (pipActive && !_usesSharedPip) unawaited(_checkPipReturn());
    } else if (!pipActive && !_pipStarting) {
      unawaited(pauseAndSave());
    }
  }

  Future<void> _checkPipReturn() async {
    try {
      if (!await pip.isPipActive()) {
        await _restorePip(_generation, resume: true);
      }
    } catch (_) {}
  }

  Future<void> close({bool increment = true}) async {
    if (increment) {
      _generation++;
      _autoAdvanceFilmId = null;
      sleepTimer.cancel();
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
