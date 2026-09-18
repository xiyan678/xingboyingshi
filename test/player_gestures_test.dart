import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:xingbo_app/player_gestures.dart';

class GesturePlayer extends VideoPlayerController {
  final speeds = <double>[];
  Duration? sought;
  GesturePlayer()
      : super.networkUrl(Uri.parse('https://example.com/video.mp4')) {
    value = const VideoPlayerValue(
        duration: Duration(minutes: 10),
        position: Duration(minutes: 2),
        isInitialized: true,
        isPlaying: true,
        playbackSpeed: 1.5);
  }
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> seekTo(Duration position) async {
    sought = position;
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }
}

void main() {
  testWidgets('long press temporarily speeds up and restores original rate',
      (tester) async {
    final controller = GesturePlayer();
    await tester.pumpWidget(MaterialApp(
        home: PlayerGestures(controller: controller, onTap: () {})));
    final touch = await tester.startGesture(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.speeds, [3]);
    await touch.up();
    await tester.pump();
    expect(controller.speeds, [3, 1.5]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('horizontal drag seeks on release and double tap pauses',
      (tester) async {
    final controller = GesturePlayer();
    await tester.pumpWidget(MaterialApp(
        home: PlayerGestures(controller: controller, onTap: () {})));
    await tester.drag(find.byType(PlayerGestures), const Offset(200, 0));
    await tester.pump();
    expect(controller.sought! > const Duration(minutes: 2), isTrue);
    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(300, 200));
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
  });
}
