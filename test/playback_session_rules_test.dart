import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xingbo_app/ad_free_source.dart';
import 'package:xingbo_app/api.dart';
import 'package:xingbo_app/hls_ad_filter.dart';
import 'package:xingbo_app/library.dart';
import 'package:xingbo_app/playback_rules.dart';
import 'package:xingbo_app/playback_session.dart';
import 'package:xingbo_app/ios_shared_pip.dart';

class RuleVideoPlatform extends VideoPlayerPlatform {
  final positions = <int, Duration>{};
  int nextId = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    positions[++nextId] = Duration.zero;
    return nextId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 10),
      size: const Size(1280, 720)));
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allow) async {}
  @override
  Future<void> setMixWithOthers(bool mix) async {}
  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }
}

class RuleSession extends PlaybackSession {
  RuleSession({super.prepareSource});
  @override
  Future<void> reportPlay() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackSession session;
  late Library library;
  final film = Film({'vod_id': 'rules', 'vod_name': 'Rules'});
  final first = Episode('one', 'https://example.com/one.mp4');
  final second = Episode('two', 'https://example.com/two.mp4');
  setUp(() async {
    VideoPlayerPlatform.instance = RuleVideoPlatform();
    SharedPreferences.setMockInitialValues({});
    library = Library(await SharedPreferences.getInstance());
    session = RuleSession(prepareSource: (uri) async => AdFreeSource(uri));
  });
  tearDown(() async {
    await session.close();
    session.sleepTimer.dispose();
    WidgetsBinding.instance.removeObserver(session);
    session.dispose();
    library.dispose();
  });

  test('credits stop current episode before automatic next', () async {
    var next = 0;
    await session.open(film, first, library, onCompleted: () => next++);
    expect(session.ready, isTrue);
    await session.updateSkipSettings(
        const SkipSettings(enabled: true, introSeconds: 30, outroSeconds: 60));
    session.sleepTimer.afterEpisodes(1);
    final c = session.controller!;
    c.value =
        c.value.copyWith(isPlaying: true, position: const Duration(minutes: 9));
    await Future<void>.delayed(Duration.zero);
    expect(next, 0);
    expect(c.value.isPlaying, isFalse);
    expect(session.sleepTimer.stopped, isTrue);
    await session.close();
  });

  test('two episodes survive switch, duplicate completion cannot double count',
      () async {
    var next = 0;
    await session.open(film, first, library, onCompleted: () => next++);
    session.sleepTimer.afterEpisodes(2);
    final firstController = session.controller!;
    firstController.value = firstController.value.copyWith(isCompleted: true);
    await Future<void>.delayed(Duration.zero);
    firstController.value = firstController.value.copyWith(isBuffering: true);
    await Future<void>.delayed(Duration.zero);
    expect(next, 1);
    expect(session.sleepTimer.remainingEpisodes, 1);
    await session.open(film, second, library, onCompleted: () => next++);
    session.controller!.value =
        session.controller!.value.copyWith(isCompleted: true);
    await Future<void>.delayed(Duration.zero);
    expect(next, 1);
    expect(session.sleepTimer.stopped, isTrue);
    expect(session.controller!.value.isPlaying, isFalse);
    await session.close();
  });

  test('manual episode switch does not consume sleep episode count', () async {
    await session.open(film, first, library);
    session.sleepTimer.afterEpisodes(2);
    await session.open(film, second, library);
    expect(session.sleepTimer.remainingEpisodes, 2);
    await session.close();
  });

  test('intro uses filtered timeline and does not trap manual rewind',
      () async {
    await session.close();
    session.sleepTimer.dispose();
    WidgetsBinding.instance.removeObserver(session);
    session.dispose();
    session = RuleSession(
        prepareSource: (uri) async => AdFreeSource(uri,
            playlist: const FilteredPlaylist(
                '',
                [AdCut(Duration(seconds: 20), Duration(seconds: 40))],
                1,
                Duration(seconds: 620))));
    await session.open(film, first, library);
    await session.updateSkipSettings(
        const SkipSettings(enabled: true, introSeconds: 90, outroSeconds: 60));
    final c = session.controller!;
    c.value = c.value.copyWith(isPlaying: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.value.position, const Duration(seconds: 70));
    expect(
        session.sourcePosition(c.value.position), const Duration(seconds: 90));
    c.value = c.value.copyWith(position: const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(c.value.position, const Duration(seconds: 10));
    session.sleepTimer.afterEpisodes(1);
    c.value = c.value.copyWith(position: const Duration(seconds: 539));
    await Future<void>.delayed(Duration.zero);
    expect(session.sleepTimer.stopped, isFalse);
    c.value = c.value.copyWith(position: const Duration(seconds: 540));
    await Future<void>.delayed(Duration.zero);
    expect(session.sleepTimer.stopped, isTrue);
    expect(c.value.isPlaying, isFalse);
    await session.close();
  });

  test('deadline pauses playback without advancing', () async {
    var next = 0;
    await session.open(film, first, library, onCompleted: () => next++);
    final c = session.controller!;
    c.value = c.value.copyWith(isPlaying: true);
    session.sleepTimer.after(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.value.isPlaying, isFalse);
    expect(next, 0);
    c.value = c.value.copyWith(isPlaying: true);
    await Future<void>.delayed(Duration.zero);
    expect(session.sleepTimer.stopped, isFalse);
    await session.close();
  });

  test('paused or buffering credits do not consume an episode', () async {
    var next = 0;
    await session.open(film, first, library, onCompleted: () => next++);
    await session.updateSkipSettings(
        const SkipSettings(enabled: true, introSeconds: 0, outroSeconds: 60));
    session.sleepTimer.afterEpisodes(2);
    final c = session.controller!;
    c.value = c.value.copyWith(position: const Duration(minutes: 9));
    await Future<void>.delayed(Duration.zero);
    expect(session.sleepTimer.remainingEpisodes, 2);
    c.value = c.value.copyWith(isPlaying: true, isBuffering: true);
    await Future<void>.delayed(Duration.zero);
    expect(next, 0);
    c.value = c.value.copyWith(isBuffering: false);
    await Future<void>.delayed(Duration.zero);
    expect(next, 1);
    expect(session.sleepTimer.remainingEpisodes, 1);
    await session.close();
  });

  test('sleep deadline during iOS PiP startup cannot restart playback',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final started = Completer<void>();
    final finishStart = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(IosSharedPip.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        started.complete();
        await finishStart.future;
      }
      return null;
    });
    try {
      await session.open(film, first, library);
      final entering = session.enterSystemPip();
      await started.future;
      session.sleepTimer.after(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      finishStart.complete();
      await entering;
      expect(session.pipActive, isFalse);
      expect(session.controller!.value.isPlaying, isFalse);
      expect(calls.last, 'close');
      await session.close();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(IosSharedPip.channel, null);
    }
  });
}
