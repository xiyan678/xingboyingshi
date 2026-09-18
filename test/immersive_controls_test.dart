import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:xingbo_app/immersive_controls.dart';
import 'package:xingbo_app/fullscreen_player.dart';

void main() {
  testWidgets(
      'playing controls hide, tap restores, pause keeps controls visible',
      (tester) async {
    final playback = ValueNotifier(const VideoPlayerValue(
        duration: Duration(minutes: 5), isInitialized: true, isPlaying: true));
    addTearDown(playback.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ImmersiveControls(
                playback: playback,
                builder: (_, visible, toggle) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: toggle,
                      child: SizedBox.expand(
                          child: visible
                              ? const Text('Controls')
                              : const SizedBox()),
                    )))));
    expect(find.text('Controls'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Controls'), findsNothing);
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(find.text('Controls'), findsOneWidget);
    playback.value = playback.value.copyWith(isPlaying: false);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Controls'), findsOneWidget);
    playback.value = playback.value.copyWith(isPlaying: true);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Controls'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dragging never hides the progress controls mid-gesture',
      (tester) async {
    final playback = ValueNotifier(const VideoPlayerValue(
        duration: Duration(minutes: 5), isInitialized: true, isPlaying: true));
    addTearDown(playback.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ImmersiveControls(
            playback: playback,
            builder: (_, visible, toggle) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: SizedBox.expand(
                      child:
                          visible ? const Text('Controls') : const SizedBox()),
                ))));
    final gesture = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Controls'), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Controls'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fullscreen requests landscape and restores system UI on exit',
      (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: FullscreenPlayer(builder: (_) => const SizedBox.expand())));
    expect(
        calls.any((c) =>
            c.method == 'SystemChrome.setEnabledSystemUIMode' &&
            c.arguments == 'SystemUiMode.immersiveSticky'),
        isTrue);
    expect(
        calls.any((c) =>
            c.method == 'SystemChrome.setPreferredOrientations' &&
            (c.arguments as List).contains('DeviceOrientation.landscapeLeft')),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(calls.last.arguments, contains('DeviceOrientation.portraitUp'));
  });
}
