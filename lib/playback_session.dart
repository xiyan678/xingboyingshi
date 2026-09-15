import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:native_picture_in_picture/native_picture_in_picture.dart';
import 'package:native_picture_in_picture/pip_event.dart';
import 'api.dart';
import 'library.dart';
import 'service.dart';

class PlaybackSession extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = PlaybackSession();
  final pip = NativePictureInPicture();
  VideoPlayerController? controller;
  Film? film;
  Episode? episode;
  Library? library;
  String lineName = '';
  int episodeIndex = 1;
  String? _ownerId;
  bool mini = false, pipActive = false, ready = false;
  String? error;
  int _generation = 0, _lastSaved = -1;
  StreamSubscription<PipEvent>? _pipEvents;
  Timer? _pipSave;
  bool _pipReturning = false;
  PlaybackSession() {
    WidgetsBinding.instance.addObserver(this);
  }
  Future<void> open(Film f, Episode e, Library lib,
      {int resume = 0, String line = '', int index = 1}) async {
    if (film?.id == f.id &&
        _ownerId == lib.accountId &&
        episode?.url == e.url &&
        controller != null &&
        ready) {
      mini = false;
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    await close(increment: false);
    if (generation != _generation) return;
    film = f;
    episode = e;
    library = lib;
    _ownerId = lib.accountId;
    lineName = line;
    episodeIndex = index;
    mini = false;
    error = null;
    ready = false;
    _lastSaved = -1;
    if (Uri.tryParse(e.url)?.scheme != 'https') {
      error = '此线路不是 HTTPS 视频地址，请切换线路';
      notifyListeners();
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(e.url));
    controller = c;
    notifyListeners();
    try {
      await c.initialize().timeout(const Duration(seconds: 30));
      if (generation != _generation) return;
      if (resume > 0 && resume < c.value.duration.inSeconds - 5) {
        await c.seekTo(Duration(seconds: resume));
      }
      if (generation != _generation) return;
      c.addListener(_tick);
      ready = true;
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
    if (c.value.hasError && error == null) {
      error = '播放中断，请切换线路';
      notifyListeners();
    }
    if (!pipActive &&
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
    final pos = seconds ?? c.value.position.inSeconds;
    if (pos <= 0) return;
    unawaited(lib.remember(
        WatchRecord(f, e.url, e.name, pos,
            lineName: lineName, episodeIndex: episodeIndex),
        forceSync: force));
  }

  void minimize() {
    if (ready) {
      mini = true;
      notifyListeners();
    }
  }

  Future<void> pauseAndSave() async {
    await controller?.pause();
    save(force: true);
  }

  Future<void> enterSystemPip() async {
    if (pipActive) return;
    final c = controller, e = episode;
    if (c == null || e == null || !ready) return;
    if (!await pip.isPipSupported()) {
      throw ServiceError('当前设备不支持系统画中画，可使用应用内小窗');
    }
    final generation = _generation;
    final wasPlaying = c.value.isPlaying;
    try {
      await pip.initialize(e.url);
      if (generation != _generation) {
        await pip.dispose();
        return;
      }
      await pip.setAutoPipEnabled(false);
      await _pipEvents?.cancel();
      _pipEvents = pip.onPipEvent.listen((event) {
        if (event == PipEvent.restoreUI || event == PipEvent.didStop) {
          unawaited(_restorePip(generation));
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
    }
  }

  Future<void> _restorePip(int generation) async {
    if (_pipReturning || !pipActive || generation != _generation) return;
    _pipReturning = true;
    _pipSave?.cancel();
    try {
      final pos = await pip.getPosition();
      await pip.pause();
      if (generation != _generation) return;
      await controller?.seekTo(pos);
      save(seconds: pos.inSeconds, force: true);
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
      if (pipActive) unawaited(_checkPipReturn());
    } else if (!pipActive) {
      unawaited(pauseAndSave());
    }
  }

  Future<void> _checkPipReturn() async {
    try {
      if (!await pip.isPipActive()) await _restorePip(_generation);
    } catch (_) {}
  }

  Future<void> close({bool increment = true}) async {
    if (increment) _generation++;
    save(force: true);
    _pipSave?.cancel();
    await _pipEvents?.cancel();
    _pipEvents = null;
    if (pipActive) {
      try {
        save(seconds: (await pip.getPosition()).inSeconds, force: true);
        await pip.stopPiP();
        await pip.dispose();
      } catch (_) {}
    }
    final old = controller;
    controller = null;
    old?.removeListener(_tick);
    ready = false;
    mini = false;
    pipActive = false;
    _pipReturning = false;
    if (old != null) await old.dispose();
    notifyListeners();
  }
}
